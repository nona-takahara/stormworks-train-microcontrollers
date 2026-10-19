#!/usr/bin/env python
# The identification of the pair as one automatic flow (PAIR_FIT_PLAN.md): run the experiments, fit, judge.
#   python pair_flow.py
# Steps: the one-car drive runs, the table of levels from them (and the guard), the runs of role fit / check / info, then the fit and the judgement (pair_loop.mjs).
# No step needs a person or a model to decide anything: the branches are exit codes (0 pass, 4 not passed, 5 a car does not match its single-car parameters).
import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))


def sh(*cmd):
    print("$", " ".join(cmd), flush=True)
    return subprocess.run(cmd, cwd=HERE).returncode


def main():
    # 0. the one-car drive runs first: they give the drive and the mass fraction of the pair, which set the motor of the equilibrium levels (pair_plan.mjs table);
    #    a car whose drive is more than 20% off its single-car K ends the flow here (exit 5)
    cfg = json.load(open(os.path.join(HERE, "..", "data", "pair_config.json"), encoding="utf-8"))
    pilots = ["drive_onlyA_f60"] + ([] if "B" not in cfg else ["drive_onlyB_f60"])   # a single car has one pilot
    if sh(sys.executable, "pair_run.py", *pilots): sys.exit(1)
    rc = sh("node", "pair_plan.mjs", "table", "--write", "--guard")
    if rc == 5: print("STOPPED: the one-car drive of a car is more than 20% off its single-car K (or the mass fraction is outside 0.3 - 0.7); check the vehicle (wiring, equipment) or identify the car again"); sys.exit(5)
    if rc: sys.exit(1)
    if sh(sys.executable, "pair_run.py", "fit", "check", "info"): sys.exit(1)
    rc = sh("node", "pair_loop.mjs")
    print("pass" if rc == 0 else "NOT PASSED: see data/pair_fit_result.json (checkFailed, onBound, deadZoneUnbracketed, deadZoneMismatch)")
    sys.exit(0 if rc == 0 else 4)


if __name__ == "__main__":
    main()
