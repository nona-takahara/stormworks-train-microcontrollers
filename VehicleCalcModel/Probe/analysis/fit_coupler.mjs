// The coupler (stage 3) on the model of record: Kc and Cc fitted on the step runs, then the speed of car A, car B and the gap over all runs.
import { corpus, simulate, score2m, THETA1 } from "./fwd.mjs";
const runs = corpus("."), step = runs.filter((r) => /^(passive_B|cancel_B|drive_B_only|use1_motor_only$|use3_share_0.5$)/.test(r.name));
let best = [9];
for (const K of [15, 20, 25, 30, 35, 40, 50]) for (const C of [1, 2, 3, 4, 6]) { const c = Math.sqrt(step.reduce((s, r) => { const e = score2m(r, THETA1, K, C); return s + e.A.rms ** 2 + e.B.rms ** 2; }, 0) / step.length); if (c < best[0]) best = [c, K, C]; }
const [, Kc, Cc] = best; console.log(`step runs (${step.length}): best Kc ${Kc}, Cc ${Cc}`);
const rigidA = (r) => { const sim = simulate(r, THETA1); let mx = 0; for (const x of r.A) { const q = sim.get(x.t); if (q !== undefined) mx = Math.max(mx, Math.abs(q - x.v)); } return mx; };
console.log("step runs: max error of the speed of car A: rigid model | two-mass model (A, B, gap)");
for (const r of step) { const e = score2m(r, THETA1, Kc, Cc); console.log("  ", r.name.padEnd(20), rigidA(r).toFixed(3), "|", e.A.max.toFixed(3), e.B.max.toFixed(3), e.d.max.toFixed(3)); }
let mxA = 0, mxB = 0, mxd = 0, q = 0; for (const r of runs) { const e = score2m(r, THETA1, Kc, Cc); mxA = Math.max(mxA, e.A.max); mxB = Math.max(mxB, e.B.max); mxd = Math.max(mxd, e.d.max); q += e.A.rms ** 2; }
console.log(`all ${runs.length} runs, two-mass: max error of A ${mxA.toFixed(3)}, B ${mxB.toFixed(3)}, gap ${mxd.toFixed(3)} m; mean rms of A ${Math.sqrt(q / runs.length).toFixed(3)}`);
