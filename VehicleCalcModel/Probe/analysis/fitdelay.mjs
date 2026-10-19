#!/usr/bin/env node
// Two models of one vehicle: A, the delays fitted from the step responses (the common procedure), and B, the delays (d_m, d_a, tau_s)
// chosen to match the measured frequency response of the sweeps. Everything else (Sc, slope, drive curve, brake) is the same.
// Prints the cost of each candidate in the frequency response and the cost it puts on the step-type data (components, verification).
// Usage: node fitdelay.mjs <vehicle> [--fmax 20] [--write]    (reads data/params_<v>.json, scenarios/<v>_sweep_*, scenarios/<v>_verify_*, log_<v>.csv)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readRuns } from "./fit.mjs";
import { simulate2 } from "./axle2.mjs";
import { responses } from "./spectral.mjs";

const here = path.dirname(fileURLToPath(import.meta.url)), data = path.join(here, "..", "data");
const veh = process.argv[2], fmax = Number(process.argv.includes("--fmax") ? process.argv[process.argv.indexOf("--fmax") + 1] : 20);
const P0 = JSON.parse(fs.readFileSync(path.join(data, `params_${veh}.json`), "utf8"));
const dirs = (kind) => fs.readdirSync(path.join(data, "scenarios")).filter((d) => d.startsWith(`${veh}_${kind}_`)).map((d) => path.join(data, "scenarios", d));
const longest = (txt) => readRuns(txt).reduce((a, r) => (r.length > a.length ? r : a), []);
const sweeps = dirs("sweep").map((d) => ({ run: longest(fs.readFileSync(path.join(d, "rows.csv"), "utf8")), freqs: JSON.parse(fs.readFileSync(path.join(d, "sweep.json"), "utf8")).freqs }));
const verifs = dirs("verify").map((d) => longest(fs.readFileSync(path.join(d, "rows.csv"), "utf8")));
const comps = readRuns(fs.readFileSync(path.join(data, `log_${veh}.csv`), "utf8")).filter((r) => r.length > 12 && Math.max(...r.map((x) => x.seg)) <= 3 && !r.some((x) => x.slip || Math.abs(x.motor) > 0.56));
const rmsV = (run, P) => { const sim = simulate2(run, P), sg = 1; return Math.sqrt(sim.reduce((s, x, i) => s + (x.v - run[i].v) ** 2, 0) / sim.length); };
const meanRms = (runs, P) => Math.sqrt(runs.reduce((s, r) => s + rmsV(r, P) ** 2, 0) / runs.length);
const freqCost = (P, fm) => {
    let c = 0, n = 0;
    for (const { run, freqs } of sweeps) for (const r of responses(run, freqs, P)) {
        if (r.f > fm) continue;
        const lg = Math.log(Math.hypot(...r.g) / Math.hypot(...r.gm)), dp = Math.atan2(r.g[1], r.g[0]) - Math.atan2(r.gm[1], r.gm[0]), d = Math.atan2(Math.sin(dp), Math.cos(dp));
        c += lg * lg + d * d; n++;
    }
    return Math.sqrt(c / n);
};
const cands = [];
for (let dm = 1; dm <= 6; dm++) for (let da = 0; da <= 4; da++) for (let ts = 0; ts <= 1.001; ts += 0.1) cands.push({ dm, da, taus: +ts.toFixed(2) });
const scored = cands.map((c) => ({ ...c, cost: freqCost({ ...P0, ...c }, fmax) })).sort((a, b) => a.cost - b.cost);
const show = (label, c) => {
    const P = { ...P0, ...c };
    console.log(`${label.padEnd(22)} dm ${c.dm} da ${c.da} taus ${Number(c.taus).toFixed(2)}  frequency cost ${freqCost(P, fmax).toFixed(3)} (<=${fmax} Hz), ${freqCost(P, 8).toFixed(3)} (<=8 Hz)   step data: components rms ${meanRms(comps, P).toFixed(3)}, verification rms ${meanRms(verifs, P).toFixed(3)}`);
};
show("A (step-fitted)", { dm: P0.dm, da: P0.da, taus: P0.taus });
const best = scored[0]; show("B (frequency-fitted)", best);
console.log("next candidates:"); scored.slice(1, 6).forEach((c, i) => show(`  #${i + 2}`, c));
if (process.argv.includes("--write")) { fs.writeFileSync(path.join(data, `params_${veh}_freq.json`), JSON.stringify({ ...P0, dm: best.dm, da: best.da, taus: best.taus }, null, 1)); console.log("written params_" + veh + "_freq.json"); }
