#!/usr/bin/env node
// The axle-speed model, identified in stages from each component's own measurements (same code for every vehicle).
//
//   s  = pi*(RPS - 0.3183*v)  [m/s]  measured circumference-speed excess of the axle (input channel 22)
//   s' = (Sc*o_m*F(o_b) - s)/(1+taus), the command reaching s after dm ticks; o_b acts after db ticks
//   the drive follows s after da ticks:  a_drive = f(s(t - da))
//   a_drive = min(slope*|s|*(1 - gamma*v^2), muMax)*sign(s)   (static drive curve; the slope falls with speed, about 5% (2000) to 9% (1800) at 30 m/s)
//   dv/dt   = a_drive - k*v - g(o_b)*v
//   F(b) = 1 - c1*b - (1-c1)*b^2                      (F(0) = 1 and F(1) = 0, as measured)
//   g(b) = 0 for b < 0.0113, else B1*b + B2*b^2
//
// Stages (a measured quantity fixes its parameters; velocity is a prediction that is only refined within +-5%):
//   1  k              coast stretches (input 0)
//   2  B1, B2         brake stretches (motor 0), relative-error weights
//   3a Sc, taus, dm   s(t) against the command, motor-only windows
//   3a' da            the delay between the measured s and the drive (dv/dt + k v), all motor-only samples
//   3b slope, muMax   drive (dv/dt + k v) against the measured s, samples below 12 m/s; gamma from the samples above 12 m/s
//                     (the high-speed cruise: the first run-curve programme of the log is used for gamma only and left out of the validation)
//   3c c1             drive left under the brake, simultaneous-input windows
//   3d db             brake-path delay, brake runs
//   4  refinement     +-5% on Sc, slope, k, B1, B2, c1, gamma (velocity error on the fit runs and on the cruise run that fixed gamma)
// Fit runs: component runs (at most 3 programme segments). Validation: runs with 4 or more segments (scenarios, sweeps, run curves).
// A run whose speed exceeds 36 m/s is left out of both.
// Usage: node axle2.mjs <log.csv> [--worst]
import fs from "node:fs";
import { readRuns } from "./fit.mjs";
import { estimateK, estimateBrake } from "./axle.mjs";

const DZ = 0.0113, R = Math.PI;
// RHO = |RPS| / |v| while coasting (nominal 1/(2*pi*0.5) = 0.3183). It is estimated for each vehicle: an error of 0.0005 puts 3% into s at 30 m/s.
let RHO = 0.3183;
export function estimateRho(runs) {
    const xs = [];
    for (const run of runs) { let last = -1e9; for (const x of run) { if (x.motor !== 0 || x.brake !== 0) last = x.t; else if (x.t - last >= 60 && Math.abs(x.v) > 2 && x.rps !== 0) xs.push(Math.abs(x.rps) / Math.abs(x.v)); } }
    xs.sort((a, b) => a - b); return xs.length >= 20 ? xs[xs.length >> 1] : 0.3183;
}
const sMeas = (x) => R * (x.rps - RHO * x.v);
const sat = (x, a) => Math.min(a, Math.max(-a, x));
// the drive slope falls above the knee speed vk:  1 - gamma*(|v| - vk)^PW
const PW = Number(process.env.DROP_PW ?? 1);
const GMAX = { 1: 0.03, 1.5: 0.003, 2: 6e-4 }[PW];
export const drop = (v, g, vk) => 1 - g * Math.max(0, Math.abs(v) - vk) ** PW;

