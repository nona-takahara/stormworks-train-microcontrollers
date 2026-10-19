#!/usr/bin/env node
// Integrates  dv/dt = f - k*v - B*brake(t-d)*v,   f' = (K*motor(t-d)*(1 - c*brake(t-d)) - f)/tau   per tick (tau while f rises, tauDown while it falls);
// (tau = 0: f follows at once, the plain delayed model) from each run's
// first sample, with the recorded inputs, and reports the error against the
// measured speeds. Used to judge a parameter set on runs it was not fitted on.
// Usage: node simulate.mjs K k B d [c [tau]] [log.csv] [--runs 3,5] [--vehicle mo1800|mo2000]
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readRuns } from "./fit.mjs";

// Vehicle shapes measured on the test line (brake effectiveness curve with its dead zone, the drive factor
// under the brake, the drive saturation). Used instead of the plain B and c when given.
const interp = (tbl, x) => { for (let i = 1; i < tbl.length; i++) if (x <= tbl[i][0]) { const [x0, y0] = tbl[i - 1], [x1, y1] = tbl[i]; return y0 + (y1 - y0) * (x - x0) / (x1 - x0); } return tbl.at(-1)[1]; };
export const PRESETS = {
    mo2000: { brakeRate: (b) => (b < 0.0113 ? 0 : 2.0 * b + 0.18 * b * b), driveFactor: (b) => 1 - 0.947 * b, netMax: Infinity },
    mo1800: { brakeRate: (b) => (b < 0.0113 ? 0 : 1.5 * b + 0.43 * b * b),
        driveFactor: (b) => interp([[0, 1], [0.1, 0.94], [0.3, 0.75], [0.6, 0.45], [0.9, 0.11], [1.0, 0.0]], b), netMax: 10.7 }, // net acceleration limit [m/s^2]
};
export function simulate(run, K, k, B, d, c = 0, tau = 0, tauDown = tau, preset = null) {
    // the vehicle itself saturates its inputs: brake 0..1 (verified), motor -1..+1
    const lim = { motor: [-1, 1], brake: [0, 1] };
    const sat = (key, u) => Math.min(lim[key][1], Math.max(lim[key][0], u));
    // input at tick `tt`: the last sample at or before it (0 before the run starts). tt only grows.
    let ptr = -1;
    const input = (key, tt) => {
        while (ptr + 1 < run.length && run[ptr + 1].t <= tt) ptr++;
        return ptr < 0 ? 0 : sat(key, run[ptr][key]);
    };
    let v = run[0].v, f = 0;
    const out = [{ t: run[0].t, v }];
    for (let t = run[0].t; t < run[run.length - 1].t; t++) {
        const m = input("motor", t - d), b = ptr < 0 ? 0 : sat("brake", run[ptr].brake); // same tick for both
        const drive = preset ? K * m * preset.driveFactor(b) : K * m * (1 - c * b);
        const tz = drive >= f ? tau : tauDown; // one time constant while the drive rises, another while it falls
        f = tz > 0 ? f + (drive - f) / (1 + tz) : drive;
        const net = f - k * v - (preset ? preset.brakeRate(b) : B * b) * v;
        // the 1800 limits the net acceleration in the direction of the drive (not the braking): +-netMax
        const capped = preset && m !== 0 && net * m > 0 ? Math.sign(m) * Math.min(preset.netMax, Math.abs(net)) : net;
        v += capped / 60;
        if (t + 1 === run[out.length].t) out.push({ t: t + 1, v });
    }
    return out;
}

export function errors(run, sim) {
    let max = 0, sq = 0;
    sim.forEach((s, i) => { const e = s.v - run[i].v; max = Math.max(max, Math.abs(e)); sq += e * e; });
    return { max, rms: Math.sqrt(sq / sim.length) };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    const args = process.argv.slice(2);
    const [K, k, B, d, c = 0, tau = 0, tauDown = tau] = args.slice(0, 7).filter((a) => !a.endsWith(".csv") && !a.startsWith("--")).map(Number);
    const logPath = args.find((a) => a.endsWith(".csv")) ?? path.join(path.dirname(fileURLToPath(import.meta.url)), "../data/log.csv");
    const only = args.includes("--runs") ? args[args.indexOf("--runs") + 1].split(",").map(Number) : null;
    const runs = readRuns(fs.readFileSync(logPath, "utf8"));
    runs.forEach((run, i) => {
        if (only && !only.includes(i)) return;
        const e = errors(run, simulate(run, K, k, B, d, c, tau, tauDown, args.includes("--vehicle") ? PRESETS[args[args.indexOf("--vehicle") + 1]] : null));
        console.log(`run ${i} motor ${run[0].motor} brake ${run[0].brake} v0 ${run[0].v.toFixed(2)}: max err ${e.max.toFixed(3)} m/s, rms ${e.rms.toFixed(3)} m/s`);
    });
}
