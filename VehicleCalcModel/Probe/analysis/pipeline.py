#!/usr/bin/env python
# One procedure for a new vehicle: base measurement -> fit -> speed ladder -> fit -> two random verification runs -> verdict.
#
#   python pipeline.py --vehicle ku2100 all          (everything; stops at the first run that does not finish)
#   python pipeline.py --vehicle ku2100 base|ladder|fit|verify|extend
#
# data/vehicles/<vehicle>.json:  {"vtop": 30.5, "mmax": 0.5, "bmax": 1.0, "rps_aux": 22}
#   vtop  the top of the regular speed range [m/s] (the base measurement and the scenarios are scaled to it; the clean fit range)
#   xdir  the sign of the x change per +motor (default 1; -1 when the vehicle faces the other way on the track). Sent to the probe as 3,xdir (probe_dir) at the start
#   sync_aux  the input channel with the sawtooth of the time sync between two probes (aux2; default 0 = none; 23 on a two-car train)
#   mmax  the motor bound of the measurement (below the slip threshold, which the base measurement does not look for)
# The input channel with the axle RPS must be wired and chosen as an auxiliary channel (set here with 6,rps_aux,0).
# Everything is logged in data/log_<vehicle>.csv; the fit scenarios in data/fit_<vehicle>.csv (read by axle2.mjs --fit-log);
# the verification runs in data/verify_<vehicle>.csv (read by nothing). A failed verification is answered by `extend`,
# which adds base measurement (more motor and brake levels, a second speed ladder), not fit scenarios.
import sys, os, json, subprocess, urllib.request, time, shutil
import scenario as sc

HERE, DATA = sc.HERE, sc.DATA
PASS_RMS, PASS_MAX = 0.12, 0.35  # per verification run, m/s, on model - measured (the aim is rms 0.1)


def notify(msg):
    try:
        env = open(os.path.join(HERE, "..", "..", "..", ".env")).read()
        url = next(l.split("=", 1)[1].strip() for l in env.splitlines() if l.startswith("PROBE_WEBHOOK_URL="))
        urllib.request.urlopen(urllib.request.Request(url, json.dumps({"content": msg}).encode(), {"Content-Type": "application/json", "User-Agent": "probe-pipeline"}))
    except Exception as e:
        print("  (no notification:", type(e).__name__, ")")


def seg(n, m=0.0, b=0.0, vend=0.0, vmin=1.0):
    return f"{n}/{vend:g}/{vmin:g}/{m:g},0,0,0,0,0,0/{b:g},0,0,0,0,0,0"


class Vehicle:
    def __init__(self, name):
        self.name = name; self.cfg = json.load(open(os.path.join(DATA, "vehicles", f"{name}.json")))
        self.V = self.cfg["vtop"]; self.mmax = self.cfg.get("mmax", 0.5); self.bmax = self.cfg.get("bmax", 1.0)
        self.log = os.path.join(DATA, f"log_{name}.csv"); self.params = os.path.join(DATA, f"params_{name}.json")
        self.fitlog = os.path.join(DATA, f"fit_{name}.csv")

    def run(self, label, segs, dist=None):
        text = ";".join(segs); dist = dist or 0.5 * self.V * sum(min(int(s.split("/")[0]), 1800) for s in segs) / 60 + 150
        out = os.path.join(DATA, "scenarios", f"{self.name}_base_{label}")
        ok, mirror, msg = sc.launch(text, dist, out, self.name, mmax=max(self.mmax, 0.5) + 0.01, bmax=max(self.bmax, 1.0) + 0.01, vmax=self.V + 3)
        print(f"  {label}: {'ok' if ok else 'FAILED'} ({'-x' if mirror else '+x'}) {msg}")
        if not ok: notify(f"[{self.name}] base run {label} did not finish: {msg}"); raise SystemExit(1)

    def axle2(self, with_fit=True, bound=0.15):
        cmd = ["node", os.path.join(HERE, "axle2.mjs"), self.log, "--bound", str(bound), "--params-out", self.params]
        if with_fit and os.path.exists(self.fitlog): cmd += ["--fit-log", self.fitlog]
        r = subprocess.run(cmd, capture_output=True, text=True)
        lines = [l for l in r.stdout.split("\n") if l.startswith(("stage 4", "fit", "validation", "  all"))]
        print("\n".join("  " + l for l in lines)); return r.returncode == 0


