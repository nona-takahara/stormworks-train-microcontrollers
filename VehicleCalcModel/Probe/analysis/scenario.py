#!/usr/bin/env python
# Precomputes a speed scenario (constant-rate speed changes and holds), runs it on the probe, and compares it.
#
#   python scenario.py fit    --name A1 --acc 0.8 "25:5 110:5 80:5 95:5 75:5 25:5 15:5 stop"
#   python scenario.py verify --name V1 "35:10@0.7 105:5@0.9 65:5@r 90:5@0.5 45:5@r/? stop@r/r"
#   python scenario.py plan   --name T  "..."          (plan only: writes the files and prints the distance, does not run)
#
# Spec, tokens separated by spaces. The first token starts from rest.
#   kmh:hold[@a][/method]   go to kmh at a m/s^2 (default --acc), then hold kmh for `hold` seconds.
#                           method of a deceleration: m = motor (default), b = brake (the motor cancels the running resistance and
#                           the brake gives a), ? = drawn.  a may be r = drawn from 0.7..1.0.
#   stop[@a][/kmh]          the stop: brake from the end of the previous token; /kmh first decelerates with the motor to kmh
#                           (r = drawn from 20..30), then brakes. The brake law is a speed-dependent formula (vend), not a time table.
# The feed-forward is computed from the model of COMMON_MODEL.md (a params JSON written by axle2.mjs --params-out):
# the input of each channel is the model's inverse at the reference speed, advanced by that channel's lead (d_m + d_a + tau_s for the
# motor, d_b for the brake). No feedback. Everything drawn is written to plan.json with the seed.
import sys, os, re, json, math, random, time, subprocess, shutil, urllib.request
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")
BASE = "http://127.0.0.1:8765"
DZ = 0.0113
KMH = 1 / 3.6


class Model:
    def __init__(self, P):
        self.P = P; self.k = P["k"]; self.Kd = P["slope"] * P["Sc"]; self.gam = P["gamma"]; self.vk = P["vk"]
        self.B1, self.B2, self.c1 = P["B1"], P["B2"], P["c1"]
        self.Lm = round(P["dm"] + P["da"] + P["taus"]); self.Lb = round(P["db"])

    def F(self, b): return max(0.0, 1 - self.c1 * b - (1 - self.c1) * b * b)

    def drop(self, v): return 1 - self.gam * max(0.0, abs(v) - self.vk)  # the drive slope falls above the knee speed vk

    def ff(self, a, v):  # motor that gives acceleration a at speed v with no brake
        return (a + self.k * v) / (self.Kd * self.drop(v))

    def brake_for(self, g):  # brake that gives the extra decay rate g (1/s)
        if g <= 0: return 0.0
        b = (-self.B1 + math.sqrt(self.B1 ** 2 + 4 * self.B2 * g)) / (2 * self.B2) if self.B2 > 1e-9 else g / self.B1
        return min(1.0, max(DZ, b))

    def brake_ramp(self, a, v):  # brake gives the deceleration a, the motor cancels the running resistance
        b = self.brake_for(a / max(v, 0.3))
        return b, self.k * v / (self.Kd * self.drop(v) * max(self.F(min(b, 0.9)), 0.2))


def parse(spec, rng, acc0):
    phases = []; v = 0.0; resolved = []
    for tok in spec.split():
        if tok.startswith("stop"):
            m = re.fullmatch(r"stop(?:@(r|[\d.]+))?(?:/(r|[\d.]+))?", tok)
            if not m: raise SystemExit(f"bad token {tok}")
            a = round(rng.uniform(0.7, 1.0), 2) if m.group(1) == "r" else float(m.group(1) or acc0)
            if m.group(2) is not None:
                vs = round(rng.uniform(20, 30), 1) if m.group(2) == "r" else float(m.group(2))
                if vs * KMH < v: phases.append(dict(kind="ramp", v0=v, v1=vs * KMH, a=a, method="m", label=f"-> {vs:g} (motor)"))
                v = min(v, vs * KMH)
                resolved.append(f"stop@{a:g}/{vs:g}")
            else: resolved.append(f"stop@{a:g}")
            phases.append(dict(kind="stop", v0=v, a=a, label=f"stop from {v / KMH:.1f}"))
            for i, p in enumerate(phases): p["label"] = f"{i + 1:02d} {p['label']}"
            return phases, " ".join(resolved)
        m = re.fullmatch(r"([\d.]+):([\d.]+)(?:@(r|[\d.]+))?(?:/(m|b|\?))?", tok)
        if not m: raise SystemExit(f"bad token {tok}")
        vt = float(m.group(1)) * KMH; hold = float(m.group(2))
        a = round(rng.uniform(0.7, 1.0), 2) if m.group(3) == "r" else float(m.group(3) or acc0)
        meth = m.group(4) or "m"
        if meth == "?": meth = rng.choice("mb")
        if vt > v: meth = "m"
        if abs(vt - v) > 1e-9: phases.append(dict(kind="ramp", v0=v, v1=vt, a=a, method=meth, label=f"-> {vt / KMH:g} ({'+' if vt > v else '-'}{a:g}{meth})"))
        phases.append(dict(kind="hold", v0=vt, v1=vt, T=hold, label=f"hold {vt / KMH:g}"))
        resolved.append(f"{m.group(1)}:{m.group(2)}@{a:g}/{meth}"); v = vt
    raise SystemExit("the spec must end with stop")


