#!/usr/bin/env node
// Fits  dv/dt = a*motor(t-d) + b*brake(t-d) + c*brake(t-d)*v - k*v - q*v*|v|  (per tick)
// to the RUN samples (state 1, 2-tick spacing) of a probe log, for each lag d,
// and prints the lag with the smallest residual.
// Usage: node fit.mjs [log.csv] [--runs 3,5,...] [--no-quad] [--max-lag 12]
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const opt = (name) => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined);

export function readRuns(text) {
    const rows = text.trim().split("\n").slice(1).map((l) => l.split(","))
        // Signed speed and motor: the model dv/dt = K*m*(1-c*b) - k*v - B*b*v is odd in (v, m),
        // so reverse running needs no special case.
        .map((r) => ({ t: +r[2], v: +r[6], motor: +r[7], brake: +r[8], state: +r[10], slip: +(r[12] || 0), rps: +(r[13] || 0), seg: +r[11] }));
    const runs = [];
    let cur = [];
    for (const r of rows) {
        if (r.state === 1 && (cur.length === 0 || (r.t - cur[cur.length - 1].t >= 1 && r.t - cur[cur.length - 1].t <= 2))) cur.push(r);
        else { if (cur.length > 1) runs.push(cur); cur = r.state === 1 ? [r] : []; }
    }
    if (cur.length > 1) runs.push(cur);
    return runs;
}

// input value at tick `t - d`: last sample at or before it, 0 before the run starts
function at(run, t, d, key) {
    let value = 0;
    for (const r of run) { if (r.t <= t - d) value = r[key]; else break; }
    return value;
}

function solve(A, y) { // least squares via normal equations
    const n = A[0].length;
    const M = Array.from({ length: n }, () => new Array(n + 1).fill(0));
    for (let r = 0; r < A.length; r++) for (let i = 0; i < n; i++) {
        for (let j = 0; j < n; j++) M[i][j] += A[r][i] * A[r][j];
        M[i][n] += A[r][i] * y[r];
    }
    for (let i = 0; i < n; i++) {
        let p = i;
        for (let k = i + 1; k < n; k++) if (Math.abs(M[k][i]) > Math.abs(M[p][i])) p = k;
        [M[i], M[p]] = [M[p], M[i]];
        if (Math.abs(M[i][i]) < 1e-12) return null;
        for (let k = 0; k < n; k++) if (k !== i) {
            const f = M[k][i] / M[i][i];
            for (let j = i; j <= n; j++) M[k][j] -= f * M[i][j];
        }
    }
    return M.map((row, i) => row[n] / row[i]);
}

export function fit(runs, d, quad = true) {
    const A = [], y = [];
    for (const run of runs) for (let i = 0; i + 1 < run.length; i++) {
        const t = run[i].t, v = run[i].v;
        const m = at(run, t, d, "motor"), b = at(run, t, d, "brake");
        const cols = [m, b, b * v, -v];
        if (quad) cols.push(-v * v);
        A.push(cols); y.push((run[i + 1].v - v) / 2);
    }
    // terms that are identically zero in the data (e.g. no brake runs) are left out
    const used = A[0].map((_, j) => A.some((r) => r[j] !== 0));
    const Au = A.map((r) => r.filter((_, j) => used[j]));
    const x = solve(Au, y);
    if (!x) return null;
    let sse = 0;
    Au.forEach((r, k) => { const e = y[k] - r.reduce((s, c, j) => s + c * x[j], 0); sse += e * e; });
    const coef = []; let q = 0;
    used.forEach((u) => coef.push(u ? x[q++] : null));
    return { d, coef, rms: Math.sqrt(sse / y.length), n: y.length };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    const logPath = args.find((a) => a.endsWith(".csv")) ?? path.join(here, "../data/log.csv");
    const maxLag = Number(opt("--max-lag") ?? 12);
    const only = opt("--runs")?.split(",").map(Number);
    let runs = readRuns(fs.readFileSync(logPath, "utf8"));
    runs.forEach((r, i) => console.log(`run ${i}: t ${r[0].t}-${r[r.length - 1].t} motor ${r[0].motor} brake ${r[0].brake} v ${r[0].v.toFixed(2)}->${r[r.length - 1].v.toFixed(2)}`));
    if (only) runs = runs.filter((_, i) => only.includes(i));
    let best = null;
    for (let d = 0; d <= maxLag; d++) {
        const f = fit(runs, d, !flag("--no-quad"));
        if (f && (!best || f.rms < best.rms)) best = f;
        if (f) console.log(`lag ${d}: rms ${(f.rms * 60).toFixed(4)} m/s^2`);
    }
    const [a, b, c, k, q] = best.coef;
    const f3 = (x, s = 60, p = 3) => (x === null || x === undefined ? "-" : (x * s).toFixed(p));
    console.log(`\nbest lag ${best.d} ticks, n=${best.n}, rms ${(best.rms * 60).toFixed(3)} m/s^2`);
    console.log(`motor gain      a = ${f3(a, 60, 2)} m/s^2 per unit`);
    console.log(`brake           b = ${f3(b, 60, 2)} m/s^2 per unit,  c = ${f3(c, 60, 3)} 1/s per unit`);
    console.log(`linear drag     k = ${f3(k, 60, 4)} 1/s` + (k ? `  (time constant ${(1 / (k * 60)).toFixed(1)} s)` : ""));
    console.log(`quadratic drag  q = ${f3(q, 60, 5)} 1/m`);
}
