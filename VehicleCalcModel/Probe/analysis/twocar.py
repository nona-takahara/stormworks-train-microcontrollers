#!/usr/bin/env python
# One run on a coupled pair: the same moment, one program per car, both logs cut out with the time offset between the two probes.
#   python twocar.py <name> "<program A>" "<program B>"
# A is the car on port 8765 (log.csv), B the car on 8766 (log_8766.csv). A program is the argument of campaign.mjs (steps joined by space),
# written in each car's own motor sign: car B (ku2100) has +motor toward -x, so a push toward +x of both cars is +m on A and -m on B.
# Result: data/twocar/<name>/A.csv, B.csv (the rows of the run), sync.txt (the offset d, tB = tA + d).
import sys, os, json, subprocess, shlex, threading
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, "..", "data")
CFG = json.load(open(os.path.join(DATA, "pair_config.json"), encoding="utf-8"))   # the pair: ports and server logs
CARS = {c: (CFG[c]["port"], CFG[c]["log"]) for c in "AB" if c in CFG}   # a single car (no "B" in the config) is run alone


def nrows(f): return sum(1 for _ in open(os.path.join(DATA, f)))


def campaign(port, prog, out):
    cmd = ["node", os.path.join(HERE, "campaign.mjs"), "--url", f"http://127.0.0.1:{port}", "--mmax", "0.5", "--bmax", "1", "--vmax", "30"] + shlex.split(prog)
    out.append(subprocess.run(cmd, capture_output=True, text=True))


def main():
    name, progs = sys.argv[1], {"A": sys.argv[2], "B": sys.argv[3] if len(sys.argv) > 3 else ""}
    n0 = {c: nrows(f) for c, (_, f) in CARS.items()}; res = {c: [] for c in CARS}
    ts = [threading.Thread(target=campaign, args=(CARS[c][0], progs[c], res[c])) for c in CARS]
    for t in ts: t.start()
    for t in ts: t.join()
    out = os.path.join(DATA, "twocar", name); os.makedirs(out, exist_ok=True); ok = True
    for c, (_, f) in CARS.items():
        lines = open(os.path.join(DATA, f)).read().split("\n"); head = lines[0]
        open(os.path.join(out, f"{c}.csv"), "w").write(head + "\n" + "\n".join(lines[n0[c]:]))
        r = res[c][0]; ok &= r.returncode == 0; print(c, r.stdout.strip().replace("\n", " | ") or r.stderr.strip()[-200:])
    json.dump({c: progs[c] for c in CARS}, open(os.path.join(out, "programs.json"), "w"), indent=1)
    if len(CARS) == 1: sys.exit(0 if ok else 1)   # one car: no time offset between probes to read
    s = subprocess.run(["node", os.path.join(HERE, "twocar_sync.mjs"), os.path.join(out, "A.csv"), os.path.join(out, "B.csv")], capture_output=True, text=True)
    open(os.path.join(out, "sync.txt"), "w").write(s.stdout); print(s.stdout.strip())
    sys.exit(0 if ok and s.returncode == 0 else 1)


if __name__ == "__main__":
    main()