export function simulate2(run, P) {
    let pm = -1, pb = -1;
    const adv = (p, tt) => { while (p + 1 < run.length && run[p + 1].t <= tt) p++; return p; };
    let v = run[0].v, s = 0;
    const sh = [];
    const out = [{ t: run[0].t, v, s }];
    for (let t = run[0].t; t < run[run.length - 1].t; t++) {
        pm = adv(pm, t - P.dm); pb = adv(pb, t - P.db);
        const m = pm < 0 ? 0 : sat(run[pm].motor, 1), b = pb < 0 ? 0 : sat(Math.abs(run[pb].brake), 1);
        const F = Math.max(0, 1 - P.c1 * b - (1 - P.c1) * b * b);
        s += (P.Sc * m * F - s) / (1 + P.taus);
        sh.push(s);
        const sd = sh.length > P.da ? sh[sh.length - 1 - P.da] : 0;
        const drive = sat(P.slope * sd * drop(v, P.gamma, P.vk), P.muMax);
        const g = b < DZ ? 0 : P.B1 * b + P.B2 * b * b;
        v += (drive - P.k * v - g * v) / 60;
        if (t + 1 === run[out.length].t) out.push({ t: t + 1, v, s });
    }
    return out;
}
// The maximum error leaves out the hard stop (brake >= 0.9): there the speed falls at about 60 m/s^2, so one tick of timing is 1 m/s.
// The rms includes everything. The same rule for every vehicle.
const err = (run, P) => { const sim = simulate2(run, P); let sq = 0, mx = 0; sim.forEach((x, i) => { const e = x.v - run[i].v; sq += e * e; if (Math.abs(run[i].brake) < 0.9) mx = Math.max(mx, Math.abs(e)); }); return { rms: Math.sqrt(sq / sim.length), max: mx }; };

// ---------- stage 3a: s(t) against the command (windows of programme segment 1 with no brake) ----------
function motorWindows(runs) {
    const out = [];
    for (const run of runs) {
        const w = run.filter((x) => x.seg === 1 && x.brake === 0 && x.rps !== 0);
        if (w.length > 12 && Math.abs(w[0].v) < 1) out.push(w);   // from rest, so that s starts at 0
    }
    return out;
}
function fitSChain(runs) {
    const wins = motorWindows(runs); let best = null;
    for (let dm = 2; dm <= 6; dm++) {
        let Sc = 15, taus = 3, stepS = 1, stepT = 1;
        const cost = (Sc, taus) => {
            let c = 0, n = 0;
            for (const w of wins) {
                let s = 0, p = -1;
                const t0 = w[0].t;
                for (let t = t0; t <= w.at(-1).t; t++) {
                    while (p + 1 < w.length && w[p + 1].t <= t - dm) p++;
                    const m = p < 0 ? 0 : w[p].motor;
                    s += (Sc * m - s) / (1 + taus);
                    const k = w.findIndex((x) => x.t === t);
                    if (k >= 0) { const e = s - sMeas(w[k]); c += e * e; n++; }
                }
            }
            return c / n;
        };
        let c0 = cost(Sc, taus);
        for (let it = 0; it < 80; it++) {
            let imp = false;
            for (const [a, b] of [[stepS, 0], [-stepS, 0], [0, stepT], [0, -stepT]]) { const q1 = Sc + a, q2 = Math.max(0, taus + b), c = cost(q1, q2); if (c < c0 - 1e-12) { Sc = q1; taus = q2; c0 = c; imp = true; } }
            if (!imp) { stepS /= 2; stepT /= 2; if (stepS < 0.01) break; }
        }
        if (!best || c0 < best.c) best = { Sc, taus, dm, c: c0, n: wins.length };
    }
    return best;
}

// the delay between the measured s and the drive: choose da so that  drive_meas(t) ~ slope*|s_meas(t - da)|*(1 - gamma v^2)
function fitDriveDelay(runs, k, slope, gamma, vk) {
    let best = null;
    for (let da = 0; da <= 6; da++) {
        let c = 0, n = 0;
        for (const run of runs) {
            const w = run.filter((x) => x.seg === 1 && x.brake === 0 && x.rps !== 0 && !x.slip);
            if (w.length < 12 || Math.abs(w[0].v) > 1) continue;
            for (let i = 3; i < w.length - 3; i++) {
                const a = w[i - 3], b = w[i + 3];
                if (b.t - a.t > 14) continue;
                const j = w.findIndex((x) => x.t >= w[i].t - da);
                if (j < 0) continue;
                const sg = Math.sign(w[i].v) || 1, acc = sg * (b.v - a.v) / ((b.t - a.t) / 60), drive = acc + k * Math.abs(w[i].v);
                const e = drive - slope * Math.abs(sMeas(w[j])) * drop(w[i].v, gamma, vk); c += e * e; n++;
            }
        }
        if (n && (!best || c / n < best.c)) best = { da, c: c / n };
    }
    return best ?? { da: 0, c: 0 };
}

