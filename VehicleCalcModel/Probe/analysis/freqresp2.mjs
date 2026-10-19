#!/usr/bin/env node
// Frequency response of a sine-sweep run (the folder written by pipeline.py sweep), measured and of the common model:
//   G(f) = V(f)/U(f)   the speed's component at f over the motor command's component at f (the plant with its integrator)
//   P(f) = G (j w + k)/Kd   with the integrator taken out: ~ exp(-j w d)/(1 + j w tau_s) for the model; Kd = slope * Sc
// The model is simulate2 driven by the logged motor and brake, so it sees the same input as the vehicle.
// Per sine segment (segment 2 and on; segment 1 brings the speed up), over the whole periods after the first one.
// Reports the agreement as the highest frequency up to which |G| agrees within 10% and the phase within 10 degrees.
// Usage: node freqresp2.mjs <sweep folder>
import fs from "node:fs";
import path from "node:path";
import { readRuns } from "./fit.mjs";
import { simulate2 } from "./axle2.mjs";
import { comp, div } from "./spectral.mjs";

const dir = process.argv[2];
const plan = JSON.parse(fs.readFileSync(path.join(dir, "sweep.json"), "utf8")), P = JSON.parse(fs.readFileSync(path.join(dir, "params.json"), "utf8"));
const run = readRuns(fs.readFileSync(path.join(dir, "rows.csv"), "utf8")).reduce((a, r) => (r.length > a.length ? r : a), []);
if (!run.length) { console.log("  REFUSED: no RUN samples"); process.exit(1); }
const nseg = Math.max(...run.map((x) => x.seg));
if (nseg !== plan.segments) { console.log(`  REFUSED: the probe ran ${nseg} of ${plan.segments} segments`); process.exit(1); }
const sim = simulate2(run, P), Kd = P.slope * P.Sc, sgn = Math.sign(run.reduce((s, x) => s + x.v, 0)) || 1;
const rows = []; let agree = 0, agreeing = true, prevD = [null, null];
console.log(`  ${"f [Hz]".padEnd(8)}${"|G| meas".padEnd(10)}${"|G| model".padEnd(11)}${"ratio".padEnd(8)}${"phase meas".padEnd(12)}${"phase model".padEnd(13)}${"diff".padEnd(8)}${"delay meas [tick]".padEnd(19)}delay model [tick]   (G = speed / motor; delay = equivalent pure delay of P)`);
plan.freqs.forEach((f, i) => {
    const w = run.filter((x) => x.seg === i + 2); if (w.length < 8) return;
    const T = 60 / f, t0 = w[0].t + T, nper = Math.floor((w[w.length - 1].t - t0) / T); if (nper < 1) return;
    const idx = w.map((x, j) => j).filter((j) => w[j].t >= t0 && w[j].t < t0 + nper * T);
    const ts = idx.map((j) => w[j].t), u = comp(ts, idx.map((j) => sgn * w[j].motor), f), vm = comp(ts, idx.map((j) => sgn * w[j].v), f);
    const k0 = run.indexOf(w[0]), vs = comp(ts, idx.map((j) => sgn * sim[k0 + j].v), f);
    const g = div(vm, u), gm = div(vs, u), wr = 2 * Math.PI * f / 60;  // wr in rad/tick
    const mag = (z) => Math.hypot(z[0], z[1]), ph = (z) => Math.atan2(z[1], z[0]) * 180 / Math.PI;
    // the equivalent delay of P, with the phase unwrapped toward the delay of the previous (lower) frequency
    const dly = (z, slot) => {
        const p = [z[0] * P.k / 60 / Kd - z[1] * wr / Kd, z[1] * P.k / 60 / Kd + z[0] * wr / Kd], a = -Math.atan2(p[1], p[0]) / wr;
        const n = prevD[slot] === null ? 0 : Math.round((prevD[slot] - a) * wr / (2 * Math.PI)), d = a + n * 2 * Math.PI / wr; prevD[slot] = d; return d;
    };
    let dph = ph(g) - ph(gm); dph = ((dph + 540) % 360) - 180;
    const ok = Math.abs(mag(g) / mag(gm) - 1) <= 0.1 && Math.abs(dph) <= 10;
    if (agreeing && ok) agree = f; else agreeing = false;
    const dd = dly(g, 0), ddm = dly(gm, 1);
    rows.push({ f, G: mag(g), Gm: mag(gm), ph: ph(g), phm: ph(gm), dph, d: dd, dm: ddm, periods: nper });
    console.log(`  ${String(f).padEnd(8)}${mag(g).toFixed(3).padEnd(10)}${mag(gm).toFixed(3).padEnd(11)}${(mag(g) / mag(gm)).toFixed(3).padEnd(8)}${ph(g).toFixed(1).padEnd(12)}${ph(gm).toFixed(1).padEnd(13)}${dph.toFixed(1).padEnd(8)}${dd.toFixed(2).padEnd(19)}${ddm.toFixed(2)}  (${nper} periods)`);
});
console.log(`  the model agrees with the measurement (|G| within 10%, phase within 10 deg) up to ${agree || "none of the"} Hz`);
fs.writeFileSync(path.join(dir, "freqresp.json"), JSON.stringify({ agree_to_hz: agree, rows }));
