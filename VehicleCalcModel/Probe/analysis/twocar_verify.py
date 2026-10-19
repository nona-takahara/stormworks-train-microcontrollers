#!/usr/bin/env python
# Random verification on the coupled pair (not used by any fit): inertia-compensation style commands made from the single-car parameters.
#   python twocar_verify.py <seed> [name [vmin vmax [rule]]]   (the top speed V1 of the run: vmin..vmax m/s, default 6..11; rule v1..v6, default v3 (v5 = the new inertia compensation with the F compensation, v6 = without it))
# Rules v8 and v9 = v5 and v6 with the model of record (G = 1/w = 2, beta = 1): v8 with the F compensation, v9 without. Rule v3 = v2 with the brake command divided by BRAKE_GAIN (1.05). Rule v4 = v3 with the motor commands raised above vk by the inverse of the drive drop. Rule v1: each car commands 2 x its share of the target. Rule v2 (TWO_CAR_MODEL.md): 1/w x its share (w = 0.49), and the car that brakes also gets
# the constant c0 += cancel c1 ci in its resistance cancel, against the weakening of its motor by its own brake (F(b) ~ 1 - c1 b).
# Per car: the resistance cancel is always on (motor = c v with c = k/(Sc slope)). The train accelerates at a with the share beta_i of
# the acceleration on car i, and decelerates at a_d with the share alpha on the motor of car X and 1 - alpha on the brake of car Y.
# The pair is one body of weight 1/2 per car, so each car's command is that of a single car at 2 x its share (the target is the train's).
# Reports model - measured (pair.mjs, w = 0.49) and the realized acceleration against the target (twocar_realized.py).
# The top speed V1 is a target: the first segment ends after 4800 tick at the latest, so a low acceleration may not reach it.
import sys, os, json, random, subprocess
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, "..", "data")
P = {"A": json.load(open(os.path.join(DATA, "params_mo2000.json"))), "B": json.load(open(os.path.join(DATA, "params_ku2100.json")))}
SIGN = {"A": 1, "B": -1}   # the motor sign toward +x
KFIT = {"A": 0.1062, "B": 0.0939}; K2 = 8e-5   # the resistance of the coasting fit (RESISTANCE_CANCEL.md)
import urllib.request
LO, HI = -8480, 480   # the track limits of probe_site.lua


def travel_dir():
    """+1 toward +x or -1 toward -x: the side with more room (the pair is long, so the limits are kept at 1500 m)."""
    x = json.load(urllib.request.urlopen("http://127.0.0.1:8765/state"))["last"]["x"]
    return 1 if HI - x > x - LO else -1


def car(c, d=1):
    p = P[c]; K = p["Sc"] * p["slope"]; sg = SIGN[c] * d
    return dict(K=K, cancel=sg * p["k"] / K, B1=p["B1"], sign=sg)


