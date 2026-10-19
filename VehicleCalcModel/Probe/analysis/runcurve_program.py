# Usage: python runcurve_program.py plan.csv program.txt [--mirror] [--stop unified] [--b-stop 2.0] [--params K,k,B_stop,c]
#   --mirror: run in the -x direction (motor coefficients negated; the model is odd in the motor and the speed)
#   --stop unified: the stop is one segment, o_b = a_b/(B v), o_m = (k v)/(K (1 - c o_b)) as a series in v
# Turns a planned run curve (plan.csv from runcurve_plan.py) into a probe program: the motor cancels the
# running resistance (k*v) and adds the planned acceleration, with feedback on the planned speed v_ref(t);
# the stop uses the constant-deceleration brake law. Usage: python runcurve_program.py plan.csv program.txt
# The program text is one `campaign.mjs` step (see campaign.mjs).
import csv, sys
import numpy as np
K, k, B, g, cc = 36.69, 0.1079, 2.108, 0.02, 0.947
if '--params' in sys.argv:  # vehicle: K,k,B_stop,c   (the 1800: 30.43,0.1091,1.5,0.65)
    K, k, B, cc = [float(x) for x in sys.argv[sys.argv.index('--params') + 1].split(',')]
MIRROR = '--mirror' in sys.argv
UNIFIED = '--stop' in sys.argv and sys.argv[sys.argv.index('--stop') + 1] == 'unified'
B_EFF = float(sys.argv[sys.argv.index('--b-stop') + 1]) if '--b-stop' in sys.argv else (B if '--params' in sys.argv else 1.97)  # brake effectiveness for the stop (about 2.0 for o_b above the dead zone of 0.011)
rows = list(csv.DictReader(open(sys.argv[1])))
t = np.array([float(r["t"]) for r in rows]); v = np.array([float(r["v"]) for r in rows]); ctl = [r["control"] for r in rows]
# the planner's brake starts at the first sample whose control is BRAKE*
ib = next(i for i, c in enumerate(ctl) if c.startswith("BRAKE"))
tb = t[ib]
# resample v(t) every 0.1 s up to tb and fit piecewise-linear (Douglas-Peucker on the (t, v) polyline, eps in m/s)
tt = np.arange(0, tb, 0.1); vv = np.interp(tt, t, v)
def dp(pts, eps):
    if len(pts) < 3: return [0, len(pts) - 1]
    a, b = pts[0], pts[-1]
    d = np.abs((b[1]-a[1])*pts[:,0] - (b[0]-a[0])*pts[:,1] + b[0]*a[1] - b[1]*a[0]) / np.hypot(b[0]-a[0], b[1]-a[1]) if False else None
    # vertical error against the chord (better suited to v(t))
    chord = a[1] + (b[1]-a[1]) * (pts[:,0]-a[0]) / (b[0]-a[0])
    err = np.abs(pts[:,1] - chord); i = int(err.argmax())
    if err[i] <= eps: return [0, len(pts) - 1]
    left = dp(pts[:i+1], eps); right = dp(pts[i:], eps)
    return left[:-1] + [x + i for x in right]
pts = np.column_stack([tt, vv]); idx = dp(pts, 0.08)
segs = []
for a, b in zip(idx[:-1], idx[1:]):
    t0, v0, t1, v1 = tt[a], vv[a], tt[b], vv[b]
    acc = (v1 - v0) / (t1 - t0); n = round((t1 - t0) * 60)
    # motor = (acc + k v)/K + g (v_ref - v),  v_ref = v0 + acc*tau
    c0 = (acc + g * K * v0) / K; c1 = k / K - g; ct = g * acc
    segs.append((n, 0, 1, (c0, c1, 0, 0, ct, 0, 0), (0,) * 7))
# stop phase: planned decel a_dec
a_dec = 0.8
if UNIFIED:
    # a_m = 0, a_b = a_dec:  o_b = a_b/(B v),  o_m ~ (k/K) v + k c a_b/(K B) + k c^2 a_b^2/(K B^2)/v
    segs.append((3000, -0.05, 0.4,
                 (k * cc * a_dec / (K * B_EFF), k / K, 0, k * cc * cc * a_dec * a_dec / (K * B_EFF * B_EFF), 0, 0, 0),
                 (0, 0, 0, a_dec / B_EFF, 0, 0, 0)))
else:
    segs.append((9999, -(a_dec / k), 1, (-a_dec / K, k / K, 0, 0, 0, 0, 0), (0,) * 7))
    segs.append((9999, -0.05, 0.4, (0,) * 7, (-k / B, 0, 0, a_dec / B, 0, 0, 0)))
segs.append((300, 0, 1, (0,) * 7, (1, 0, 0, 0, 0, 0, 0)))
if MIRROR:
    segs = [(n, ve, vm, tuple(-c for c in m), b) for n, ve, vm, m, b in segs]
def fmt(x): return f"{x:.6g}"
step = ";".join(f"{n}/{ve:g}/{vm:g}/{','.join(fmt(c) for c in m)}/{','.join(fmt(c) for c in b)}" for n, ve, vm, m, b in segs)
open(sys.argv[2], "w").write(step)
print("segments:", len(segs), "power/coast pieces:", len(idx) - 1, "brake starts at", round(tb, 1), "s, v =", round(float(np.interp(tb, t, v)), 2))
for n, ve, vm, m, b in segs[:len(idx)-1]: print(f"  {n/60:6.1f} s  accel -> m = {m[0]:+.4f} {m[1]:+.5f} v {m[4]:+.5f} tau")
print("program text length:", len(step))
