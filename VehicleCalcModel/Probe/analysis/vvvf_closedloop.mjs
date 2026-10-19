#!/usr/bin/env node
// The confirmation drive pattern with the 2000-series traction controller (n485.lua, a 1M1T unit) in a closed loop with the pair model.
//   node vvvf_closedloop.mjs <seed> <out folder>
// Pattern: 0 -> 35 km/h (power notch P2) -> 105 (P4) -> 65 (brake) -> 90 (P4) -> 45 (brake) -> stop; every brake phase takes a brake notch of B20..B28
// by lot (bN/8/3.6 = 0.69..0.97 m/s^2). The controller's N2 (the motor acceleration of the M car) and N1 (the friction brake deceleration of the M car
// and of the T car) are the accelerations each car gives alone; they are turned back into the motor and brake commands of the cars (the inverse of the
// single-car model of the car, with the resistance cancel always on) and the commands are applied to the pair model; its speed goes back to the controller.
// Result: <out>/commands.json (per tick), <out>/programs.json (the segments for the probe, one program per car, forward frame -> signs by direction).
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { Car, BRAKE_GAIN } from "./pair.mjs";

const HERE = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1"));
const seed = +(process.argv[2] ?? 1), out = process.argv[3] ?? `../data/vvvf/run_${seed}`;
const PA = JSON.parse(fs.readFileSync(path.join(HERE, "../data/params_mo2000.json"))), PB = JSON.parse(fs.readFileSync(path.join(HERE, "../data/params_ku2100.json")));
const W = 0.49, DZ = 0.0113, MMAX = 0.5, SEG = 4, SCALE = +(process.env.ACC_SCALE ?? 1);