def main():
    seed = int(sys.argv[1]); name = sys.argv[2] if len(sys.argv) > 2 else f"verify_{seed}"; rng = random.Random(seed)
    vlo, vhi = (float(sys.argv[3]), float(sys.argv[4])) if len(sys.argv) > 4 else (6, 11)
    dirn = travel_dir()
    rule = sys.argv[5] if len(sys.argv) > 5 else "v3"; G = 2.0 if rule in ("v1", "v8", "v9") else 1 / 0.49; GB = 1.05 if rule in ("v3", "v4", "v5", "v6", "v7") else 1.0   # v8, v9: the model of record (w 0.5, beta 1)   # v3: the brake of the pair acts 1.05 x the single-car law
    V1 = rng.uniform(vlo, vhi); a = rng.uniform(0.4, 0.8); ad = rng.uniform(0.5, 1.0)
    beta = rng.choice([(1, 0), (0.5, 0.5), (0, 1), (0.75, 0.25)]); alpha = rng.uniform(0, 1); X, Y = rng.choice([("A", "B"), ("B", "A")])
    prog = {}
    for c in "AB":
        k = car(c, dirn); bi = beta[0] if c == "A" else beta[1]
        m_acc = k["sign"] * G * bi * a / k["K"]
        m_dec = k["sign"] * (-G * alpha * ad / k["K"]) if c == X else 0.0
        ci = G * (1 - alpha) * ad / (GB * k["B1"]) if c == Y else 0.0
        c0f = k["cancel"] * P[c]["c1"] * ci if rule in ("v2", "v3", "v4") else 0.0   # the weakening of the motor by the brake of the same car
        plain = lambda m0, cf=0.0: f"{m0 + cf:.8f},{k['cancel']:.8f},0,0"
        gam, vk = P[c].get("gamma", 0.0), P[c].get("vk", 0.0)
        # rule v4: above vk the drive of the car drops by 1 - gam (v - vk); (m0 + cancel v) (1 + gam (v - vk)) is c0 + c1 v + c2 v^2 on that band
        comp = lambda m0, cf=0.0: f"{m0 * (1 - gam * vk) + cf:.8f},{k['cancel'] + m0 * gam - k['cancel'] * gam * vk:.8f},{k['cancel'] * gam:.10f},0"
        band = rule == "v4" and V1 > vk
        if rule == "v7":
            # v6 + the dead zone: where the brake command ci/|v| would be under DZ (|v| > ci/DZ), the share of the brake goes to the negative drive of the same car
            sg = k["sign"]; K = k["K"]; ck = sg * 1.02 * KFIT[c] / K; cq = sg * 1.02 * K2 / K
            m_brk = sg * (-G * (1 - alpha) * ad / K) if c == Y else 0.0     # the brake share as a motor command
            vstar = ci / 0.0113 if ci > 0 else 0.0
            def mot7(m0, drop_on):
                if drop_on: return f"{m0 * (1 - gam * vk):.8f},{ck + m0 * gam:.8f},{cq:.10f},0"
                return f"{m0:.8f},{ck:.8f},{cq:.10f},0"
            cuts = sorted({v_ for v_ in (vk, vstar) if 2 < v_ < V1}, reverse=True)
            segs = [f"4800/{vk:.2f}/1/{mot7(m_acc, False)}/0,0,0,0", f"4800/{V1:.2f}/1/{mot7(m_acc, True)}/0,0,0,0", f"120/1/{mot7(0.0, True)}/0,0,0,0"] if V1 > vk else [f"4800/{V1:.2f}/1/{mot7(m_acc, False)}/0,0,0,0", f"120/1/{mot7(0.0, False)}/0,0,0,0"]
            edges = cuts + [2.0]; top = V1
            for lo in edges:
                mid = (top + lo) / 2; active = mid <= vstar and ci > 0     # the brake works in this band
                segs.append(f"4800/-{lo:.2f}/2/{mot7(m_dec + (0.0 if active else m_brk), mid > vk)}/0,0,0,{ci if active else 0.0:.4f}"); top = lo
        elif rule in ("v5", "v6", "v8", "v9"):
            # the new inertia compensation (INERTIA_COMPENSATION_NEW.md): the cancel 1.02 (k |v| + k2 v^2) / K without the drop, the drive part with the drop
            # above vk, and the whole motor command divided by F(b) of the car's own brake, to first order: (m0 + cancel) (1 + c1 b), b = ci / |v|
            sg = k["sign"]; K = k["K"]; ck = sg * 1.02 * KFIT[c] / K; cq = sg * 1.02 * K2 / K; c1b = P[c]["c1"]
            def mot(m0, drop_on, with_f):
                f0 = c1b * ci * ck if (with_f and rule in ("v5", "v8")) else 0.0          # the constant of (cancel c1 b)
                fi = c1b * ci * m0 if (with_f and rule in ("v5", "v8")) else 0.0          # the 1/|v| term of (m0 c1 b)
                f1 = c1b * ci * cq if (with_f and rule in ("v5", "v8")) else 0.0          # the |v| term of (k2 v^2 c1 b)
                if drop_on: return f"{m0 * (1 - gam * vk) + f0:.8f},{ck + m0 * gam + f1:.8f},{cq:.10f},{fi:.8f}"
                return f"{m0 + f0:.8f},{ck + f1:.8f},{cq:.10f},{fi:.8f}"
            if V1 > vk:
                segs = [f"4800/{vk:.2f}/1/{mot(m_acc, False, False)}/0,0,0,0", f"4800/{V1:.2f}/1/{mot(m_acc, True, False)}/0,0,0,0", f"120/1/{mot(0.0, True, False)}/0,0,0,0",
                        f"4800/-{vk:.2f}/2/{mot(m_dec, True, True)}/0,0,0,{ci:.4f}"]
            else:
                segs = [f"4800/{V1:.2f}/1/{mot(m_acc, False, False)}/0,0,0,0", f"120/1/{mot(0.0, False, False)}/0,0,0,0"]
            segs.append(f"4800/-2/2/{mot(m_dec, False, True)}/0,0,0,{ci:.4f}")
        elif band:
            segs = [f"4800/{vk:.2f}/1/{plain(m_acc)}/0,0,0,0", f"4800/{V1:.2f}/1/{comp(m_acc)}/0,0,0,0", f"120/1/{comp(0.0)}/0,0,0,0",
                    f"4800/-{vk:.2f}/2/{comp(m_dec, c0f)}/0,0,0,{ci:.4f}"]
        else:
            segs = [f"4800/{V1:.2f}/1/{plain(m_acc)}/0,0,0,0", f"120/1/{plain(0.0)}/0,0,0,0"]
        if rule not in ("v5", "v6", "v7", "v8", "v9"): segs.append(f"4800/-2/2/{plain(m_dec, c0f)}/0,0,0,{ci:.4f}")
        segs.append("600/-0.2/1/0,0,0,0/0.5,0,0,0")
        prog[c] = ";".join(segs)
    print(f"direction {dirn:+d}, rule {rule}, seed {seed}: V1 {V1:.1f} m/s, a {a:.2f}, a_dec {ad:.2f}, accel share A/B {beta}, decel: motor of {X} {alpha:.2f}, brake of {Y} {1 - alpha:.2f}")
    r = subprocess.run([sys.executable, os.path.join(HERE, "twocar.py"), name, prog["A"], prog["B"]], capture_output=True, text=True)
    if r.returncode != 0: print("run failed:", r.stdout[-400:], r.stderr[-300:]); sys.exit(1)
    out = subprocess.run(["node", os.path.join(HERE, "pair.mjs"), os.path.join(DATA, "twocar", name), "--w", "0.49"], capture_output=True, text=True).stdout.strip()
    from twocar_realized import realized
    top, ra, rd = realized(name)
    print(out, f"| top {top:.1f} m/s, realized accel {ra:.2f} (target {a:.2f}), decel {rd:.2f} (target {ad:.2f})")
    sys.exit(0)


if __name__ == "__main__":
    main()
