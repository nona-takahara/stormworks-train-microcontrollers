#!/usr/bin/env python
# Runs the experiments of pair_experiments.json on the pair of data/pair_config.json in the direction with more room.
#   python pair_run.py [role|id ...]      role: fit | check | info (default: fit check info). A finished experiment (data/twocar/pf_<id>/A.csv) is skipped.
# The programs come from `node pair_plan.mjs program <id> <dir>`; twocar.py runs both cars at the same moment and cuts the logs.
import sys, os, json, subprocess, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, "..", "data")
LO, HI = -8480, 480   # the track limits of probe_site.lua


CFG = json.load(open(os.path.join(DATA, "pair_config.json"), encoding="utf-8"))


def travel_dir():
    x = json.load(urllib.request.urlopen(f"http://127.0.0.1:{CFG['A']['port']}/state"))["last"]["x"]
    return 1 if HI - x > x - LO else -1


def main():
    exps = json.load(open(os.path.join(HERE, "pair_experiments.json"), encoding="utf-8"))["experiments"]
    want = sys.argv[1:] or ["fit", "check", "info"]
    todo = [e for e in exps if e["role"] in want or e["id"] in want]
    for e in todo:
        name = f"pf_{e['id']}"
        if os.path.exists(os.path.join(DATA, "twocar", name, "A.csv")): print(f"{name}: done, skipped"); continue
        d = travel_dir()
        progs = json.loads(subprocess.run(["node", os.path.join(HERE, "pair_plan.mjs"), "program", e["id"], str(d)], capture_output=True, text=True, check=True).stdout)
        print(f"{name}: direction {d:+d} ...", flush=True)
        r = subprocess.run([sys.executable, os.path.join(HERE, "twocar.py"), name, progs["A"], progs.get("B", "")], capture_output=True, text=True)
        print(r.stdout.strip()[-300:])
        if r.returncode != 0: print(f"{name}: FAILED", r.stderr.strip()[-300:]); sys.exit(1)


if __name__ == "__main__":
    main()