def build(phases, md):
    t = 0.0
    for p in phases:
        if p["kind"] == "ramp": p["T"] = abs(p["v1"] - p["v0"]) / p["a"]
        if p["kind"] == "stop": p["T"] = p["v0"] / p["a"]
        p["t0"] = t; t += p["T"]
    return t


def vref(phases, t):
    for p in phases:
        if t < p["t0"] + p["T"] or p is phases[-1]:
            tau = min(max(t - p["t0"], 0), p["T"])
            if p["kind"] == "hold": return p["v0"]
            if p["kind"] == "ramp": return p["v0"] + math.copysign(p["a"], p["v1"] - p["v0"]) * tau
            return p["v0"] - p["a"] * tau


def inputs(phases, md, t):  # (motor, brake) the model needs at reference time t, not the stop
    for p in phases:
        if t < p["t0"] + p["T"] or p["kind"] == "stop":
            v = vref(phases, t)
            if p["kind"] == "hold": return md.ff(0, v), 0.0
            a = math.copysign(p["a"], p["v1"] - p["v0"])
            if p["method"] == "b": b, m = md.brake_ramp(p["a"], v); return m, b
            return md.ff(a, v), 0.0
    raise ValueError(t)


def dp(y, lo, hi, eps):  # knots of the piecewise-linear fit of y[lo..hi] (vertical error against the chord)
    out = {lo, hi}; stack = [(lo, hi)]
    while stack:
        a, b = stack.pop()
        if b - a < 2: continue
        i = np.arange(a, b + 1); chord = y[a] + (y[b] - y[a]) * (i - a) / (b - a)
        e = np.abs(y[a:b + 1] - chord); j = int(e.argmax())
        if e[j] > eps: out.add(a + j); stack += [(a, a + j), (a + j, b)]
    return out


def stop_law(md, a, vs):
    vg = np.linspace(0.4, vs + 3, 240)
    bt = np.array([min(1.0, max(DZ, md.brake_for(a / v))) for v in vg])
    mt = np.array([md.k * v / (md.Kd * md.drop(v) * max(md.F(min(b, 0.9)), 0.2)) for v, b in zip(vg, bt)])
    X = np.column_stack([np.ones_like(vg), vg, 1 / np.maximum(vg, 0.4)])
    w = 1 / (0.15 + bt)  # the small brake values count too
    cb = np.linalg.lstsq(X * w[:, None], bt * w, rcond=None)[0]; cm = np.linalg.lstsq(X, mt, rcond=None)[0]
    return cm, cb, X @ cb, X @ cm, vg, bt, mt


