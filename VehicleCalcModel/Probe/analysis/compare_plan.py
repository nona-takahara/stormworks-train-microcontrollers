# Compares the last long probe program in ../data/log.csv with the planned run curve (plan.csv).
# Usage: python compare_plan.py plan.csv ../data/log.csv [--nth 2]
import csv, sys
import numpy as np
plan = list(csv.DictReader(open(sys.argv[1])))
pt = np.array([float(r["t"]) for r in plan]); pv = np.array([float(r["v"]) for r in plan]); px = np.array([float(r["x"]) for r in plan])
rows = [l.split(",") for l in open(sys.argv[2]).read().split("\n")[1:] if l]
rows = [r for r in rows if len(r) >= 13]
# take the final contiguous program: scan backward from the end for the last state==1 block
blocks = []; cur = []
for r in rows:
    if int(r[10]) == 1 and (not cur or int(r[2]) - int(cur[-1][2]) <= 62): cur.append(r)
    else:
        if int(r[10]) == 1: cur = [r]
        elif cur: blocks.append(cur); cur = []
if cur: blocks.append(cur)
longs = [x for x in blocks if len(x) > 1000]
nth = int(sys.argv[sys.argv.index('--nth') + 1]) if '--nth' in sys.argv else 1  # 1 = the last long program in the log, 2 = the one before
b = longs[-nth]
t0 = int(b[0][2]); x0 = float(b[0][3])
T = np.array([(int(r[2]) - t0) / 60 for r in b]); V = np.abs(np.array([float(r[6]) for r in b])); X = np.abs(np.array([float(r[3]) - x0 for r in b]))  # |v|, |distance|: a run toward -x is the mirror image
Vp = np.interp(T, pt, pv, right=0.0); Xp = np.interp(T, pt, px - px[0], right=px[-1] - px[0])
e = V - Vp
moving = T <= pt[-1]
print(f"program ran {T[-1]:.1f} s; plan {pt[-1]:.1f} s")
print(f"speed error over the plan duration: max {np.abs(e[moving]).max():.3f} m/s, rms {np.sqrt((e[moving]**2).mean()):.3f} m/s")
i = int(np.abs(e[moving]).argmax()); print(f"  worst at t={T[i]:.1f} s: game {V[i]:.2f} vs plan {Vp[i]:.2f} m/s")
for q in (10, 30, 60, 70, 90, 100, 110, 120, 130, 138):
    j = int(np.abs(T - q).argmin()); print(f"  t={q:3d} s: game v {V[j]:6.2f}  plan {Vp[j]:6.2f}  err {e[j]:+.2f} | game s {X[j]:7.1f} plan s {Xp[j]:7.1f} diff {X[j]-Xp[j]:+.1f} m")
stop_t = T[np.argmax((T > 100) & (np.abs(V) < 0.05))]
print(f"stop (|v|<0.05) at t={stop_t:.1f} s (plan {pt[-1]:.1f} s), distance {X[np.argmax(T >= stop_t)]:.1f} m (plan {px[-1]-px[0]:.1f} m)")
d_end = abs(float(b[-1][3]) - x0)
print(f"final x {float(b[-1][3]):.1f}, distance {d_end:.1f} m, plan {px[-1]-px[0]:.1f} m, diff {d_end - (px[-1]-px[0]):+.1f} m")
print(f"max motor in the run {max(float(r[7]) for r in b):.3f}, max brake {max(float(r[8]) for r in b):.3f}, slip flag seen: {any(len(r)>12 and r[12] not in ('','0') for r in b)}")
