// The forward model of the coupled pair (commands -> speed) with the terms that the measurements of 2026-10-18 changed as parameters, and a scorer over all runs.
//   v' = w ( f_A + f_B ),   f_i = eff D_i - (kappa k_i + k2 |v| + g_i beta) v,   D_i = sat(slope sd drop_lam(v), muMax)
//   F(b) = 1 - phi (c1 b + (1 - c1) b^2) weakens the motor of a car by its own brake;  drop_lam(v) = 1 - lam gamma max(0, |v| - vk)
// theta = { w (wA: the mass fraction of car A, overrides it), beta, eff, lam, phi, kappa, k2, dscale }; the old model is  w 0.49, beta 1.05, eff 1, lam 1, phi 1, kappa 1, k2 0.
// The commands are rebuilt from the program text (replay.mjs): no rounding of the log. The speed is compared with the MEAN of the two cars' speeds (x frame),
// so that the oscillation of the coupler does not enter the fit of a bias.
//   node fwd.mjs [name-regex]       prints rms / max per run and per category for the old model
import fs from "node:fs";
import path from "node:path";
import { fixCommands } from "./replay.mjs";

const DZ = 0.0098, sat = (x, a) => Math.min(a, Math.max(-a, x));
export const THETA0 = { w: 0.49, beta: 1.05, eff: 1, lam: 1, phi: 1, kappa: 1, k2: 0, dscale: 1 };
// The model of record: w and beta at their natural values (equal shares of two cars, the brake like a single car), the other five fitted on the isolation runs
// (cancel holds, ftest, creep, decel paths, step runs) with `node fit_fwd.mjs eff,lam,phi,kappa,k2 '{"w":0.5,"beta":1}'`; the use, verify and vvvf runs were not used.
// The model of record (THETA2): the single-car values for the resistance (kappa 1, k2 8e-5), the brake (phi 1, beta 1) and the slope of the drive drop (lam 1), and two corrections of the drive
// that `node pair_loop.mjs` reads from the six equilibrium-speed runs (pf_terminal_*): the drive of the pair is 0.83% weaker (eff), and its drop starts dvk = 14.9 m/s above the single-car
// knee vk (the form was chosen by leave-one-out over those runs). The dead zone of the brake command is read from the pf_brake_dz* runs (0.0098; the interval is 0.009 to 0.0105).
// The older runs (112) took no part. THETA1 below is the earlier five-correction fit, kept for comparison.
export const THETA2 = { w: 0.5, beta: 1, eff: 0.9917, lam: 1, phi: 1, kappa: 1, k2: 8e-5, dscale: 1, dvk: 14.93 };
export const THETA1 = { w: 0.5, beta: 1, eff: 0.9966, lam: 0.4457, phi: 1.204, kappa: 1.0059, k2: 2.61e-5, dscale: 1 };
const DATA = path.join(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), "../data");
// The pair (data/pair_config.json): the single-car parameters of the two cars and the sign of their motors toward +x (the logged speed of a car is sign * the speed toward +x).
export const CONFIG = JSON.parse(fs.readFileSync(path.join(DATA, "pair_config.json"), "utf8"));
// A single car (no "B" in the file) is a pair whose car B is a copy of car A with the weight 0: the same code fits one car (wA = 1).
export const SINGLE = !CONFIG.B;
const PA = JSON.parse(fs.readFileSync(path.join(DATA, CONFIG.A.params), "utf8")), PB = SINGLE ? PA : JSON.parse(fs.readFileSync(path.join(DATA, CONFIG.B.params), "utf8")), sA = CONFIG.A.sign, sB = SINGLE ? sA : CONFIG.B.sign;