def base(v, levels=(0.05, 0.1, 0.15, 0.2, 0.3, 0.4, 0.5), blevels=(0.0125, 0.02, 0.035, 0.05, 0.1, 0.2, 0.4, 0.7, 1.0), sim=((0.2, 0.1), (0.2, 0.3), (0.2, 0.6), (0.2, 0.9), (0.4, 0.5)), tag=""):
    V = v.V; stop = seg(2000, 0, 0.5, vend=-0.2)
    # the direction of the motor: a small step must move the vehicle toward +x
    print("base measurement: motor steps from rest (each: step until 0.9 vtop or 15 s, coast 10 s, brake to rest)")
    for m in levels:
        if m > v.mmax + 1e-9: continue
        v.run(f"step{m:g}{tag}", [seg(900, m, 0, vend=0.9 * V), seg(600), stop])
    print("base measurement: long coast (the running resistance)")
    v.run(f"coast{tag}", [seg(1200, min(0.25, v.mmax), 0, vend=0.95 * V), seg(1800), stop])
    print("base measurement: brake levels from 0.7 vtop")
    for b in blevels:
        if b > v.bmax + 1e-9: continue
        v.run(f"brake{b:g}{tag}", [seg(1500, min(0.25, v.mmax), 0, vend=0.7 * V), seg(2400, 0, b, vend=-3), stop])
    print("base measurement: motor and brake together from rest")
    for m, b in sim:
        if m > v.mmax + 1e-9 or b > v.bmax + 1e-9: continue
        v.run(f"both{m:g}_{b:g}{tag}", [seg(360, m, b), stop])
    print("fit of the base measurement:"); v.axle2(with_fit=False)


def ladder(v, hold=10, order="up", name="L1"):
    fr = [0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0]
    if order == "down": fr = fr[::-1]
    # after the top step the speed is brought down to 30% of vtop before the stop: the brake law is fitted for low speeds
    spec = " ".join(f"{v.V * 3.6 * f:.1f}:{hold}" for f in fr) + f" {v.V * 3.6 * 0.3:.1f}:3@0.9 stop"
    print(f"speed ladder {name}: {spec}")
    ok, _ = sc.run_scenario("fit", name, spec, 0.5, veh=v.name, quiet=True)
    if not ok: notify(f"[{v.name}] speed ladder {name} did not finish"); raise SystemExit(1)
    print("fit with the ladder:"); v.axle2()


def sweep(v, amp_scale=1.0, name="S1", freqs=(0.2, 0.4, 0.8, 1.5, 3, 5, 8)):
    """Frequency response: the motor is 0.06 + 0.06 sin(2 pi f t) (times amp_scale) at each of 7 frequencies, recorded every tick."""
    freqs = list(freqs); o = round(0.06 * amp_scale, 4)
    segs = [seg(1500, o, 0, vend=0.4 * v.V)]
    for f in freqs: segs.append(f"{round(60 * max(8, 6 / f))}/0/1/{o:g},0,0,0,0,{o:g},{f:g}/0,0,0,0,0,0,0")
    segs.append(seg(2000, 0, 0.5, vend=-0.2))
    out = os.path.join(DATA, "scenarios", f"{v.name}_sweep_{name}"); os.makedirs(out, exist_ok=True)
    json.dump(dict(freqs=freqs, amp=o, segments=len(segs)), open(os.path.join(out, "sweep.json"), "w"))
    shutil.copy(v.params, os.path.join(out, "params.json"))
    dur = sum(int(s.split("/")[0]) for s in segs[:-1]) / 60
    ctl = lambda body: urllib.request.urlopen(urllib.request.Request(sc.BASE + "/ctl", body.encode(), method="POST"))
    ctl("5,1,12")  # a record every tick
    try:
        ok, mirror, msg = sc.launch(";".join(segs), 0.45 * v.V * dur + 300, out, v.name, rows_to=(os.path.join(DATA, f"sweep_{v.name}.csv"),), mmax=2 * o + 0.01, bmax=max(v.bmax, 1.0) + 0.01, vmax=v.V + 3, base_log=False)
    finally: ctl("5,2,8")
    print(f"  sweep {name} (amplitude {o}): {'ok' if ok else 'FAILED'} ({'-x' if mirror else '+x'}) {msg}")
    if not ok: notify(f"[{v.name}] sweep {name} did not finish: {msg}"); raise SystemExit(1)
    r = subprocess.run(["node", os.path.join(HERE, "freqresp2.mjs"), out], capture_output=True, text=True); print(r.stdout.rstrip())
    return r.returncode == 0


