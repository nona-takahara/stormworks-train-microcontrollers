#!/usr/bin/env python
# The use cases of the pull / cancel configurations under the final rule (v3 of TWO_CAR_MODEL.md): the resistance cancel is always on.
#   python twocar_use.py [case ...]       (default: all)
# Each run: the puller accelerates the train at a = 0.6 m/s^2 up to 10 m/s (the other car only cancels its resistance), a hold, then a
# deceleration of 1.0 m/s^2 shared as the case says (motor share of car X, brake of car Y; "both" brakes both cars), then a stop.
# Reports the model - measured error (pair.mjs) and the realized acceleration / deceleration against the targets (twocar_realized.py).
import sys, os, json, subprocess, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, "..", "data")
P = {"A": json.load(open(os.path.join(DATA, "params_mo2000.json"))), "B": json.load(open(os.path.join(DATA, "params_ku2100.json")))}
SIGN = {"A": 1, "B": -1}; W, GB = 0.49, 1.05; G = 1 / W
# case: (puller, motor-decel car X, motor share of the deceleration, brake car Y, brake share)
CASES = {
    "use1_motor_only": ("A", "A", 1.0, None, 0.0),
    "use2_brake_only": ("A", None, 0.0, "B", 1.0),
    "use3_half": ("A", "A", 0.5, "B", 0.5),
    "use3_quarter": ("A", "A", 0.25, "B", 0.75),
    "use4_brake_both": ("A", None, 0.0, "both", 1.0),
    "use5_Bpulls_brakeA": ("B", None, 0.0, "A", 1.0),
}
V1, A_ACC, A_DEC = 10.0, 0.6, 1.0


def direction():
    x = json.load(urllib.request.urlopen("http://127.0.0.1:8765/state"))["last"]["x"]
    return 1 if 480 - x > x + 8480 else -1


def program(c, case, d):
    puller, X, mshare, Y, bshare = CASES[case]; p = P[c]; K = p["Sc"] * p["slope"]; sg = SIGN[c] * d; cancel = sg * p["k"] / K
    m_acc = sg * G * A_ACC / K if c == puller else 0.0
    m_dec = sg * (-G * mshare * A_DEC / K) if c == X else 0.0
    brakes = (Y == "both") or (c == Y); share = 0.5 if Y == "both" else bshare
    ci = G * share * A_DEC / (GB * p["B1"]) if brakes else 0.0
    c0 = cancel * p["c1"] * ci
    return ";".join([f"3000/{V1}/1/{m_acc:.5f},{cancel:.6f},0,0/0,0,0,0", f"120/1/0,{cancel:.6f},0,0/0,0,0,0",
                     f"1500/-2/2/{m_dec + c0:.5f},{cancel:.6f},0,0/0,0,0,{ci:.4f}", "600/-0.2/1/0,0,0,0/0.5,0,0,0"])


def main():
    d = direction(); cases = sys.argv[1:] or list(CASES)
    for case in cases:
        name = case + "_v3"
        r = subprocess.run([sys.executable, os.path.join(HERE, "twocar.py"), name, program("A", case, d), program("B", case, d)], capture_output=True, text=True)
        if r.returncode != 0: print(case, "run failed:", r.stdout[-300:], r.stderr[-200:]); sys.exit(1)
        err = subprocess.run(["node", os.path.join(HERE, "pair.mjs"), os.path.join(DATA, "twocar", name)], capture_output=True, text=True).stdout.strip()
        sys.path.insert(0, HERE); from twocar_realized import realized
        top, ra, rd = realized(name)
        print(f"{case:20s} dir {d:+d}  {err} | top {top:.1f}  accel {ra:.3f} (target {A_ACC}, {100 * (ra - A_ACC) / A_ACC:+.1f}%)  decel {rd:.3f} (target {A_DEC}, {100 * (rd - A_DEC) / A_DEC:+.1f}%)")


if __name__ == "__main__":
    main()