def program(phases, md, mirror):
    N0 = build(phases, md); stop = phases[-1]; Tn = stop["t0"]; Lm, Lb = md.Lm, md.Lb
    N = round(Tn * 60) - Lm
    im = np.array([inputs(phases, md, min(Tn - 1e-9, (i + Lm) / 60)) for i in range(N + 1)])
    ib = np.array([inputs(phases, md, min(Tn - 1e-9, (i + Lb) / 60)) for i in range(N + 1)])
    ym, yb = im[:, 0], ib[:, 1]
    assert phases[-2]["kind"] in ("hold", "ramp") and phases[-2].get("method", "m") == "m", "the phase before the stop must not brake"
    forced = {0, N}
    for p in phases[:-1]:
        for L in (Lm, Lb):
            j = round((p["t0"] + p["T"]) * 60) - L
            for x in (j - 1, j):
                if 0 <= x <= N: forced.add(x)
    fk = sorted(forced); knots = set(fk)
    for a, b in zip(fk[:-1], fk[1:]): knots |= dp(ym, a, b, 0.0004) | dp(yb, a, b, 0.004)
    kn = sorted(knots); segs = []
    for a, b in zip(kn[:-1], kn[1:]):
        n = b - a; T = n / 60
        segs.append((n, 0, 1, (ym[a], 0, 0, 0, (ym[b] - ym[a]) / T, 0, 0), (yb[a], 0, 0, 0, (yb[b] - yb[a]) / T, 0, 0)))
    vs = stop["v0"]; cm, cb, bfit, mfit, vg, bt, mt = stop_law(md, stop["a"], vs)
    peak_b = float(bfit[(vg >= 0.4) & (vg <= vs + 3)].max()); low_b = float(bfit.min())
    assert low_b > -0.05 and peak_b < 3, f"brake formula {low_b} .. {peak_b}"
    # between the end of the motor's time table and the start of the brake law (the motor's lead is longer than the brake's)
    if Lm > Lb: segs.append((Lm - Lb, 0, 1, (cm[0], cm[1], 0, cm[2], 0, 0, 0), (0,) * 7))
    segs.append((3000, -0.05, 0.4, (cm[0], cm[1], 0, cm[2], 0, 0, 0), (cb[0], cb[1], 0, cb[2], 0, 0, 0)))
    segs.append((300, 0, 1, (0,) * 7, (1, 0, 0, 0, 0, 0, 0)))
    mpeak = max(abs(s[3][0]) + abs(s[3][4]) * s[0] / 60 for s in segs[:-2])
    if mirror: segs = [(n, ve, vm, tuple(-c for c in m), b) for n, ve, vm, m, b in segs]
    fmt = lambda x: f"{float(x):.6g}"
    text = ";".join(f"{n}/{ve:g}/{vm:g}/{','.join(fmt(c) for c in m)}/{','.join(fmt(c) for c in b)}" for n, ve, vm, m, b in segs)
    dist = sum(vref(phases, t / 20) for t in range(int((Tn + stop["T"]) * 20))) / 20
    return text, len(segs), dist, dict(mpeak=mpeak, stop_b=[low_b, peak_b])


def refcsv(phases, path):
    end = phases[-1]["t0"] + phases[-1]["T"]
    with open(path, "w") as f:
        f.write("t,v,label\n")
        for i in range(int((end + 6) * 60) + 1):
            t = i / 60; p = next((p for p in phases if t < p["t0"] + p["T"]), None)
            f.write(f"{t:.4f},{vref(phases, min(t, end)) if p else 0:.4f},{p['label'] if p else 'rest'}\n")
    return end


def get_state():
    return json.load(urllib.request.urlopen(BASE + "/state"))["last"]


def site():
    s = open(os.path.join(HERE, "..", "src", "probe_site.lua")).read()
    return float(re.search(r"SITE_LO\s*=\s*(-?[\d.]+)", s).group(1)), float(re.search(r"SITE_HI\s*=\s*(-?[\d.]+)", s).group(1))


def xdir(veh):  # the sign of the x change per +motor: the "xdir" of data/vehicles/<veh>.json (default +1)
    f = os.path.join(DATA, "vehicles", f"{veh}.json")
    return json.load(open(f)).get("xdir", 1) if os.path.exists(f) else 1


def mirror_text(text):  # the same program toward -x: the model is odd in the motor and the speed
    out = []
    for seg in text.split(";"):
        n, ve, vm, m, b = seg.split("/")
        # every coefficient but the frequency (the last of the 7) changes its sign
        out.append("/".join([n, ve, vm, ",".join(f"{-float(c) + 0.0:.6g}" if i < 6 else c for i, c in enumerate(m.split(","))), b]))
    return ";".join(out)