def verify(v, n=2):
    f = v.V * 3.6 / 110  # the verification recipe of the 1800 (top 110 km/h), scaled to the vehicle
    sp = lambda x: f"{x * f:.1f}"
    spec = f"{sp(35)}:10@0.7 {sp(105)}:5@0.9 {sp(65)}:5@r {sp(90)}:5@0.5 {sp(45)}:5@r/? stop@r/r"
    res = []
    for i in range(n):
        seed = int(time.time() * 1000) % 100000 + i
        ok, out = sc.run_scenario("verify", f"{int(time.time())}_{i}", spec, 0.8, seed, v.name, quiet=False)
        if not ok: notify(f"[{v.name}] verification run did not finish"); raise SystemExit(1)
        c = json.load(open(os.path.join(out, "compare.json"))); res.append(c)
    # the pass is on the model (model - measured); ideal - measured also contains the feed-forward's own approximation (ideal - model), reported beside it
    ok = all(c["MoM"][0] <= PASS_RMS and c["MoM"][1] <= PASS_MAX for c in res)
    line = "; ".join(f"seed {c['seed']}: model-measured rms {c['MoM'][0]:.3f} max {c['MoM'][1]:.3f}; ideal-measured rms {c['IM'][0]:.3f} max {c['IM'][1]:.3f}; ideal-model rms {c['IMo'][0]:.3f}" for c in res)
    verdict = f"[{v.name}] verification {'PASSED' if ok else 'NOT passed'} (rms <= {PASS_RMS}, max <= {PASS_MAX}): {line}"
    print(verdict); notify(verdict); return ok


def extend(v, round_no):
    print(f"extending the base measurement (round {round_no}): more levels and a second ladder")
    base(v, levels=(0.075, 0.125, 0.25, 0.35, 0.45), blevels=(0.015, 0.03, 0.075, 0.15, 0.3, 0.55, 0.85), sim=((0.1, 0.2), (0.3, 0.2), (0.3, 0.7)), tag=f"_x{round_no}")
    ladder(v, hold=14, order="down", name=f"L{round_no + 1}")


def main():
    a = sys.argv[1:]; veh = a[a.index("--vehicle") + 1]; cmd = a[-1]
    cmds = set(cmd.split(","))  # e.g. "refit,verify" resumes after the base measurement and the ladder
    v = Vehicle(veh)
    for body in (f"6,{v.cfg.get('rps_aux', 22)},{v.cfg.get('sync_aux', 0)}", f"3,{sc.xdir(veh)}"):  # the auxiliary channel; the direction (for the probe's jog back into the area)
        urllib.request.urlopen(urllib.request.Request(sc.BASE + "/ctl", body.encode(), method="POST"))
    notify(f"[{veh}] pipeline '{cmd}' started (vtop {v.V} m/s)")
    if cmds & {"base", "all"}: base(v)
    if cmds & {"ladder", "all", "resume"}: ladder(v)
    if cmds & {"sweep", "all", "resume"}:
        sweep(v); sweep(v, 2.0, "S2")  # the second amplitude shows whether the response is linear
    if "sweephigh" in cmds: sweep(v, 2.0, "S3", (8, 10, 12, 15, 20, 24, 27, 29))  # above 8 Hz (the tick rate is 60 Hz, so 30 Hz is the limit)
    if cmds & {"sweep", "all", "resume", "sweephigh"}: print("two models: A (delays from the steps) and B (delays from the frequency response):"); print(subprocess.run(["node", os.path.join(HERE, "fitdelay.mjs"), v.name, "--write"], capture_output=True, text=True).stdout)
    if "refit" in cmds: print("fit of everything so far:"); v.axle2()
    if "extend" in cmds: extend(v, int(time.time()) % 1000)
    if cmds & {"verify", "all", "resume"}:
        ok = verify(v)
        for r in range(1, 3):  # an unsuccessful verification is answered by more base measurement
            if ok or not cmds & {"all", "resume"}: break
            extend(v, r); ok = verify(v)
        sys.exit(0 if ok else 2)


if __name__ == "__main__":
    main()
