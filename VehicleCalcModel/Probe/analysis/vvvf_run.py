#!/usr/bin/env python
# Injects the commands made by vvvf_closedloop.mjs into the real pair and compares the real speed with the model speed of the closed loop.
#   python vvvf_run.py <seed> [seg_ticks]
# The command of every car is held for seg_ticks ticks (default 6); the program has one segment per hold. Direction: the side with more room.
import sys, os, json, subprocess, urllib.request
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, "..", "data")


def main():
    seed = int(sys.argv[1]); seg = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    tag = "new_" if os.environ.get("NEWIC") else ""     # NEWIC=1: the new inertia compensation (INERTIA_COMPENSATION_NEW.md)
    out = os.path.join(DATA, "vvvf", f"run_{tag}{seed}")
    subprocess.run(["node", os.path.join(HERE, "vvvf_closedloop.mjs"), str(seed), out], check=True)
    cmd = json.load(open(os.path.join(out, "commands.json")))["log"]
    x = json.load(urllib.request.urlopen("http://127.0.0.1:8765/state"))["last"]["x"]
    dist = sum(r["v"] for r in cmd) / 60; d = 1 if 480 - x > x + 8480 else -1; room = (480 - x) if d == 1 else (x + 8480)
    if room < dist + 800: print(f"no room: x {x:.0f}, distance {dist:.0f} m, room {room:.0f} m"); sys.exit(1)
    # the commands in segments of seg_ticks (the mean of the tick commands), in the forward frame; car A has +motor toward +x, car B the opposite
    prog = {}
    for car, sgn, km, kb in (("A", d, "mM", "bM"), ("B", -d, "mT", "bT")):
        segs = []
        for i in range(0, len(cmd), seg):
            w = cmd[i:i + seg]; m = sum(r[km] for r in w) / len(w); b = sum(r[kb] for r in w) / len(w)
            segs.append(f"{len(w)}/1/{sgn * m:.6f},0,0,0/{b:.5f},0,0,0")
        segs.append("600/-0.2/1/0,0,0,0/0.5,0,0,0"); prog[car] = ";".join(segs)
    print(f"direction {d:+d}, x {x:.0f}, distance {dist:.0f} m, segments {len(segs)}, program {len(prog['A'])} chars")
    name = f"vvvf_{tag}{seed}"
    r = subprocess.run([sys.executable, os.path.join(HERE, "twocar.py"), name, prog["A"], prog["B"]], capture_output=True, text=True)
    print(r.stdout[-400:].strip().replace("\n", " | ")[:300], r.stderr[-300:])
    compare(name, cmd, d, out)


def compare(name, cmd, d, out):
    import csv
    rows = list(csv.DictReader(open(os.path.join(DATA, "twocar", name, "A.csv"))))
    run = [r for r in rows if r["state"] == "1"]
    t0 = int(run[0]["t"]); t = np.array([int(r["t"]) for r in run]); v = d * np.array([float(r["v"]) for r in run])
    tb = np.array([int(r["t"]) for r in csv.DictReader(open(os.path.join(DATA, "twocar", name, "B.csv"))) if r["state"] == "1"])
    mod_t = np.array([r["t"] for r in cmd]) + t0; mod_v = np.array([r["v"] for r in cmd])
    real = np.interp(mod_t, t, v)
    e = mod_v - real
    print(f"model - real speed over the {len(cmd)} ticks of the pattern: rms {np.sqrt(np.mean(e ** 2)):.3f}  max {np.abs(e).max():.3f} m/s (at {np.argmax(np.abs(e)) / 60:.0f} s, v {real[np.argmax(np.abs(e))]:.1f});  mean {e.mean():+.3f}")
    ph = [("P%d" % r["pN"] if r["pN"] else ("B%d" % r["bN"] if r["bN"] else "coast")) for r in cmd]
    print("phase                 ticks  rms    max   mean   [m/s]  (model - real)")
    i = 0
    while i < len(cmd):
        j = i
        while j < len(cmd) and ph[j] == ph[i]: j += 1
        if j - i >= 30: print(f"{ph[i]:6s} v {real[i]:5.1f}->{real[j - 1]:5.1f}  {j - i:5d}  {np.sqrt(np.mean(e[i:j] ** 2)):.3f}  {np.abs(e[i:j]).max():.3f}  {e[i:j].mean():+.3f}")
        i = j
    json.dump(dict(error_rms=float(np.sqrt(np.mean(e ** 2))), error_max=float(np.abs(e).max()), t0=t0, direction=d), open(os.path.join(out, "result.json"), "w"))


if __name__ == "__main__":
    main()