export class CarX {
    constructor(P, sign, th) { this.P = P; this.sign = sign; this.th = th; this.s = 0; this.sh = []; this.pm = -1; this.pb = -1; }
    step(rows, t, v) {
        const P = this.P, th = this.th, adv = (p, tt) => { while (p + 1 < rows.length && rows[p + 1].t <= tt) p++; return p; };
        this.pm = adv(this.pm, t - P.dm); this.pb = adv(this.pb, t - P.db);
        const m = this.pm < 0 ? 0 : sat(rows[this.pm].motor, 1), b = this.pb < 0 ? 0 : sat(Math.abs(rows[this.pb].brake), 1);
        const F = Math.max(0, 1 - th.phi * (P.c1 * b + (1 - P.c1) * b * b));
        const target = P.Sc * m * F;
        this.s += (target - this.s) / (1 + P.taus * (target < this.s ? th.dscale : 1)); this.sh.push(this.s);   // dscale: the first-order lag of the axle excess s when it falls, in units of the lag when it rises
        const sd = this.sh.length > P.da ? this.sh[this.sh.length - 1 - P.da] : 0, vOwn = this.sign * v;
        const knee = th.vkp ?? P.vk + (th.dvk ?? 0), ex = Math.max(0, Math.abs(vOwn) - knee), drop = 1 - th.lam * P.gamma * (th.dpow === undefined ? ex : 20 * (ex / 20) ** th.dpow);   // vkp: one knee for both cars (m/s; overrides vk + dvk); dvk: the knee moved up by dvk m/s; dpow: the power of the excess over the knee (1 = linear), scaled so that 20 m/s above the knee drops the same
        const drive = this.sign * sat(P.slope * sd * drop, P.muMax) * th.eff;
        const g = (b < (th.dz ?? DZ) ? 0 : P.B1 * b + P.B2 * b * b) * th.beta;   // th.dz: the dead zone of the brake command (default DZ = 0.0098: the pair brakes at 0.0085 not and at 0.0105 does; 0.0113 of the single-car fit is rejected by pf_brake_dzA_0.0105)
        return [drive, th.kappa * P.k + th.k2 * Math.abs(v) + g];
    }
}

const load = (f) => fs.readFileSync(f, "utf8").trim().split("\n").slice(1).map((l) => l.split(",")).map((c) => ({ t: +c[2], x: +c[3], v: +c[6], motor: +c[7], brake: +c[8], state: +c[10], reason: +c[11] }));
const span = (rows) => {
    const i = rows.findIndex((r) => r.state === 1), j = rows.findLastIndex((r) => r.state === 1), out = [];
    for (const r of rows.slice(i, j + 1)) { const p = out.at(-1); if (p && r.t - p.t > 4) out.push({ ...p, t: p.t + 2, motor: 0, brake: 0, state: 0 }); out.push(r); }
    return out;
};

export function loadRun(name) {
    const dir = path.join(DATA, "twocar", name), pf = path.join(dir, "programs.json");
    if (!fs.existsSync(pf) || !fs.existsSync(path.join(dir, "A.csv"))) return null;
    const progs = JSON.parse(fs.readFileSync(pf, "utf8"));
    let A = span(fixCommands(load(path.join(dir, "A.csv")), progs.A)), B = SINGLE ? A : span(fixCommands(load(path.join(dir, "B.csv")), progs.B));
    const t0 = Math.max(A[0].t, B[0].t); A = A.filter((r) => r.t >= t0); B = B.filter((r) => r.t >= t0);
    if (A.length < 20 || B.length < 20) return null;
    const bt = new Map(B.map((r) => [r.t, r])), mean = new Map();
    for (const r of A) { const b = bt.get(r.t); if (b) mean.set(r.t, (sA * r.v + sB * b.v) / 2); }   // x frame: the logged speed of a car is its sign times the speed toward +x
    return { name, A, B, mean, v0: (sA * A[0].v + sB * B[0].v) / 2 };
}

export function simulate(run, th) {
    const a = new CarX(PA, sA, th), b = new CarX(PB, sB, th), out = new Map(), wa = SINGLE ? 1 : th.wA ?? th.w, wb = SINGLE ? 0 : th.wA === undefined ? th.w : 1 - th.wA; let v = run.v0;   // wA: the mass fraction of car A, M_A / (M_A + M_B) (default: w each)
    out.set(run.A[0].t, v);
    for (let t = run.A[0].t; t < run.A.at(-1).t; t++) {
        const [dA, lA] = a.step(run.A, t, v), [dB, lB] = b.step(run.B, t, v);
        v += (wa * (dA - lA * v) + wb * (dB - lB * v)) / 60; out.set(t + 1, v);
    }
    return out;
}

