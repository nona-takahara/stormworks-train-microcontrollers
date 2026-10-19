#!/usr/bin/env node
// Compares the measured speed response of a sine-sweep program with the model, per segment:
// the component of v at the segment's frequency (amplitude, phase) from a least-squares fit on the
// last whole periods, against the same from simulate.mjs. Usage: node sweep.mjs K k B d c tau runIndex f1,f2,...
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readRuns } from "./fit.mjs";
import { simulate, PRESETS } from "./simulate.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const [K, k, B, d, c, tau, ri, fs_] = process.argv.slice(2).filter((a) => !a.endsWith('.csv') && !a.startsWith('--'));
const presetName = process.argv.includes('--vehicle') ? process.argv[process.argv.indexOf('--vehicle') + 1] : null;
const runs = readRuns(fs.readFileSync((process.argv.find((a) => a.endsWith(".csv")) ?? path.join(here, "../data/log.csv")), "utf8"));
const run = runs[Number(ri)];
const freqs = fs_.split(",").map(Number);
const sim = simulate(run, ...[K, k, B, d, c, tau].map(Number), Number(tau), PRESETS[presetName] ?? null);
const comp = (pts, f) => { // least squares: v - mean = a sin + b cos
    const n = pts.length, mean = pts.reduce((s, p) => s + p.v, 0) / n;
    let ss = 0, cc = 0, sc = 0, sv = 0, cv = 0;
    for (const p of pts) { const w = 2 * Math.PI * f * p.t / 60, s = Math.sin(w), co = Math.cos(w), y = p.v - mean; ss += s * s; cc += co * co; sc += s * co; sv += s * y; cv += co * y; }
    const det = ss * cc - sc * sc, a = (sv * cc - cv * sc) / det, b = (cv * ss - sv * sc) / det;
    return { amp: Math.hypot(a, b), phase: Math.atan2(b, a) };
};
console.log("f[Hz]  amp_meas  amp_model  ratio   phase_diff[deg]  (meas - model; negative = measured lags more)");
let segStart = run[0].t;
// the run is a sequence of segments; segment numbers come from the log's reason column, so rebuild boundaries from the log
const raw = fs.readFileSync((process.argv.find((a) => a.endsWith(".csv")) ?? path.join(here, "../data/log.csv")), "utf8").trim().split("\n").slice(1).map((l) => l.split(","));
const bySeg = new Map();
for (const r of raw) { const t = +r[2]; if (t >= run[0].t && t <= run[run.length - 1].t && +r[10] === 1) { const g = +r[11]; if (!bySeg.has(g)) bySeg.set(g, []); bySeg.get(g).push(t); } }
freqs.forEach((f, i) => {
    const ts = bySeg.get(i + 1); if (!ts) return;
    const [a0, a1] = [Math.min(...ts), Math.max(...ts)];
    const period = 60 / f, whole = Math.max(1, Math.floor((a1 - a0) / period) - 1) * period; // skip the first period (settling)
    const lo = a1 - whole;
    const idx = run.map((r, j) => ({ r, j })).filter(({ r }) => r.t >= lo && r.t <= a1);
    const meas = comp(idx.map(({ r }) => ({ t: r.t, v: r.v })), f), mod = comp(idx.map(({ r, j }) => ({ t: r.t, v: sim[j].v })), f);
    let dp = (meas.phase - mod.phase) * 180 / Math.PI; dp = ((dp + 540) % 360) - 180;
    console.log(`${String(f).padEnd(5)}  ${meas.amp.toFixed(4).padStart(8)}  ${mod.amp.toFixed(4).padStart(9)}  ${(meas.amp / mod.amp).toFixed(3).padStart(5)}   ${dp.toFixed(1).padStart(8)}`);
});
