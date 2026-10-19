#!/usr/bin/env node
// One model and one fitting procedure for every vehicle: the axle-speed model.
//
//   s  = circumference-speed excess of the axle over the vehicle  (m/s, signed)
//   s' = (Sc*o_m*F(o_b) - s)/(1+taus)                (the command reaches s after a delay d [ticks])
//   a_drive = clamp(slope*s, +-muMax)                (a static drive curve; slip runs are left out)
//   dv/dt   = a_drive - k*v - g(o_b)*v
//   F(b) = 1 - c1*b - c2*b^2   (the drive left under the brake)
//   g(b) = 0 for b < dz, else B1*b + B2*b^2   (brake effect with its dead zone; dz = 0.0113 for both vehicles)
//
// The same code fits a vehicle from its log; only the parameters differ.
// Usage: node axle.mjs <log.csv> [--rps-weight 0.3] [--mmax-fit 0.56] [--init Sc,taus,slope,muMax,k,B1,B2,c1,c2]
//        node axle.mjs <log.csv> --params Sc,taus,d,slope,muMax,k,B1,B2,c1,c2 --runs 3,5   (evaluate, no fit)
import fs from "node:fs";
import { readRuns } from "./fit.mjs";

export const NAMES = ["Sc", "taus", "slope", "muMax", "k", "B1", "B2", "c1", "c2"];
const DZ = 0.0113;

export function simulateAxle(run, P, d) {
    const [Sc, taus, slope, muMax, k, B1, B2, c1, c2] = P;
    let ptrM = -1, ptrB = -1;
    const get = (key, ptr, tt) => { while (ptr + 1 < run.length && run[ptr + 1].t <= tt) ptr++; return ptr; };
    let v = run[0].v, s = 0;
    const out = [{ t: run[0].t, v, s }];
    const sat = (x, a) => Math.min(a, Math.max(-a, x));
    for (let t = run[0].t; t < run[run.length - 1].t; t++) {
        ptrM = get("motor", ptrM, t - d); ptrB = get("brake", ptrB, t - d);
        const m = ptrM < 0 ? 0 : sat(run[ptrM].motor, 1), b = ptrB < 0 ? 0 : sat(Math.abs(run[ptrB].brake), 1);
        const F = Math.max(0, 1 - c1 * b - c2 * b * b);
        s += (Sc * m * F - s) / (1 + taus);
        const drive = sat(slope * s, muMax);
        const g = b < DZ ? 0 : B1 * b + B2 * b * b;
        v += (drive - k * v - g * v) / 60;
        if (t + 1 === run[out.length].t) out.push({ t: t + 1, v, s });
    }
    return out;
}

export function runError(run, P, d, rpsWeight = 0) {
    const sim = simulateAxle(run, P, d);
    let sq = 0, mx = 0, sqs = 0, ns = 0;
    sim.forEach((x, i) => {
        const e = x.v - run[i].v; sq += e * e; mx = Math.max(mx, Math.abs(e));
        if (rpsWeight > 0 && run[i].rps !== 0) { const sm = Math.PI * (run[i].rps - 0.3183 * run[i].v); const es = x.s - sm; sqs += es * es; ns++; }
    });
    const rms = Math.sqrt(sq / sim.length);
    return { rms, max: mx, srms: ns ? Math.sqrt(sqs / ns) : 0, cost: rms * rms + rpsWeight * (ns ? sqs / ns : 0) };
}

