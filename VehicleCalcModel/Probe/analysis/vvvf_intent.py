#!/usr/bin/env python
# The realized acceleration of every phase of a vvvf run against the intent of the controller (0.5 x the sum of its outputs, w of the model of record) and against the notch deceleration.
#   python vvvf_intent.py <run name>      (e.g. vvvf_1 or vvvf_new_1; the commands are in data/vvvf/run_<...>/)
import sys, os, csv, json
import numpy as np
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
name = sys.argv[1]; tag = name[len("vvvf_"):]
out = os.path.join(DATA, "vvvf", f"run_{tag}"); log = json.load(open(os.path.join(out, "commands.json")))["log"]; res = json.load(open(os.path.join(out, "result.json")))
d, t0 = res["direction"], res["t0"]
rows = [r for r in csv.DictReader(open(os.path.join(DATA, "twocar", name, "A.csv"))) if r["state"] == "1"]
t = np.array([int(r["t"]) for r in rows]); v = d * np.array([float(r["v"]) for r in rows]); mt = np.array([r["t"] for r in log]) + t0
real = np.interp(mt, t, v); model = np.array([x["v"] for x in log])
print(f"{name}: model - real speed: rms {np.sqrt(np.mean((model - real) ** 2)):.3f}  max {np.abs(model - real).max():.3f} m/s")
print("phase          real accel   0.5*sum(N)   notch decel   (real - sum)/sum")
i = 0
while i < len(log):
    j = i; key = (log[i]["pN"], log[i]["bN"])
    while j < len(log) and (log[j]["pN"], log[j]["bN"]) == key: j += 1
    if j - i >= 120:
        sl = slice(i + 60, j - 30); tt = np.arange(len(log))[sl] / 60
        a_real = np.polyfit(tt, real[sl], 1)[0]
        ssum = 0.5 * np.mean([x["n2"] - x["n1M"] - x["n1T"] for x in log[i + 60:j - 30]])
        pn, bn = key; notch = -(bn / 8 / 3.6) if 0 < bn < 31 else float("nan")
        print(f"{'P%d' % pn if pn else 'B%d' % bn:5s} {real[i]:5.1f}->{real[j - 1]:5.1f}  {a_real:+8.3f}   {ssum:+9.3f}   {notch:+9.3f}   {100 * (a_real - ssum) / abs(ssum):+6.1f} %")
    i = j