// The coupler as a spring and a damper between two masses (stage 3): each car keeps its own speed; M = 1/(2 w) per car.
//   vA' = (f_A - Fc) / M,  vB' = (f_B + Fc) / M,  Fc = Kc (d - d0) + Cc d',  d = x_A - x_B
export function simulate2m(run, th, Kc, Cc) {
    const a = new CarX(PA, sA, th), b = new CarX(PB, sB, th), M = 1 / (2 * th.w), out = new Map();
    let vA = sA * run.A[0].v, vB = sB * run.B[0].v, d = 0; out.set(run.A[0].t, [vA, vB, d]);
    for (let t = run.A[0].t; t < run.A.at(-1).t; t++) {
        const [dA, lA] = a.step(run.A, t, vA), [dB, lB] = b.step(run.B, t, vB), Fc = Kc * d + Cc * (vA - vB);
        vA += ((dA - lA * vA) - Fc) / M / 60; vB += ((dB - lB * vB) + Fc) / M / 60; d += (vA - vB) / 60; out.set(t + 1, [vA, vB, d]);
    }
    return out;
}
export function score2m(run, th, Kc, Cc) {
    const sim = simulate2m(run, th, Kc, Cc), bt = new Map(run.B.map((r) => [r.t, r])), x0 = run.A[0].x - (bt.get(run.A[0].t)?.x ?? run.B[0].x);
    const e = { A: [0, 0, 0], B: [0, 0, 0], d: [0, 0, 0] }, add = (k, x) => { e[k][0] += x * x; e[k][1] = Math.max(e[k][1], Math.abs(x)); e[k][2]++; };
    for (const r of run.A) { const q = sim.get(r.t), b = bt.get(r.t); if (!q || !b) continue; add("A", q[0] - sA * r.v); add("B", q[1] - sB * b.v); add("d", q[2] - (r.x - b.x - x0)); }
    return Object.fromEntries(Object.entries(e).map(([k, [q, m, n]]) => [k, { rms: Math.sqrt(q / n), max: m }]));
}

export function score(run, th) {
    const sim = simulate(run, th); let s = 0, mx = 0, n = 0, bias = 0;
    for (const [t, vr] of run.mean) { const m = sim.get(t); if (m === undefined) continue; const e = m - vr; s += e * e; bias += e; mx = Math.max(mx, Math.abs(e)); n++; }
    return { rms: Math.sqrt(s / n), max: mx, bias: bias / n, n };
}

export const category = (n) => /^(cancel_(linear|quad|quad_drop|tuned|scaled)|cancel_tuned_a|ftest_|creep_)/.test(n) ? "cancel" : /^decel_/.test(n) ? "decel" : /^(passive_B|drive_B|cancel_B)/.test(n) ? "step" : /^use/.test(n) ? "use" : /^verify/.test(n) ? "verify" : /^vvvf/.test(n) ? "vvvf" : /^pf_/.test(n) ? "plan" : "other";

export function corpus(re = ".") {
    return fs.readdirSync(path.join(DATA, "twocar")).filter((n) => new RegExp(re).test(n)).map(loadRun).filter(Boolean);
}

if (process.argv[1] && process.argv[1].endsWith("fwd.mjs")) {
    const runs = corpus(process.argv[2] ?? "."), verbose = process.argv.includes("-v");
    console.log(`${runs.length} runs: model - mean speed of the two cars [m/s]; old model (THETA0) | model of record (THETA2)`);
    const cat = {};
    for (const run of runs) { const o = score(run, THETA0), n = score(run, THETA2), c = category(run.name); (cat[c] ??= []).push([o, n]); if (verbose) console.log(" ", run.name.padEnd(24), "old rms", o.rms.toFixed(3), "max", o.max.toFixed(3), "| new rms", n.rms.toFixed(3), "max", n.max.toFixed(3), "bias", n.bias.toFixed(3)); }
    const f = (rs, i, k) => rs.reduce((a, r) => a + r[i][k], 0) / rs.length, mx = (rs, i) => Math.max(...rs.map((r) => r[i].max));
    for (const [c, rs] of Object.entries(cat)) console.log(c.padEnd(8), String(rs.length).padStart(3), "runs | rms mean", f(rs, 0, "rms").toFixed(3), "max", mx(rs, 0).toFixed(3), "| rms mean", f(rs, 1, "rms").toFixed(3), "max", mx(rs, 1).toFixed(3), " bias", f(rs, 1, "bias").toFixed(3));
}
