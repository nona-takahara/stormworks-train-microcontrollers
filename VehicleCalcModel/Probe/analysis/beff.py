# Brake effectiveness vs command: for the last 10 programs (accelerate to 22 m/s, hold one constant brake level),
# the decay rate of |v| in the brake segment (the 2nd one) gives  rate = k + B_eff*o_b.
# Usage: python beff.py ../data/log.csv 0,0.01,0.02,...
import sys, math
rows = [l.split(",") for l in open(sys.argv[1]).read().split("\n")[1:] if l]
rows = [r for r in rows if len(r) >= 13]
levels = [float(x) for x in sys.argv[2].split(",")]
blocks = []; cur = []
for r in rows:
    if int(r[10]) == 1 and (not cur or int(r[2]) - int(cur[-1][2]) <= 62): cur.append(r)
    else:
        if int(r[10]) == 1: cur = [r]
        elif cur: blocks.append(cur); cur = []
if cur: blocks.append(cur)
runs = [b for b in blocks if len(b) > 100][-len(levels):]
res = []
for lv, b in zip(levels, runs):
    seg = [(int(r[2]), abs(float(r[6]))) for r in b if int(r[11]) == 2]
    t0 = seg[0][0]
    pts = [(t, v) for t, v in seg if t - t0 >= 8 and v > 3.0]       # after the delay, while the speed is well above 0
    if len(pts) < 8: print(f"o_b={lv}: too few samples"); continue
    xs = [(t - pts[0][0]) / 60 for t, _ in pts]; ys = [math.log(v) for _, v in pts]
    n = len(xs); mx = sum(xs) / n; my = sum(ys) / n
    slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)
    res.append((lv, -slope, pts[0][1], pts[-1][1], n))
k = next(r[1] for r in res if r[0] == 0)
print(f"coast rate k = {k:.4f} 1/s (o_b = 0)")
print(" o_b   rate [1/s]  B_eff = (rate-k)/o_b   v range      n")
for lv, rate, v0, v1, n in res:
    if lv > 0: print(f"{lv:5.2f}  {rate:9.4f}  {(rate - k) / lv:9.3f}          {v0:5.1f}->{v1:4.1f}  {n}")
