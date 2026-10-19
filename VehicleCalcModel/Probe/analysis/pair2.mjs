// The two-mass model (the coupler) of the model of record: `fwd.mjs` (simulate2m, score2m), Kc and Cc from fit_coupler.mjs.
//   node pair2.mjs <twocar folder> [--k 30] [--c 3]     the errors of the speed of car A, car B and the gap
import path from "node:path";
import { THETA2, loadRun, score2m } from "./fwd.mjs";

const o = (n, d) => (process.argv.includes(n) ? +process.argv[process.argv.indexOf(n) + 1] : d);
const run = loadRun(path.basename(path.resolve(process.argv[2])));
if (!run) { console.log("no run"); process.exit(1); }
const e = score2m(run, THETA2, o("--k", 30), o("--c", 3));
console.log(["A", "B", "d"].map((k) => `${k}: rms ${e[k].rms.toFixed(3)} max ${e[k].max.toFixed(3)}`).join("   "));
