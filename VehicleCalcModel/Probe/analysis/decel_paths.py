#!/usr/bin/env python
# The deceleration of the new inertia compensation (rule v5, INERTIA_COMPENSATION_NEW.md) path by path:
#   python decel_paths.py <path> [v_top] [a_dec] [a_acc]       path: motorA | motorB | brakeA | brakeB
# The pair is brought to v_top by the car A alone (the other car only cancels), holds 2 s, then decelerates at a_dec of the train on ONE path: the motor of car
# A or B (negative drive) or the friction brake of car A or B. Reports the realized deceleration between 0.85 v_top and 5 m/s, in steps of speed.
import sys, os, json, subprocess, urllib.request
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, "..", "data")
P = {"A": json.load(open(os.path.join(DATA, "params_mo2000.json"))), "B": json.load(open(os.path.join(DATA, "params_ku2100.json")))}
FMODE = os.environ.get("FMODE", "full")   # full: F = 1 - c1 b ; none: no compensation ; dz: F = 1 - c1 (b - DZ) for b > DZ
KFIT = {"A": 0.1062, "B": 0.0939}; K2 = 8e-5; SIGN = {"A": 1, "B": -1}; W = 0.49; G = 1 / W; GB = 1.05


def build(c, path, vtop, a_acc, a_dec, d):
    p = P[c]; K = p["Sc"] * p["slope"]; sg = SIGN[c] * d; gam, vk, c1b = p["gamma"], p["vk"], p["c1"]
    ck = sg * 1.02 * KFIT[c] / K; cq = sg * 1.02 * K2 / K
    m_acc = sg * G * a_acc / K if c == "A" else 0.0
    m_dec = sg * (-G * a_dec / K) if path == f"motor{c}" else 0.0
    ci = G * a_dec / (GB * p["B1"]) if path == f"brake{c}" else 0.0
    def mot(m0, drop_on, with_f):
        f0, fi, f1 = (c1b * ci * ck, c1b * ci * m0, c1b * ci * cq) if (with_f and FMODE != "none") else (0.0, 0.0, 0.0)
        if with_f and FMODE == "dz":      # (1 + c1 (b - DZ)) (m0 + ck |v| + cq v^2) with b = ci/|v|:  the constant -c1 DZ m0, the |v| term -c1 DZ ck, the v^2 term -c1 DZ cq
            f0 -= 0.0; f1 -= c1b * 0.0113 * ck
            m0 = m0 * (1 - c1b * 0.0113)
        if drop_on: return f"{m0 * (1 - gam * vk) + f0:.8f},{ck + m0 * gam + f1:.8f},{cq:.10f},{fi:.8f}"
        return f"{m0 + f0:.8f},{ck + f1:.8f},{cq:.10f},{fi:.8f}"
    if vtop > vk:
        segs = [f"4800/{vk:.2f}/1/{mot(m_acc, False, False)}/0,0,0,0", f"4800/{vtop:.2f}/1/{mot(m_acc, True, False)}/0,0,0,0", f"120/1/{mot(0.0, True, False)}/0,0,0,0",
                f"4800/-{vk:.2f}/2/{mot(m_dec, True, True)}/0,0,0,{ci:.4f}"]
    else:
        segs = [f"4800/{vtop:.2f}/1/{mot(m_acc, False, False)}/0,0,0,0", f"120/1/{mot(0.0, False, False)}/0,0,0,0"]
    segs.append(f"4800/-2/2/{mot(m_dec, False, True)}/0,0,0,{ci:.4f}")
    segs.append("600/-0.2/1/0,0,0,0/0.5,0,0,0"); return ";".join(segs)


def main():
    path = sys.argv[1]; vtop = float(sys.argv[2]) if len(sys.argv) > 2 else 24.0; a_dec = float(sys.argv[3]) if len(sys.argv) > 3 else 0.7; a_acc = float(sys.argv[4]) if len(sys.argv) > 4 else 0.6
    x = json.load(urllib.request.urlopen("http://127.0.0.1:8765/state"))["last"]["x"]
    d = 1 if 480 - x > x + 8480 else -1; room = (480 - x) if d == 1 else (x + 8480)
    need = vtop ** 2 / (2 * 0.5) + vtop ** 2 / (2 * a_dec) + 600
    if room < need + 600: print("no room", x, need); sys.exit(1)
    name = f"decel_{path}_{int(vtop)}_{a_dec}_{FMODE}".replace(".", "p")
    r = subprocess.run([sys.executable, os.path.join(HERE, "twocar.py"), name, build("A", path, vtop, a_acc, a_dec, d), build("B", path, vtop, a_acc, a_dec, d)], capture_output=True, text=True)
    if r.returncode != 0: print("run failed", r.stdout[-300:], r.stderr[-200:]); sys.exit(1)
    import csv
    rows = [r for r in csv.DictReader(open(os.path.join(DATA, "twocar", name, "A.csv"))) if r["state"] == "1"]
    t = np.array([int(r["t"]) for r in rows]) / 60.0; v = np.abs(np.array([float(r["v"]) for r in rows])); top = v.max()
    pk = int(np.argmax(v >= 0.98 * top)); last = max(i for i in range(len(v)) if v[i] > 0.85 * top)
    out = [f"{path} F {FMODE} (v_top {top:.1f}, target decel {a_dec})"]
    for hi, lo in ((0.85 * top, 0.6 * top), (0.6 * top, 0.35 * top), (0.35 * top, 5.0)):
        idx = [i for i in range(last, len(v)) if lo <= v[i] <= hi and t[i] > t[pk] + 3]
        if len(idx) > 20: sl = -np.polyfit(t[idx], v[idx], 1)[0]; out.append(f"  v {hi:5.1f}..{lo:5.1f}: decel {sl:.3f} ({100 * (sl - a_dec) / a_dec:+.1f}%)")
    print("\n".join(out))


if __name__ == "__main__":
    main()
