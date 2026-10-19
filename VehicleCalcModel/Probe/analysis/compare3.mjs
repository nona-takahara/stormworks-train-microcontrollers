#!/usr/bin/env node
// Compares one scenario run (the folder written by scenario.py) three ways, per phase and overall:
//   ideal (the planned speed)   model (simulate2 driven by the logged motor and brake)   measured
// I-M: how far the vehicle is from the plan.  Mo-M: how wrong the model is.  I-Mo: how well the feed-forward inverts the model.
// Refuses (exit 1) when the run is not the planned one: segment count or duration differs.
// Usage: node compare3.mjs <scenario folder>
import fs from "node:fs";
import path from "node:path";
import { readRuns } from "./fit.mjs";
import { simulate2 } from "./axle2.mjs";

const dir = process.argv[2];
const plan = JSON.parse(fs.readFileSync(path.join(dir, "plan.json"), "utf8"));
const P = JSON.parse(fs.readFileSync(path.join(dir, "params.json"), "utf8"));
const ref = fs.readFileSync(path.join(dir, "ref.csv"), "utf8").trim().split("\n").slice(1).map((l) => l.split(",")).map(([t, v, label]) => ({ t: +t, v: +v, label }));
const runs = readRuns(fs.readFileSync(path.join(dir, "rows.csv"), "utf8"));
const run = runs.reduce((a, r) => (r.length > a.length ? r : a), []);
const fail = (msg) => { console.log(`  REFUSED: ${msg}`); process.exit(1); };
if (!run.length) fail("no RUN samples");
const seg = Math.max(...run.map((x) => x.seg)), dur = (run[run.length - 1].t - run[0].t) / 60;
if (seg !== plan.segments) fail(`the probe ran ${seg} of ${plan.segments} segments`);
// the stop is a speed-conditioned law (vend), so a run may end earlier than the plan; the segment count shows that it ran to the end
if (dur < plan.duration * 0.5 || dur > plan.duration + 12) fail(`duration ${dur.toFixed(1)} s, planned ${plan.duration.toFixed(1)} s`);
if (run.some((x) => x.slip)) console.log("  note: slip samples in this run");

const sgn = plan.mirror ? -1 : 1, sim = simulate2(run, P), t0 = run[0].t;
// model B (delays fitted to the frequency response), when the folder has its parameters
const PB = fs.existsSync(path.join(dir, "params_freq.json")) ? JSON.parse(fs.readFileSync(path.join(dir, "params_freq.json"), "utf8")) : null, simB = PB ? simulate2(run, PB) : null;
const rows = run.map((x, i) => {
    const t = (x.t - t0) / 60, j = Math.min(ref.length - 1, Math.round(t * 60));
    return { t, label: ref[j].label, I: ref[j].v, M: sgn * x.v, Mo: sgn * sim[i].v, MoB: simB ? sgn * simB[i].v : NaN, brake: x.brake, motor: sgn * x.motor };
});
const stat = (a) => `${(a.reduce((s, x) => s + x, 0) / a.length >= 0 ? "+" : "")}${(a.reduce((s, x) => s + x, 0) / a.length).toFixed(3)}/${Math.max(...a.map(Math.abs)).toFixed(3)}`;
const pad = (s, n) => String(s).padEnd(n);
console.log(`  ${seg} segments, ${dur.toFixed(1)} s; errors are mean/max in m/s (signed mean, max |e|)`);
console.log(`  ${pad("phase", 24)}${pad("t [s]", 13)}${pad("I-M", 16)}${pad("Mo-M", 16)}I-Mo`);
const labels = [...new Set(rows.map((r) => r.label))];
for (const lb of labels) {
    const w = rows.filter((r) => r.label === lb); if (w.length < 3) continue;
    console.log(`  ${pad(lb, 24)}${pad(`${w[0].t.toFixed(0)}-${w[w.length - 1].t.toFixed(0)}`, 13)}${pad(stat(w.map((r) => r.I - r.M)), 16)}${pad(stat(w.map((r) => r.Mo - r.M)), 16)}${stat(w.map((r) => r.I - r.Mo))}`);
}
const rms = (f) => Math.sqrt(rows.reduce((s, r) => s + f(r) ** 2, 0) / rows.length).toFixed(3);
const mx = (f) => Math.max(...rows.filter((r) => r.brake < 0.9).map((r) => Math.abs(f(r)))).toFixed(3);
console.log(`  overall rms (max without the hard stop, brake>=0.9):  I-M ${rms((r) => r.I - r.M)} (${mx((r) => r.I - r.M)})   Mo-M ${rms((r) => r.Mo - r.M)} (${mx((r) => r.Mo - r.M)})   I-Mo ${rms((r) => r.I - r.Mo)} (${mx((r) => r.I - r.Mo)})`);
if (simB) console.log(`  model B (frequency-fitted delays: dm ${PB.dm} da ${PB.da} taus ${PB.taus}):  Mo-M ${rms((r) => r.MoB - r.M)} (${mx((r) => r.MoB - r.M)})   I-Mo ${rms((r) => r.I - r.MoB)} (${mx((r) => r.I - r.MoB)})`);
fs.writeFileSync(path.join(dir, "compare.json"), JSON.stringify({ MoB_M: simB ? [+rms((r) => r.MoB - r.M), +mx((r) => r.MoB - r.M)] : null, seed: plan.seed, resolved: plan.resolved, mirror: plan.mirror, IM: [+rms((r) => r.I - r.M), +mx((r) => r.I - r.M)], MoM: [+rms((r) => r.Mo - r.M), +mx((r) => r.Mo - r.M)], IMo: [+rms((r) => r.I - r.Mo), +mx((r) => r.I - r.Mo)] }));
