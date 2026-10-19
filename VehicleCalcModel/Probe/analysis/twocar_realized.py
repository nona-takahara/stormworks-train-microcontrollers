#!/usr/bin/env python
# The train's realized acceleration and deceleration of a run (car A's speed), the same way for every run.
#   python twocar_realized.py <twocar folder>...      (a name under data/twocar)
# Acceleration: the straight-line slope of v between 25% and 75% of the top speed, before the top.
# Deceleration: the slope of v from 85% of the top speed down to 3 m/s, from the end of the hold on (the hold is the 120 tick after the top).
import sys, os, csv
import numpy as np
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "twocar")


def realized(name):
    rows = list(csv.DictReader(open(os.path.join(DATA, name, "A.csv"))))
    t = np.array([float(r["t"]) for r in rows]) / 60; v = np.abs(np.array([float(r["v"]) for r in rows])); top = v.max()
    pk = int(np.argmax(v >= 0.98 * top))
    acc = [i for i in range(pk) if 0.25 * top < v[i] < 0.75 * top]
    dec = [i for i in range(pk, len(v)) if 3 <= v[i] <= 0.85 * top and t[i] > t[pk] + 2.5 and v[i] < v[pk]]
    # the deceleration window starts when v is falling for good: after the last time v is above 0.85 top
    last_hi = max((i for i in range(len(v)) if v[i] > 0.85 * top), default=pk); dec = [i for i in dec if i > last_hi]
    sl = lambda idx: np.polyfit(t[idx], v[idx], 1)[0] if len(idx) > 5 else float("nan")
    return top, sl(acc), -sl(dec)


if __name__ == "__main__":
    for n in sys.argv[1:]:
        top, a, d = realized(n); print(f"{n:22s} top {top:5.1f} m/s  accel {a:6.3f}  decel {d:6.3f}")
