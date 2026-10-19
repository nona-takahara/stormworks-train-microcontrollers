#!/usr/bin/env node
// Frequency response of a sine-sweep run: per segment, the complex ratio of the speed's component
// at f to the motor's component at f, with the plant's integrator (jw + k)/K taken out:
//   P(f) = (V/U) * (jw + k) / K       ~ exp(-jw*d) / (1 + jw*tau)  for the model
// Prints |P| and the equivalent pure delay -arg(P)/w in ticks. Usage: node freqresp.mjs K k runIndex f1,f2,...
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readRuns } from "./fit.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const [K, k, ri, fl] = process.argv.slice(2);
const runs = readRuns(fs.readFileSync((process.argv.find((a) => a.endsWith(".csv")) ?? path.join(here, "../data/log.csv")), "utf8"));
const run = runs[Number(ri)];
const raw = fs.readFileSync((process.argv.find((a) => a.endsWith(".csv")) ?? path.join(here, "../data/log.csv")), "utf8").trim().split("\n").slice(1).map((l) => l.split(","));
const segs = new Map();
for (const r of raw) { const t = +r[2]; if (t >= run[0].t && t <= run[run.length - 1].t && +r[10] === 1) { const g = +r[11]; if (!segs.has(g)) segs.set(g, []); segs.get(g).push(t); } }
const proj = (pts, f) => { // component at f: v ~ mean + a sin + b cos  ->  complex a - jb... use Re/Im of sum y*exp(-jwt)
    const n = pts.length, mean = pts.reduce((s, p) => s + p.y, 0) / n;
    let re = 0, im = 0;
    for (const p of pts) { const w = 2 * Math.PI * f * p.t / 60; re += (p.y - mean) * Math.cos(w); im -= (p.y - mean) * Math.sin(w); }
    return { re: 2 * re / n, im: 2 * im / n };
};
console.log("f[Hz]  |P|     delay_equiv[ticks]");
fl.split(",").map(Number).forEach((f, i) => {
    const ts = segs.get(i + 1); if (!ts) return;
    const a1 = Math.max(...ts), period = 60 / f, whole = Math.max(1, Math.floor((a1 - Math.min(...ts)) / period) - 1) * period;
    const sel = run.filter((r) => r.t >= a1 - whole && r.t <= a1);
    const V = proj(sel.map((r) => ({ t: r.t, y: r.v })), f), U = proj(sel.map((r) => ({ t: r.t, y: r.motor })), f);
    const w = 2 * Math.PI * f / 60 * 60; // rad/s  (t is in ticks, f in Hz)
    // R = V/U (complex)
    const den = U.re * U.re + U.im * U.im, Rr = (V.re * U.re + V.im * U.im) / den, Ri = (V.im * U.re - V.re * U.im) / den;
    // P = R * (jw + k) / K
    const Pr = (Rr * Number(k) - Ri * w) / Number(K), Pi = (Rr * w + Ri * Number(k)) / Number(K);
    const mag = Math.hypot(Pr, Pi), arg = Math.atan2(Pi, Pr);
    console.log(`${String(f).padEnd(5)}  ${mag.toFixed(3)}   ${(-arg / (2 * Math.PI * f) * 60).toFixed(2)}`);
});
