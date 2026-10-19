#!/usr/bin/env python
# The weakening of the motor by the brake of the same car, at the level of the resistance cancel (small motor, small brake):
#   python f_test.py <A|B> [v_top]
# The pair is brought to v_top (the cancel on, car A pulls), then ONE car brakes in steps (b = 0.02, 0.03, 0.05, 0.08, 2.5 s each) while both cars keep the cancel
# (no compensation of F). The deceleration above the brake law  w beta (B1 b + B2 b^2) |v|  is the loss of the cancel drive:  w (1 - F(b)) cancel_drive.
import sys, os, json, subprocess, urllib.request
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, "..", "data")
P = {"A": json.load(open(os.path.join(DATA, "params_mo2000.json"))), "B": json.load(open(os.path.join(DATA, "params_ku2100.json")))}
KFIT = {"A": 0.1062, "B": 0.0939}; K2 = 8e-5; SIGN = {"A": 1, "B": -1}; W = float(os.environ.get("W", 0.49)); G = 1 / W; BETA = float(os.environ.get("BETA", 1.05))   # the model of record: W 0.5, BETA 1 (TWO_CAR_MODEL.md)
STEPS = [0.02, 0.03, 0.05, 0.08]; LEN = 150


def build(c, who, vtop, d):
    p = P[c]; K = p["Sc"] * p["slope"]; sg = SIGN[c] * d; gam, vk = p["gamma"], p["vk"]
    ck = sg * 1.02 * KFIT[c] / K; cq = sg * 1.02 * K2 / K; m_acc = sg * G * 0.6 / K if c == "A" else 0.0
    cancel = f"{ck:.8f},{cq:.10f},0"
    segs = [f"4800/{vk:.2f}/1/{m_acc:.8f},{ck:.8f},{cq:.10f},0/0,0,0,0",
            f"4800/{vtop:.2f}/1/{m_acc * (1 - gam * vk):.8f},{ck + m_acc * gam:.8f},{cq:.10f},0/0,0,0,0", f"120/1/0,{ck:.8f},{cq:.10f},0/0,0,0,0"]
    for b in STEPS: segs.append(f"{LEN}/1/0,{ck:.8f},{cq:.10f},0/{b if c == who else 0.0:.4f},0,0,0")
    segs.append("600/-0.2/1/0,0,0,0/0.5,0,0,0"); return ";".join(segs)


def main():
    who = sys.argv[1]; vtop = float(sys.argv[2]) if len(sys.argv) > 2 else 29.0
    x = json.load(urllib.request.urlopen("http://127.0.0.1:8765/state"))["last"]["x"]
    d = 1 if 480 - x > x + 8480 else -1; room = (480 - x) if d == 1 else (x + 8480)
    if room < vtop ** 2 + 1500: print("no room", x); sys.exit(1)
    name = f"ftest_{who}"
    r = subprocess.run([sys.executable, os.path.join(HERE, "twocar.py"), name, build("A", who, vtop, d), build("B", who, vtop, d)], capture_output=True, text=True)
    if r.returncode != 0: print("run failed", r.stdout[-300:], r.stderr[-200:]); sys.exit(1)
    import csv
    rows = [r for r in csv.DictReader(open(os.path.join(DATA, "twocar", name, "A.csv"))) if r["state"] == "1"]
    t = np.array([int(r["t"]) for r in rows]) / 60.0; v = np.abs(np.array([float(r["v"]) for r in rows])); seg = np.array([int(r["reason"]) for r in rows])
    p = P[who]
    print(f"brake on car {who}: weakening of the cancel drive (1 - F) at the level of the cancel")
    print("   b    v    decel   brake-law decel   excess   cancel drive   (1-F)    (1-F)/b   c1 b of the model")
    for i, b in enumerate(STEPS):
        s = seg == 4 + i
        if s.sum() < 60: print(b, "no data"); continue
        tt, vv = t[s], v[s]; m = tt >= tt[0] + 0.7
        a = -np.polyfit(tt[m], vv[m], 1)[0]; vm = vv[m].mean()
        brake = W * BETA * (p["B1"] * b + p["B2"] * b * b) * vm if b >= 0.0113 else 0.0
        cdrive = 1.02 * (KFIT[who] * vm + K2 * vm * vm); excess = a - brake - W * (-0.0) ; f1 = excess / (W * cdrive)
        print(f"{b:5.2f} {vm:5.1f}  {a:6.3f}   {brake:8.3f}        {excess:+7.3f}   {cdrive:8.3f}     {f1:+.3f}   {f1 / b:+.2f}      {p['c1'] * b:.3f}")


if __name__ == "__main__":
    main()
