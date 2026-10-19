# Runs runcurve-planner (a separate repository, read only) for one trial and writes the trajectory
# (t, x, v, control) as CSV. Usage (WSL venv of runcurve-planner):
#   python runcurve_plan.py generated/routes/<route>.yaml generated/trials/<trial>.yaml plan.csv
# The route and trial paths are relative to examples/hokko_shionaghihama/ of that repository.
import sys, csv
sys.path.insert(0, "/mnt/c/Users/taka/Documents/GitHub/runcurve-planner/src")
from runcurve.main import run_pipeline
from runcurve.controller import switch_points
base="/mnt/c/Users/taka/Documents/GitHub/runcurve-planner/examples/hokko_shionaghihama/"
r = run_pipeline(base+"vehicle.yaml", base+sys.argv[1], base+sys.argv[2])
tr = r.result.trajectory
out = sys.argv[3]
with open(out,"w",newline="") as f:
    w=csv.writer(f); w.writerow(["t","x","v","control"])
    for i in range(len(tr.t)): w.writerow([f"{tr.t[i]:.3f}", f"{tr.x[i]:.2f}", f"{tr.v[i]:.4f}", tr.control[i].kind.name])
print("t_total",tr.t_total,"distance",tr.distance,"samples",len(tr.t),"operations",len(r.result.plan.operations))
for i,x,t in switch_points(tr): print(f"{x:9.1f} m {t:7.1f} s {tr.v[i]*3.6:6.1f} km/h {tr.control[i-1].kind.name}->{tr.control[i].kind.name}")