// Stage 1 and 2: components that a single kind of run measures directly (the same code for every vehicle).
// Stretches of consecutive samples with constant inputs: the decay rate of |v| is  k + g(o_b).
function stretches(runs, test, minSamples, skipTicks) {
    const out = [];
    for (const run of runs) {
        let cur = [];
        const flush = () => { if (cur.length >= minSamples) out.push(cur); cur = []; };
        for (const r of run) {
            if (test(r) && (cur.length === 0 || (r.motor === cur[0].motor && Math.abs(r.brake - cur[0].brake) < 1e-9))) cur.push(r); else { flush(); if (test(r)) cur = [r]; }
        }
        flush();
    }
    return out.map((st) => st.filter((r) => r.t - st[0].t >= skipTicks));
}
function decayRate(st) {
    const pts = st.filter((r) => Math.abs(r.v) > 2.5);
    if (pts.length < 8) return null;
    const xs = pts.map((r) => (r.t - pts[0].t) / 60), ys = pts.map((r) => Math.log(Math.abs(r.v)));
    const mx = xs.reduce((a, b) => a + b) / xs.length, my = ys.reduce((a, b) => a + b) / ys.length;
    return -xs.reduce((a, x, i) => a + (x - mx) * (ys[i] - my), 0) / xs.reduce((a, x) => a + (x - mx) ** 2, 0);
}
export function estimateK(runs) {
    const rates = stretches(runs, (r) => r.motor === 0 && r.brake === 0 && Math.abs(r.v) > 2.5, 30, 24).map(decayRate).filter((x) => x !== null && x > 0.05 && x < 0.2);
    return { k: rates.reduce((a, b) => a + b, 0) / rates.length, n: rates.length };
}
export function estimateBrake(runs, k) {
    const byLevel = new Map();
    for (const st of stretches(runs, (r) => r.motor === 0 && r.brake >= 0.0125 && r.brake <= 1.0 && Math.abs(r.v) > 2.5, 30, 24)) {
        const rate = decayRate(st); if (rate === null) continue;
        const lv = Math.round(st[0].brake * 1000) / 1000;
        if (!byLevel.has(lv)) byLevel.set(lv, []);
        byLevel.get(lv).push(rate - k);
    }
    // least squares of g = B1*b + B2*b^2 over the levels with relative-error weights (1/g^2): every level counts alike,
    // including the small levels (0.0125 to 0.2) at which a stop is mostly made
    let a11 = 0, a12 = 0, a22 = 0, r1 = 0, r2 = 0;
    for (const [b, gs] of byLevel) { const g = gs.reduce((a, x) => a + x, 0) / gs.length; if (g <= 0) continue; const w = 1 / (g * g); a11 += w * b * b; a12 += w * b ** 3; a22 += w * b ** 4; r1 += w * b * g; r2 += w * b * b * g; }
    const det = a11 * a22 - a12 * a12;
    return { B1: (r1 * a22 - r2 * a12) / det, B2: (a11 * r2 - a12 * r1) / det, levels: byLevel.size };
}

const BOUNDS = { Sc: [5, 40], taus: [0, 15], slope: [0.5, 4], muMax: [3, 60], k: [0.05, 0.2], B1: [0.5, 4], B2: [-1, 2], c1: [0, 2], c2: [-1, 1] };
const STEP = { Sc: 0.5, taus: 0.5, slope: 0.05, muMax: 1, k: 0.005, B1: 0.1, B2: 0.1, c1: 0.05, c2: 0.05 };

const RANGE = { Sc: [10, 25], taus: [0.5, 10], slope: [1.5, 3], muMax: [8, 40], k: [0.1, 0.12], B1: [1, 2.5], B2: [0, 1], c1: [0.2, 1.2], c2: [-0.3, 0.5] };
// A seeded generator, so the same log always gives the same fit.
function rng(seed) { let x = seed >>> 0; return () => { x = (x * 1664525 + 1013904223) >>> 0; return x / 4294967296; }; }

