#!/usr/bin/env node
// Closed-loop simulation of the inertia-compensation rule on the pair: the commands are the formulas of the programs
// (u = c0 + c1 |v| + ci / max(|v|, vmin), evaluated on the model's own speed), not the logged commands.
// Used to split the bias of the realized acceleration / deceleration into the terms of the model.
// Usage: node rule_sim.mjs   (prints the deviation of the realized values from the target for a set of scenarios and model variants)
import fs from "node:fs";
import { Car } from "./pair.mjs";

const PA0 = JSON.parse(fs.readFileSync("../data/params_mo2000.json")), PB0 = JSON.parse(fs.readFileSync("../data/params_ku2100.json"));
const slope = (xs, ys) => { const n = xs.length, mx = xs.reduce((a, b) => a + b) / n, my = ys.reduce((a, b) => a + b) / n; return xs.reduce((s, x, i) => s + (x - mx) * (ys[i] - my), 0) / xs.reduce((s, x) => s + (x - mx) ** 2, 0); };

// sc: { V1, a, ad, beta: [bA, bB], alpha, X, Y }, rule: { G, F (apply the brake-car cancel correction) }
export function run(sc, rule, PA, PB, w) {
    const cars = { A: new Car(PA, 1), B: new Car(PB, -1) }, P = { A: PA, B: PB }, rows = { A: [], B: [] };
    let v = 0, phase = 1, hold = 0, t = 0; const log = [];
    const gain = {}; for (const c of "AB") { const p = P[c], K = p.Sc * p.slope; gain[c] = { K, cancel: cars[c].sign * p.k / K }; }
    for (; t < 12000; t++) {
        const av = Math.abs(v), cmd = {};
        for (const c of "AB") {
            const g = gain[c], sg = cars[c].sign, bi = c === "A" ? sc.beta[0] : sc.beta[1]; let m = g.cancel * av, b = 0, c0f = 0;
            if (phase === 1) m += sg * rule.G * bi * sc.a / g.K;
            if (phase === 3) {
                if (c === sc.X) m += sg * (-rule.G * sc.alpha * sc.ad / g.K);
                if (c === sc.Y) { const ci = rule.G * (1 - sc.alpha) * sc.ad / ((rule.GB ?? 1) * P[c].B1); b = ci / Math.max(av, 2); if (rule.F) c0f = g.cancel * P[c].c1 * ci; }
            }
            // rule v4: the drive of a car drops above vk by 1 - gamma (v - vk); the motor command (without the constant of F) is raised by the first-order inverse
            if (rule.GAMC && phase !== 4) m *= 1 + P[c].gamma * Math.max(0, av - P[c].vk);
            m += c0f;
            if (phase === 4) { m = 0; b = 0.5; }
            cmd[c] = [m, b];
        }
        for (const c of "AB") rows[c].push({ t, motor: cmd[c][0], brake: cmd[c][1] });
        if (phase === 1 && av >= sc.V1) { phase = 2; hold = 120; } else if (phase === 2 && --hold <= 0) phase = 3; else if (phase === 3 && av <= 2) phase = 4; else if (phase === 4 && av < 0.05) break;
        const [dA, lA] = cars.A.step(rows.A, t, v), [dB, lB] = cars.B.step(rows.B, t, v);
        v += w * (dA - lA * v + dB - lB * v) / 60; log.push([t / 60, v]);
    }
    const ts = log.map((x) => x[0]), vs = log.map((x) => Math.abs(x[1])), top = Math.max(...vs), pk = vs.findIndex((x) => x >= 0.98 * top);
    const acc = ts.map((_, i) => i).filter((i) => i < pk && vs[i] > 0.25 * top && vs[i] < 0.75 * top);
    const lastHi = vs.reduce((m, x, i) => (x > 0.85 * top ? i : m), pk);
    const dec = ts.map((_, i) => i).filter((i) => i > lastHi && vs[i] >= 3 && vs[i] <= 0.85 * top && ts[i] > ts[pk] + 2.5);
    return [slope(acc.map((i) => ts[i]), acc.map((i) => vs[i])), -slope(dec.map((i) => ts[i]), dec.map((i) => vs[i]))];
}

if (process.argv[1] && process.argv[1].endsWith("rule_sim.mjs")) {
    const scs = [
        { name: "A pulls, B cancel only; B brakes", V1: 12, a: 0.6, ad: 0.8, beta: [1, 0], alpha: 0.0, X: "A", Y: "B" },
        { name: "B pulls, A cancel only; A brakes", V1: 12, a: 0.6, ad: 0.8, beta: [0, 1], alpha: 0.0, X: "B", Y: "A" },
        { name: "both pull; motor A 0.5, brake B 0.5", V1: 12, a: 0.6, ad: 0.8, beta: [0.5, 0.5], alpha: 0.5, X: "A", Y: "B" },
        { name: "both pull; brake A only", V1: 20, a: 0.6, ad: 0.8, beta: [0.5, 0.5], alpha: 0.0, X: "B", Y: "A" },
    ];
    const variants = {
        "model": {}, "no γ": { gamma: 0 }, "no B2": { B2: 0 }, "no F": { noF: 1 }, "no delays": { dm: 0, da: 0, db: 0, taus: 0 },
        "no γ,B2,F": { gamma: 0, B2: 0, noF: 1 }, "none (ideal)": { gamma: 0, B2: 0, noF: 1, dm: 0, da: 0, db: 0, taus: 0 },
    };
    for (const rn of ["v1", "v2"]) {
        const rule = rn === "v1" ? { G: 2, F: false } : { G: 1 / 0.49, F: true };
        console.log(`rule ${rn}: deviation from the target [%]  (accel / decel)`);
        console.log("variant".padEnd(14) + scs.map((s) => s.name.slice(0, 22).padEnd(26)).join(""));
        for (const [vn, ov] of Object.entries(variants)) console.log(vn.padEnd(14) + scs.map((sc) => { const [ra, rd] = run(sc, rule, { ...PA0, ...ov }, { ...PB0, ...ov }, 0.49); return `${((ra - sc.a) / sc.a * 100).toFixed(1).padStart(6)} /${((rd - sc.ad) / sc.ad * 100).toFixed(1).padStart(6)}`.padEnd(26); }).join(""));
    }
}
