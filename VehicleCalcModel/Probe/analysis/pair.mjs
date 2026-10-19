// The forward model of the pair is `fwd.mjs` (the model of record, THETA2). This file keeps the old entry points on top of it:
//   Car, BRAKE_GAIN  for rule_sim.mjs and vvvf_closedloop.mjs (the single-car dynamics with the terms of the model of record),
//   node pair.mjs <twocar folder>   the model - measured error of a run (the speed of the two cars' mean), as before.
import path from "node:path";
import { CarX, THETA2, loadRun, score } from "./fwd.mjs";

export const BRAKE_GAIN = THETA2.beta;
export class Car extends CarX { constructor(P, sign, th = THETA2) { super(P, sign, th); } }

if (process.argv[1] && process.argv[1].endsWith("pair.mjs")) {
    const run = loadRun(path.basename(path.resolve(process.argv[2])));
    if (!run) { console.log("no run"); process.exit(1); }
    const r = score(run, THETA2);
    console.log(`w ${THETA2.w}: rms ${r.rms.toFixed(3)} max ${r.max.toFixed(3)} m/s (${r.n} samples)`);
}