export function fit(runs, idx, init, rpsWeight, restarts = 6, fixed = {}) {
    let best = null;
    const rand = rng(12345);
    const inits = [init, ...Array.from({ length: restarts }, () => NAMES.map((n) => RANGE[n][0] + rand() * (RANGE[n][1] - RANGE[n][0])))];
    for (const start of inits) for (let d = 2; d <= 5; d++) {
        let P = start.map((x, j) => (NAMES[j] in fixed ? fixed[NAMES[j]] : x)), step = NAMES.map((n) => (n in fixed ? 0 : STEP[n]));
        const cost = (Q) => idx.reduce((a, i) => a + runError(runs[i], Q, d, rpsWeight).cost, 0) / idx.length;
        let c0 = cost(P);
        for (let it = 0; it < 60; it++) {
            let improved = false;
            for (let j = 0; j < NAMES.length; j++) if (!(NAMES[j] in fixed)) for (const sgn of [1, -1]) {
                const Q = [...P]; Q[j] = Math.min(BOUNDS[NAMES[j]][1], Math.max(BOUNDS[NAMES[j]][0], Q[j] + sgn * step[j]));
                const c = cost(Q);
                if (c < c0 - 1e-12) { P = Q; c0 = c; improved = true; }
            }
            if (!improved) { step = step.map((x) => x / 2); if (step[0] < 0.01) break; }
        }
        if (!best || c0 < best.cost) best = { P, d, cost: c0 };
    }
    return best;
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
    const args = process.argv.slice(2);
    const opt = (n, dflt) => (args.includes(n) ? args[args.indexOf(n) + 1] : dflt);
    const logPath = args.find((a) => a.endsWith(".csv"));
    const runs = readRuns(fs.readFileSync(logPath, "utf8"));
    const mfit = Number(opt("--mmax-fit", 0.56)), rpsW = Number(opt("--rps-weight", 0.3));
    const usable = runs.map((r, i) => i).filter((i) => runs[i].every((x) => x.slip === 0) && !runs[i].some((x) => Math.abs(x.motor) > mfit) && runs[i].length > 12);
    const fitIdx = usable.filter((_, j) => j % 2 === 0), chkIdx = usable.filter((_, j) => j % 2 === 1);
    let P, d;
    if (args.includes("--params")) { const q = opt("--params").split(",").map(Number); d = q[2]; P = [q[0], q[1], ...q.slice(3)]; }
    else {
        const init = opt("--init", "16,3,2.1,20,0.109,1.8,0.2,0.8,0.1").split(",").map(Number);
        // stage 1 and 2 use all runs of the log (they are measurements of single components); stage 3 uses the fit runs only
        const kEst = estimateK(runs), brk = estimateBrake(runs, kEst.k);
        console.log(`stage 1: k = ${kEst.k.toFixed(4)} 1/s (${kEst.n} coast stretches)   stage 2: B1 = ${brk.B1.toFixed(3)}, B2 = ${brk.B2.toFixed(3)} (${brk.levels} brake levels)`);
        const b = fit(runs, fitIdx, init, rpsW, 6, { k: kEst.k, B1: brk.B1, B2: brk.B2 }); P = b.P; d = b.d;
        console.log(`stage 3 (${fitIdx.length} runs, rps weight ${rpsW}): d=${d}  ` + NAMES.map((n, i) => `${n}=${P[i].toFixed(4)}`).join(" "));
    }
    const summarize = (name, set) => {
        const es = set.map((i) => ({ i, ...runError(runs[i], P, d, rpsW) }));
        const long = es.filter((e) => runs[e.i].length > 300);
        const mean = (a) => (a.length ? Math.sqrt(a.reduce((s, e) => s + e.rms * e.rms, 0) / a.length) : NaN);
        const worst = es.reduce((a, e) => (e.max > a.max ? e : a), { max: 0 });
        console.log(`${name}: ${set.length} runs, mean rms ${mean(es).toFixed(3)} m/s, worst max ${worst.max.toFixed(3)} (run ${worst.i}); ` +
            `long runs (${long.length}): mean rms ${mean(long).toFixed(3)}, worst max ${Math.max(0, ...long.map((e) => e.max)).toFixed(3)}; s rms ${(es.reduce((a, e) => a + e.srms, 0) / es.length).toFixed(2)} m/s`);
        return es;
    };
    summarize("fit  ", fitIdx);
    const es = summarize("check", chkIdx);
    if (args.includes("--runs")) for (const i of opt("--runs").split(",").map(Number)) { const e = runError(runs[i], P, d, rpsW); console.log(`run ${i} motor ${runs[i][0].motor} brake ${runs[i][0].brake}: max ${e.max.toFixed(3)} rms ${e.rms.toFixed(3)} s-rms ${e.srms.toFixed(2)}`); }
    if (args.includes("--worst")) for (const e of es.sort((a, b) => b.max - a.max).slice(0, 8)) console.log(`  worst: run ${e.i} motor ${runs[e.i][0].motor} brake ${runs[e.i][0].brake} len ${runs[e.i].length}: max ${e.max.toFixed(3)} rms ${e.rms.toFixed(3)}`);
}
