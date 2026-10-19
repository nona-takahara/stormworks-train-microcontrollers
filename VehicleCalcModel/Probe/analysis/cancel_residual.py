#!/usr/bin/env python
# The residual resistance with the resistance cancel on (r_target = 0): the pair holds a series of speeds with the motors giving only the cancel.
#   python cancel_residual.py <variant> [speeds ...]       variant: linear | quad | quad_drop | tuned | scaled
# The motor of car i (forward frame) is the cancel  (k_i v + k2 v^2) / (K_i drop_i(v))  as the formula  c1 |v| + c2 v^2  (see RESISTANCE_CANCEL.md):
#   linear    k from params_*.json (the step fit), no k2, no drop
#   quad      k from the coasting fit, k2 = 8e-5 (shared), no drop
#   quad_drop quad, and the drop of the drive above vk:  (c v + q v^2)(1 - gamma vk + gamma v)  for the band above vk
#   tuned     quad_drop with the drop compensation at LAMBDA of the model value (the cancel regime has a smaller drop) and a constant term C0 (m/s^2 of the train)
#   scaled    quad with k x KSCALE (no constant, no drop): the residual of `quad` is about 2 % of the drag at every speed
# Between the holds the train accelerates (car A pulls at 0.5 m/s^2 of the train) with the same cancel. Each hold lasts 600 tick;
# the residual deceleration is the slope of the speed over the last 400 tick of the hold.
import sys, os, json, subprocess, urllib.request
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, "..", "data")
P = {"A": json.load(open(os.path.join(DATA, "params_mo2000.json"))), "B": json.load(open(os.path.join(DATA, "params_ku2100.json")))}
KFIT = {"A": 0.1062, "B": 0.0939}; K2 = 8e-5; KSCALE = float(os.environ.get("KSCALE", 1.02)); LAMBDA = float(os.environ.get("LAMBDA", 0.55)); C0 = float(os.environ.get("C0", 0.0102)); SIGN = {"A": 1, "B": -1}; W = 0.49


def coeffs(c, variant, v):
    """c0, c1, c2 of the cancel motor (forward frame, before the sign of the car)"""
    p = P[c]; K = p["Sc"] * p["slope"]
    k = p["k"] if variant == "linear" else KFIT[c]; q = 0.0 if variant == "linear" else K2
    if variant == "scaled": k *= KSCALE
    cc, qq = k / K, q / K; c0 = (C0 / (2 * W)) / K if variant == "tuned" else 0.0     # the constant: C0 of the train from two cars
    if variant in ("quad_drop", "tuned") and v > p["vk"]:
        g, vk = p["gamma"] * (LAMBDA if variant == "tuned" else 1.0), p["vk"]
        return c0, cc * (1 - g * vk), cc * g + qq * (1 - g * vk)
    return c0, cc, qq


def program(c, variant, speeds, d):
    p = P[c]; K = p["Sc"] * p["slope"]; sg = SIGN[c] * d; segs = []
    for v in speeds:
        c0, c1, c2 = coeffs(c, variant, v)
        macc = sg * (1 / W) * 0.5 / K if c == "A" else 0.0     # the train accelerates at 0.5 m/s^2: car A alone pulls, at 1/w of it
        segs.append(f"4800/{v:.2f}/1/{macc + sg * c0:.8f},{sg * c1:.8f},{sg * c2:.10f},0/0,0,0,0")
        segs.append(f"600/1/{sg * c0:.8f},{sg * c1:.8f},{sg * c2:.10f},0/0,0,0,0")
    segs.append("600/-0.2/1/0,0,0,0/0.5,0,0,0")
    return ";".join(segs)


def main():
    variant = sys.argv[1]; speeds = [float(x) for x in sys.argv[2:]] or [5, 10, 15, 20, 25, 29]
    x = json.load(urllib.request.urlopen("http://127.0.0.1:8765/state"))["last"]["x"]
    d = 1 if 480 - x > x + 8480 else -1; room = (480 - x) if d == 1 else (x + 8480)
    dist = sum((v * v - u * u) / (2 * 0.5) + v * 10 for u, v in zip([0] + speeds[:-1], speeds)) + 700
    if room < dist + 600: print(f"no room: x {x:.0f}, need {dist:.0f} m, room {room:.0f} m"); sys.exit(1)
    name = f"cancel_{variant}"
    r = subprocess.run([sys.executable, os.path.join(HERE, "twocar.py"), name, program("A", variant, speeds, d), program("B", variant, speeds, d)], capture_output=True, text=True)
    if r.returncode != 0: print("run failed", r.stdout[-300:], r.stderr[-200:]); sys.exit(1)
    import csv
    rows = [r for r in csv.DictReader(open(os.path.join(DATA, "twocar", name, "A.csv"))) if r["state"] == "1"]
    t = np.array([int(r["t"]) for r in rows]) / 60.0; v = d * np.array([float(r["v"]) for r in rows]); seg = np.array([int(r["reason"]) for r in rows])
    print(f"{variant}: direction {d:+d}, the holds are segments 2, 4, ...; residual deceleration of the train in m/s^2 (positive = slowing down)")
    print("hold v[m/s]   mean v   residual decel   raw drag w(kA+kB)v   residual/raw")
    for i, vt in enumerate(speeds):
        s = seg == 2 * (i + 1)
        if s.sum() < 100: print(f"{vt:6.1f}  no data"); continue
        tt, vv = t[s], v[s]; m = tt >= tt[0] + (tt[-1] - tt[0]) * 0.33     # the last two thirds of the hold
        slope = np.polyfit(tt[m], vv[m], 1)[0]; vm = vv[m].mean(); raw = W * (P["A"]["k"] + P["B"]["k"]) * vm
        print(f"{vt:6.1f}  {vm:8.2f}  {-slope:+9.4f}         {raw:8.3f}          {100 * -slope / raw:+6.2f} %")


if __name__ == "__main__":
    main()