def launch(text, dist, out, veh, rows_to=(), mmax=0.8, bmax=3.0, vmax=None, base_log=True):
    """Runs one program (written for +x) on the probe. The direction is chosen by the room that is left, never by hand.
    Appends the run's rows to data/log_<veh>.csv (the base measurement; scenarios pass base_log=False, so that no scenario reaches
    the validation set) and to each file of rows_to. Returns (ok, mirror, message)."""
    st = get_state(); x = st["x"]; lo, hi = site(); need = dist * 1.05 + 350
    if st["state"] == 0 and 0.3 < abs(st["v"]) < 5:  # still rolling: brake to rest first
        subprocess.run(["node", os.path.join(HERE, "campaign.mjs"), "0:0.5:240"], capture_output=True, text=True); st = get_state(); x = st["x"]
    if st["state"] != 0 or abs(st["v"]) > 0.3: return False, None, f"probe not idle at rest: state {st['state']} v {st['v']}"
    room_pos, room_neg = hi - x, x - lo
    mirror = (room_neg > room_pos) != (xdir(veh) < 0)  # programs are written for "+motor moves x up"; xdir -1 flips that
    if max(room_pos, room_neg) < need: return False, mirror, f"no room: x={x:.0f}, distance {dist:.0f} m (+350 margin), limits {lo:.0f}..{hi:.0f}"
    if mirror: text = mirror_text(text)
    os.makedirs(out, exist_ok=True); open(os.path.join(out, "program.txt"), "w").write(text)
    log = os.path.join(DATA, "log.csv"); n0 = sum(1 for _ in open(log))
    cmd = ["node", os.path.join(HERE, "campaign.mjs"), "--mmax", str(mmax), "--bmax", str(bmax), "--bmin", "-0.5"]
    if vmax: cmd += ["--vmax", str(vmax)]
    r = subprocess.run(cmd + [text], capture_output=True, text=True)
    head = open(log).readline(); rows = open(log).read().split("\n")[n0:]
    with open(os.path.join(out, "rows.csv"), "w") as f: f.write(head + "\n".join(rows))
    for target in ((os.path.join(DATA, f"log_{veh}.csv"),) if base_log else ()) + tuple(rows_to):
        if not os.path.exists(target): open(target, "w").write(head)
        open(target, "a").write("\n".join(rows))
    msg = r.stdout.strip().split(": done")[-1] if ": done" in r.stdout else r.stdout.strip()[-300:]
    return r.returncode == 0, mirror, msg


def run_scenario(mode, name, spec, acc0=0.8, seed=None, veh="mo1800", pfile=None, quiet=False):
    seed = int(time.time()) % 100000 if seed is None else seed; rng = random.Random(seed)
    pfile = pfile or os.path.join(DATA, f"params_{veh}.json")
    md = Model(json.load(open(pfile)))
    phases, resolved = parse(spec, rng, acc0)
    out = os.path.join(DATA, "scenarios", f"{veh}_{mode}_{name}"); os.makedirs(out, exist_ok=True)
    text, nseg, dist, info = program(phases, md, False)
    end = refcsv(phases, os.path.join(out, "ref.csv"))
    shutil.copy(pfile, os.path.join(out, "params.json"))
    pf = pfile.replace(".json", "_freq.json")
    if os.path.exists(pf): shutil.copy(pf, os.path.join(out, "params_freq.json"))
    target = [] if mode == "plan" else [os.path.join(DATA, f"{mode}_{veh}.csv")]   # fit_<veh>.csv: axle2.mjs --fit-log; verify_<veh>.csv: read by nothing
    if mode == "plan": ok, mirror, msg = True, False, ""
    else: ok, mirror, msg = launch(text, dist, out, veh, target, base_log=False)
    if mirror: text, *_ = program(phases, md, True)
    plan = dict(mode=mode, name=name, seed=seed, spec=spec, resolved=resolved, mirror=bool(mirror), segments=nseg, duration=end, distance=dist,
                x0=get_state()["x"], params=pfile, leads=dict(motor=md.Lm, brake=md.Lb), **info,
                phases=[{k: (round(v, 4) if isinstance(v, float) else v) for k, v in p.items()} for p in phases])
    json.dump(plan, open(os.path.join(out, "plan.json"), "w"), indent=1)
    print(f"{mode} {name}: seed {seed}, resolved '{resolved}'\n  {nseg} segments, {end:.1f} s, {dist:.0f} m, peak motor {info['mpeak']:.3f}; {msg}")
    if mode == "plan": return True, out
    if not ok: print("  not run or not finished"); return False, out
    r = subprocess.run(["node", os.path.join(HERE, "compare3.mjs"), out], capture_output=quiet, text=True)
    if quiet: print(r.stdout.strip().split("\n")[-1])
    return r.returncode == 0, out


def main():
    a = sys.argv[1:]; opt = lambda n, d=None: a[a.index(n) + 1] if n in a else d
    ok, _ = run_scenario(a[0], opt("--name", "run"), a[-1], float(opt("--acc", 0.8)), int(opt("--seed")) if opt("--seed") else None, opt("--vehicle", "mo1800"), opt("--params"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
