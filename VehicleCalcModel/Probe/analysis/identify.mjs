#!/usr/bin/env node
// Fits K, k, B, c, tau (and the lag d, by scan) of the model in simulate.mjs by minimising the
// trajectory rms over the fit runs, then reports the error on the check runs (never used in the fit).
// Slip runs (slip flag on, or |motor| above --mmax-fit, default 0.56) are left out. Runs are split alternately
// (even -> fit, odd -> check) unless --fit / --check lists are given.
// Usage: node identify.mjs [--tau | --asym] [--vehicle mo1800|mo2000] [--mmax-fit 0.42]   (--asym: separate time constants while the motor drive rises / falls)
//  [--fit 0,2,3] [--check 7,9] [log.csv]
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readRuns } from "./fit.mjs";
import { simulate, errors, PRESETS } from "./simulate.mjs";

const args = process.argv.slice(2);
const list = (name) => (args.includes(name) ? args[args.indexOf(name) + 1].split(",").map(Number) : null);
const asym = args.includes("--asym");
const useTau = args.includes("--tau") || asym;
const logPath = args.find((a) => a.endsWith(".csv")) ?? path.join(path.dirname(fileURLToPath(import.meta.url)), "../data/log.csv");
const runs = readRuns(fs.readFileSync(logPath, "utf8"));
const mfit = Number(args.includes("--mmax-fit") ? args[args.indexOf("--mmax-fit") + 1] : 0.56);
const usable = runs.map((r, i) => i).filter((i) => runs[i].every((x) => x.slip === 0) && !runs[i].some((x) => Math.abs(x.motor) > mfit));
const fitIdx = list("--fit") ?? usable.filter((_, j) => j % 2 === 0);
const chkIdx = list("--check") ?? usable.filter((_, j) => j % 2 === 1);

const preset = args.includes("--vehicle") ? PRESETS[args[args.indexOf("--vehicle") + 1]] : null;
const cost = (p, set) => set.reduce((s, i) => { const e = errors(runs[i], simulate(runs[i], ...p, preset)); return s + e.rms * e.rms; }, 0) / set.length;
// p = [K, k, B, d, c, tau]
let best = null;
for (let d = 0; d <= 6; d++) {
    let p = [36, 0.107, 2.08, d, 0.95, useTau ? 1 : 0, useTau ? 1 : 0], step = [1, 0.01, 0.1, 0, 0.05, useTau ? 0.5 : 0, useTau ? 0.5 : 0];
    for (let iter = 0; iter < 80; iter++) {
        let improved = false;
        for (const j of (asym ? [0, 1, 2, 4, 5, 6] : [0, 1, 2, 4, 5])) for (const s of [step[j], -step[j]]) {
            if (s === 0) continue;
            const q = [...p]; q[j] += s; if (j >= 5 && q[j] < 0) continue;
            if (!asym) q[6] = q[5];
            if (cost(q, fitIdx) < cost(p, fitIdx)) { p = q; improved = true; }
        }
        if (!improved) { step = step.map((x) => x / 2); if (step[0] < 1e-3) break; }
    }
    const c = cost(p, fitIdx);
    if (!best || c < best.c) best = { p, c };
}
const [K, k, B, d, c, tau, tauDown] = best.p;
console.log(`fit: K=${K.toFixed(2)} k=${k.toFixed(4)} B=${B.toFixed(3)} d=${d} c=${c.toFixed(3)} tau(rising)=${tau.toFixed(2)} tau(falling)=${tauDown.toFixed(2)} ticks`);
const summary = (name, idx) => {
    const errs = idx.map((i) => errors(runs[i], simulate(runs[i], ...best.p, preset)));
    const mx = Math.max(...errs.map((e) => e.max)), rms = Math.sqrt(errs.reduce((s, e) => s + e.rms * e.rms, 0) / errs.length);
    console.log(`${name}: ${idx.length} runs, worst max ${mx.toFixed(3)} m/s (run ${idx[errs.findIndex((e) => e.max === mx)]}), mean rms ${rms.toFixed(3)} m/s`);
};
summary("fit  ", fitIdx);
summary("check", chkIdx);