// ---------- stage 3b: drive curve against the measured s (steady samples: the command constant over the last 40 ticks) ----------
function fitDrive(runs, k, extra = []) {
    const pts = [];
    for (const run of [...runs, ...extra]) for (let i = 3; i < run.length - 3; i++) {
        const x = run[i];
        if (x.rps === 0 || Math.abs(x.v) < 0.05 || x.slip || Math.abs(x.motor) < 0.02) continue;
        const a = run[i - 3], b = run[i + 3];
        if (a.brake !== 0 || b.brake !== 0 || x.brake !== 0 || b.t - a.t <= 0 || b.t - a.t > 14 || a.slip || b.slip) continue;
        let steady = true;
        for (let j = i; j >= 0 && run[j].t >= x.t - 40; j--) if (Math.abs(run[j].motor - x.motor) > 0.01 || run[j].brake !== 0) { steady = false; break; }
        if (!steady || x.t - run[0].t < 40) continue;
        const sg = Math.sign(x.v), acc = sg * (b.v - a.v) / ((b.t - a.t) / 60);
        pts.push([sg * sMeas(x), acc + k * Math.abs(x.v), Math.abs(x.v)]);
    }
    // slope and gamma together on the samples that are certainly not saturated (slope*s < 8), then muMax on the rest
    const lin = pts.filter((p) => 1.9 * Math.abs(p[0]) < 8);
    let best = null;
    for (const vk of [0, 4, 8, 12, 14, 16, 18, 20, 22]) for (let g = 0; g <= GMAX; g += GMAX / 60) for (let sl = 1.5; sl <= 3.2; sl += 0.01) {
        let c = 0; for (const [s, d, v] of lin) { const e = d - sl * Math.abs(s) * drop(v, g, vk); c += e * e; }
        if (!best || c < best.c) best = { slope: sl, gamma: g, vk, c, n: lin.length };
    }
    const hi = pts.filter((p) => !(1.9 * Math.abs(p[0]) < 8));
    let mu = null;
    for (let m = 6; m <= 40; m += 0.25) {
        let c = 0; for (const [s, d, v] of pts) { const e = d - Math.min(best.slope * Math.abs(s) * drop(v, best.gamma, best.vk), m); c += e * e; }
        if (!mu || c < mu.c) mu = { m, c };
    }
    best.muMax = mu.m;
    return best;
}

// ---------- stage 3c: the drive that is left under the brake ----------
function fitF(runs, P) {
    // (gamma is ~0 at the speeds of these runs; the drive is taken as measured)
    const pts = [];
    for (const run of runs) {
        const w = run.filter((x) => x.seg === 1 && x.brake > 0 && x.motor !== 0 && x.rps !== 0);
        if (w.length < 20 || Math.abs(w[0].v) > 1) continue;
        const b = Math.abs(w[0].brake), m = Math.abs(w[0].motor), t0 = w[0].t;
        const late = w.filter((x) => x.t - t0 >= 24 && x.t - t0 <= 56);
        if (late.length < 6) continue;
        // the drive from the measured speed: a + (k + g) v over the late part
        let sum = 0, n = 0;
        for (let i = 1; i < late.length - 1; i++) {
            const a = late[i - 1], c = late[i + 1];
            const acc = Math.abs(c.v - a.v) / ((c.t - a.t) / 60) * Math.sign(c.v - a.v) * Math.sign(late[i].v || 1);
            const g = b < DZ ? 0 : P.B1 * b + P.B2 * b * b;
            sum += acc + (P.k + g) * Math.abs(late[i].v); n++;
        }
        pts.push([b, (sum / n) / (P.slope * P.Sc * m)]);
    }
    let num = 0, den = 0;
    for (const [b, F] of pts) { const u = b - b * b; num += (1 - b * b - F) * u; den += u * u; }
    return { c1: den ? num / den : 0.8, n: pts.length, pts };
}