// a seeded generator (mulberry32)
let s = seed >>> 0; const rnd = () => { s = (s + 0x6d2b79f5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = () => 20 + Math.floor(rnd() * 9);   // B20..B28

// the pattern: [kind, target km/h, notch]; the first acceleration is P2, the others P4
const phases = [["acc", 35, 2], ["acc", 105, 4], ["brk", 65, pick()], ["acc", 90, 4], ["brk", 45, pick()], ["stop", 0.4, pick()]];

const K = (P) => P.Sc * P.slope, cancel = (P) => P.k / K(P);
const Fb = (P, b) => Math.max(0.05, 1 - P.c1 * b - (1 - P.c1) * b * b);
const drop = (P, v) => 1 - P.gamma * Math.max(0, Math.abs(v) - P.vk);
// the brake command that gives the deceleration a (> 0) at the speed v in the pair (the single-car law times BRAKE_GAIN)
function brakeFor(P, a, v) {
    const x = a / (BRAKE_GAIN * Math.max(Math.abs(v), 2));
    if (x <= 0) return 0;
    const b = P.B2 > 1e-9 ? (-P.B1 + Math.sqrt(P.B1 * P.B1 + 4 * P.B2 * x)) / (2 * P.B2) : x / P.B1;
    return b < DZ ? 0 : Math.min(b, 1);
}

const lua = spawn("lua", [path.join(HERE, "vvvf_harness.lua"), path.join(HERE, "../../../CHUSO/CHUSO2000_Traction_Controller/scripts/n485.lua")]);
const lines = []; let wake = null, buf = "";
lua.stdout.on("data", (d) => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { lines.push(buf.slice(0, i)); buf = buf.slice(i + 1); } if (wake) { const w = wake; wake = null; w(); } });
const tick = async (line) => { lua.stdin.write(line + "\n"); while (!lines.length) await new Promise((r) => (wake = r)); return lines.shift().split(" ").map(Number); };

const A = new Car(PA, 1), B = new Car(PB, 1), rowsA = [], rowsB = [];   // both in the forward frame (sign +1)
let v = 0, ph = 0, t = 0; const log = [];
for (; t < 60 * 400; t++) {
    const [kind, target, notch] = phases[ph], kmh = v * 3.6;
    let pN = 0, bN = 0;
    if (kind === "acc") pN = notch; else bN = notch;
    if (kind === "stop" && v < 2.0) bN = 31;   // the last part of the stop
    const [n2, n1M, n1T] = await tick(`${v.toFixed(6)} ${pN} ${bN} 1 0 0`);
    // the accelerations each car gives alone -> the commands (forward frame)
    let mM, mT, bM, bT;
    if (process.env.NEWIC) {
        // the new inertia compensation (INERTIA_COMPENSATION_NEW.md, rule v7): the cancel 1.02 (k |v| + k2 v^2), the drive part divided by drop,
        // no F compensation; a brake request under the dead zone goes to the negative drive of the same car
        const KF = { A: 0.1062, T: 0.0939 }, K2 = 8e-5, r = (P, kf) => 1.02 * (kf * Math.abs(v) + K2 * v * v);
        const car = (P, kf, aM_, aB_) => {
            let b = brakeFor(P, aB_ * SCALE, v), a = aM_ * SCALE;
            if (b === 0 && aB_ > 0) a -= aB_ * SCALE;       // under the dead zone: the brake share as a negative drive
            const m = (a / drop(P, v) + r(P, kf)) / K(P);
            return [Math.max(-MMAX, Math.min(MMAX, m)), b];
        };
        [mM, bM] = car(PA, KF.A, n2, n1M); [mT, bT] = car(PB, KF.T, 0, n1T);
    } else {
        const aM = n2 * SCALE; bM = brakeFor(PA, n1M * SCALE, v); bT = brakeFor(PB, n1T * SCALE, v);
        mM = Math.max(-MMAX, Math.min(MMAX, (aM / K(PA) + cancel(PA) * Math.abs(v)) / (Fb(PA, bM) * drop(PA, v))));
        mT = Math.max(-MMAX, Math.min(MMAX, (cancel(PB) * Math.abs(v)) / (Fb(PB, bT) * drop(PB, v))));
    }
    rowsA.push({ t, motor: mM, brake: bM }); rowsB.push({ t, motor: mT, brake: bT });
    const [dA, lA] = A.step(rowsA, t, v), [dB, lB] = B.step(rowsB, t, v);
    log.push({ t, v, pN, bN, n2, n1M, n1T, mM, bM, mT, bT });
    v = Math.max(0, v + W * (dA - lA * v + dB - lB * v) / 60);
    if (kind === "acc" && kmh >= target) ph++;
    else if (kind === "brk" && kmh <= target) ph++;
    else if (kind === "stop" && v < 0.15 && t > 600) break;
    if (ph >= phases.length) break;
}
lua.stdin.end();
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, "commands.json"), JSON.stringify({ seed, phases, scale: SCALE, log }));
// the segments: SEG tick each, the mean command of the car in its own forward frame; the signs of the direction are put by the runner
const seg = (key) => { const r = []; for (let i = 0; i < log.length; i += SEG) { const w = log.slice(i, i + SEG), mean = (k) => w.reduce((a, x) => a + x[k], 0) / w.length; r.push([w.length, mean(key === "A" ? "mM" : "mT"), mean(key === "A" ? "bM" : "bT")]); } return r; };
fs.writeFileSync(path.join(out, "programs.json"), JSON.stringify({ A: seg("A"), B: seg("B") }));
const top = Math.max(...log.map((x) => x.v));
console.log(`seed ${seed}: phases ${phases.map((p) => p.join(":")).join(" ")} ; ${log.length} ticks (${(log.length / 60).toFixed(0)} s), top ${top.toFixed(1)} m/s, distance ${(log.reduce((a, x) => a + x.v / 60, 0)).toFixed(0)} m`);
const peak = (f) => Math.max(...log.map(f)); console.log(`max motor of M ${peak((x) => x.mM).toFixed(3)} min ${Math.min(...log.map((x) => x.mM)).toFixed(3)}, max brake M ${peak((x) => x.bM).toFixed(3)}, T ${peak((x) => x.bT).toFixed(3)}, max N2 ${peak((x) => x.n2).toFixed(3)}`);