// ---------- stage 3d and 4: velocity error on component runs ----------
function velCost(runs, idx, P) { return idx.reduce((a, i) => { const e = err(runs[i], P); return a + e.rms * e.rms; }, 0) / idx.length; }

export function identify(runs, gammaRuns = []) {
    const kEst = estimateK(runs), P = { k: kEst.k };
    const brk = estimateBrake(runs, P.k); P.B1 = brk.B1; P.B2 = brk.B2;
    const sc = fitSChain(runs); P.Sc = sc.Sc; P.taus = sc.taus; P.dm = sc.dm;
    const dr = fitDrive(runs, P.k, gammaRuns); P.slope = dr.slope; P.muMax = dr.muMax; P.gamma = dr.gamma; P.vk = dr.vk;
    P.da = fitDriveDelay(runs, P.k, P.slope, P.gamma, P.vk).da;
    const fc = fitF(runs, P); P.c1 = fc.c1;
    const info = { kN: kEst.n, brakeLevels: brk.levels, sRms: Math.sqrt(sc.c), sWin: sc.n, driveN: dr.n, fN: fc.n, fPts: fc.pts };
    return { P, info };
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
    const args = process.argv.slice(2);
    const runsAll = readRuns(fs.readFileSync(args.find((a) => a.endsWith(".csv")), "utf8"));
    // --fit-log: fit scenarios (programs of regular running, any number of runs); they fix gamma with the first run-curve run,
    // enter stage 4, and stay out of the validation. Verification scenarios are kept in a file of their own that no stage reads.
    RHO = estimateRho(runsAll); console.log(`stage 0 RHO = ${RHO.toFixed(4)} (wheel radius ${(1 / (2 * Math.PI * RHO)).toFixed(3)} m)`);
    const nBase = runsAll.length;
    if (args.includes("--fit-log")) runsAll.push(...readRuns(fs.readFileSync(args[args.indexOf("--fit-log") + 1], "utf8")));
    const isFitSc = (i) => i >= nBase;
    const ok = (r) => r.length > 12 && !r.some((x) => x.slip) && !r.some((x) => Math.abs(x.motor) > 0.56) && !r.some((x) => Math.abs(x.v) > 36);
    const idxAll = runsAll.map((r, i) => i).filter((i) => ok(runsAll[i]));
    const fitScIdx = idxAll.filter(isFitSc).filter((i) => runsAll[i].length > 300);
    const fitIdx = idxAll.filter((i) => Math.max(...runsAll[i].map((x) => x.seg)) <= 3);
    const valAll = idxAll.filter((i) => !isFitSc(i) && Math.max(...runsAll[i].map((x) => x.seg)) >= 4);
    const gammaIdx = valAll.find((i) => runsAll[i].length > 4000);           // the high-speed cruise component
    const gammaSet = gammaIdx === undefined ? fitScIdx : [gammaIdx, ...fitScIdx];
    const valIdx = valAll.filter((i) => i !== gammaIdx);
    const comp = fitIdx.map((i) => runsAll[i]);
    const { P, info } = identify(runsAll.filter((r) => ok(r) && Math.max(...r.map((x) => x.seg)) <= 3), gammaSet.map((i) => runsAll[i]));
    // stage 3d: db on the component brake runs (motor path fixed)
    const brakeRuns = fitIdx.filter((i) => runsAll[i].some((x) => x.brake >= 0.05 && x.motor === 0));
    let bestDb = null;
    for (let db = 1; db <= 5; db++) { const Q = { ...P, db }; const c = velCost(runsAll, brakeRuns, Q); if (!bestDb || c < bestDb.c) bestDb = { db, c }; }
    P.db = bestDb.db;
    // stage 4: one bounded refinement of the velocity error (+-5%)
    const base = { ...P };
    const refIdx = [...fitIdx, ...gammaSet];
    let c0 = velCost(runsAll, refIdx, P);
    const bound = Number(args.includes("--bound") ? args[args.indexOf("--bound") + 1] : 0.05);
    const factors = Array.from({ length: Math.round(bound / 0.01) * 2 }, (_, i) => 1 + (i % 2 ? -1 : 1) * 0.01 * (1 + (i >> 1)));
    for (let pass = 0; pass < 3; pass++) for (const name of ["Sc", "taus", "slope", "k", "B1", "B2", "c1", "gamma", "vk"]) for (const f of factors) {
        const Q = { ...P, [name]: P[name] * f };
        if (Math.abs(Q[name] / base[name] - 1) > bound + 1e-9) continue;
        const c = velCost(runsAll, refIdx, Q); if (c < c0 - 1e-12) { P[name] = Q[name]; c0 = c; }
    }
    console.log(`stage 1 k = ${base.k.toFixed(4)}  stage 2 B1 = ${base.B1.toFixed(3)} B2 = ${base.B2.toFixed(3)}  stage 3a Sc = ${base.Sc.toFixed(2)} taus = ${base.taus.toFixed(2)} dm = ${base.dm} (s rms ${info.sRms.toFixed(2)} m/s, ${info.sWin} windows)  da = ${base.da}`);
    console.log(`stage 3b slope = ${base.slope.toFixed(3)} muMax = ${base.muMax.toFixed(2)}  stage 3c c1 = ${base.c1.toFixed(3)} (c2 = ${(1 - base.c1).toFixed(3)}; ${info.fN} runs)  stage 3d db = ${base.db ?? P.db}`);
    P.rho = RHO;
    if (args.includes("--params-out")) fs.writeFileSync(args[args.indexOf("--params-out") + 1], JSON.stringify(P, null, 1));
    console.log(`stage 4 (refined, +-${(bound * 100).toFixed(0)}%): ` + ["Sc", "taus", "dm", "da", "db", "slope", "muMax", "gamma", "vk", "k", "B1", "B2", "c1"].map((n) => `${n}=${(Math.abs(+P[n]) < 0.01 ? (+P[n]).toExponential(2) : (+P[n]).toFixed(4))}`).join(" "));
    const cat = (r) => (r.length > 4000 ? "run curve" : r.length > 1300 ? "sweep" : "scenario");
    const rows = valIdx.map((i) => ({ i, c: cat(runsAll[i]), ...err(runsAll[i], P) }));
    const fe = fitIdx.map((i) => err(runsAll[i], P));
    const mean = (a) => Math.sqrt(a.reduce((s, e) => s + e.rms * e.rms, 0) / a.length);
    console.log(`fit (component runs ${fitIdx.length}): mean rms ${mean(fe).toFixed(3)} m/s, worst max ${Math.max(...fe.map((e) => e.max)).toFixed(3)}`);
    for (const i of fitScIdx) { const e = err(runsAll[i], P); console.log(`fit scenario (fits gamma and stage 4, not validated): rms ${e.rms.toFixed(3)} max ${e.max.toFixed(3)} m/s`); }
    console.log(`validation (programmes with >= 4 segments, run ${gammaIdx} left out: it fixes gamma):`);
    for (const c of ["scenario", "sweep", "run curve"]) { const s = rows.filter((r) => r.c === c); if (s.length) console.log(`  ${c.padEnd(9)} ${s.length} runs: mean rms ${mean(s).toFixed(3)} m/s, worst max ${Math.max(...s.map((e) => e.max)).toFixed(3)}`); }
    console.log(`  all       ${rows.length} runs: mean rms ${mean(rows).toFixed(3)} m/s, worst max ${Math.max(...rows.map((e) => e.max)).toFixed(3)}`);
    if (args.includes("--worst")) for (const r of rows.sort((a, b) => b.max - a.max).slice(0, 10)) console.log(`    run ${r.i} (${r.c}, ${runsAll[r.i].length} samples): max ${r.max.toFixed(3)} rms ${r.rms.toFixed(3)}`);
}
