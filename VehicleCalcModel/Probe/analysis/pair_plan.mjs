// The measurement plan of the pair as one flow (see PAIR_FIT_PLAN.md).
//   node pair_plan.mjs baseline            the standard error of the five corrections that the 22 fit runs allow, and the correlation of their columns
//   node pair_plan.mjs discriminate        how far apart the rival hypotheses about the drive (eff, lam) predict each experiment: the experiments to run are the ones with the largest difference
//   node pair_plan.mjs table [--write]   the experiment table of the pair of data/pair_config.json (levels from the single-car parameters and vtop: m = (sum k_i v + 2 k2 v^2) / sum K_i); --write replaces pair_experiments.json, otherwise pair_experiments.generated.json
//   node pair_plan.mjs program <id> <dir>  prints the programs {A, B} of one experiment for the travel direction dir (+1 / -1), for pair_run.py
// An experiment is data (pair_experiments.json). Its programs are built here; the model of record answers in closed loop, so the
// plan is examined before any game time is spent. The standard error is that of a least-squares fit of the five parameters
// (FREE=eff,lam,phi limits the fit to those; the others are fixed at TRUTH) to model-minus-measured samples taken once per 10 seconds, with the residual floor of the model (SIGMA) as the noise.
import fs from "node:fs";
import path from "node:path";
import { CarX, simulate, corpus, category, THETA1, THETA2, CONFIG, SINGLE } from "./fwd.mjs";
const CARS = SINGLE ? ["A"] : ["A", "B"];   // a single car (no "B" in the config) has one program, one row set and the weight 1

const DATA = path.join(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), "../data");
const ALL = ["eff", "lam", "kappa", "k2", "phi"], PAR = (process.env.FREE ?? ALL.join(",")).split(",");   // FREE: the parameters to fit; the others stay at the single-car values of TRUTH
const TRUTH = { ...THETA1, eff: 0.9945, lam: 0.163, phi: 1, kappa: 1, k2: 8e-5 };   // the model of the plan: the single-car resistance and brake, the two corrections of the drive
const STEP = { eff: 0.002, lam: 0.05, kappa: 0.002, k2: 5e-6, phi: 0.05 };
const TARGET = { eff: 0.002, lam: 0.1, kappa: 0.005, k2: 1e-5, phi: 0.1 };            // the standard error that each parameter needs to be told from its neutral value
const SIGMA = 0.03, STRIDE = 600;   // one sample per 10 s: the residual of a run is correlated over about the time constant of the drag (9 s)
const K2 = CONFIG.k2, SIGN = { A: CONFIG.A.sign, B: SINGLE ? CONFIG.A.sign : CONFIG.B.sign };
const P = { A: JSON.parse(fs.readFileSync(path.join(DATA, CONFIG.A.params))), B: JSON.parse(fs.readFileSync(path.join(DATA, SINGLE ? CONFIG.A.params : CONFIG.B.params))) };
const KFIT = { A: P.A.k, B: P.B.k };   // the commands are rebuilt from the program text, so the cancel coefficients need to be safe, not exact
const EXP = JSON.parse(fs.readFileSync(new URL("./pair_experiments.json", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1"), "utf8")).experiments;
const STOP = { len: 600, vend: -0.2, cancel: false, m: [0, 0], b: [0.5, 0.5] };

// the segment as formula coefficients [c0, c1, c2] of u = c0 + c1 |v| + c2 v^2 for motor and the constant brake of each car, in each car's own sign (dir: travel direction)
function segmentFormula(seg, car, dir) {
    const p = P[car], K = p.Sc * p.slope, sg = SIGN[car] * dir, i = car === "A" ? 0 : 1;
    const cancel = seg.cancel ? [0, sg * 1.02 * KFIT[car] / K, sg * 1.02 * K2 / K] : [0, 0, 0];
    return { m: [sg * seg.m[i], cancel[1], cancel[2]], b: seg.b[i] };
}
const segText = (seg, f) => `${seg.len}/${seg.vend}/1/${f.m[0].toFixed(8)},${f.m[1].toFixed(8)},${f.m[2].toFixed(10)},0/${f.b.toFixed(4)},0,0,0`;
export function programs(exp, dir) {
    const segs = [...exp.segs, STOP];
    return Object.fromEntries(CARS.map((c) => [c, segs.map((s) => segText(s, segmentFormula(s, c, dir))).join(";")]));
}

// the closed-loop run of an experiment on the model theta (dir +1): rows of both cars in the form that fwd.mjs reads, and the speed as the "measurement"
export function synth(exp, th) {
    const segs = [...exp.segs, STOP], rows = { A: [], B: [] }, car = { A: new CarX(P.A, 1, th), B: new CarX(P.B, -1, th) }, mean = new Map();
    let v = 0, t = 0;
    const wa = SINGLE ? 1 : th.wA ?? th.w, wb = SINGLE ? 0 : th.wA === undefined ? th.w : 1 - th.wA;   // the mass fraction of car A, as in fwd.mjs simulate()
    for (let s = 0; s < segs.length; s++) {
        const seg = segs[s], f = { A: segmentFormula(seg, "A", 1), B: segmentFormula(seg, "B", 1) };
        for (let tau = 0; tau < seg.len; tau++, t++) {
            const av = Math.abs(v), d = [];
            for (const c of CARS.join("")) {
                rows[c].push({ t, motor: f[c].m[0] + f[c].m[1] * av + f[c].m[2] * av * av, brake: f[c].b, state: 1, reason: s + 1 });
                d.push(car[c].step(rows[c], t, v));
            }
            mean.set(t, v);
            if (SINGLE) d[1] = [0, 0];
            v += (wa * (d[0][0] - d[0][1] * v) + wb * (d[1][0] - d[1][1] * v)) / 60;
            if ((seg.vend > 0 && Math.abs(v) >= seg.vend) || (seg.vend < 0 && Math.abs(v) <= -seg.vend)) { t++; break; }
        }
    }
    mean.set(t, v);
    return { name: exp.id, A: rows.A, B: SINGLE ? rows.A : rows.B, mean, v0: 0 };
}

// the sensitivity of the samples (once per STRIDE ticks) to the five parameters: one column per parameter
function columns(run, th) {
    const base = simulate(run, th), ts = [...base.keys()].filter((t) => t % STRIDE === 0 && run.mean.has(t)), cols = {};
    for (const k of PAR) { const o = simulate(run, { ...th, [k]: th[k] + STEP[k] }); cols[k] = ts.map((t) => (o.get(t) - base.get(t)) / STEP[k]); }
    return cols;
}
const cache = new Map();
const colsOf = (id, run) => (cache.has(id) ? cache.get(id) : (cache.set(id, columns(run, TRUTH)), cache.get(id)));
const stack = (list) => Object.fromEntries(PAR.map((k) => [k, list.flatMap((c) => c[k])]));

function invert(M) {
    const n = M.length, A = M.map((r, i) => [...r, ...Array.from({ length: n }, (_, j) => +(i === j))]);
    for (let i = 0; i < n; i++) {
        let p = i; for (let r = i + 1; r < n; r++) if (Math.abs(A[r][i]) > Math.abs(A[p][i])) p = r;
        [A[i], A[p]] = [A[p], A[i]]; const d = A[i][i]; if (Math.abs(d) < 1e-300) return null;
        A[i] = A[i].map((x) => x / d); for (let r = 0; r < n; r++) if (r !== i) { const f = A[r][i]; A[r] = A[r].map((x, j) => x - f * A[i][j]); }
    }
    return A.map((r) => r.slice(n));
}
export function standardErrors(list) {
    const J = stack(list), G = PAR.map((a) => PAR.map((b) => J[a].reduce((s, x, i) => s + x * J[b][i], 0))), inv = invert(G);
    const corr = PAR.map((a) => PAR.map((b) => { const ab = G[PAR.indexOf(a)][PAR.indexOf(b)], aa = G[PAR.indexOf(a)][PAR.indexOf(a)], bb = G[PAR.indexOf(b)][PAR.indexOf(b)]; return ab / Math.sqrt(aa * bb); }));
    return { se: inv ? Object.fromEntries(PAR.map((k, i) => [k, SIGMA * Math.sqrt(Math.max(inv[i][i], 0))])) : Object.fromEntries(PAR.map((k) => [k, Infinity])), corr };
}
const need = (se) => PAR.reduce((s, k) => s + (se[k] / TARGET[k]) ** 2, 0);
function show(label, r) {
    console.log(`${label}\n  standard error / target: ` + PAR.map((k) => `${k} ${r.se[k].toPrecision(2)}/${TARGET[k]}${r.se[k] <= TARGET[k] ? " ok" : " NO"}`).join("  "));
    console.log("  column correlation (" + PAR.join(" ") + "):\n" + r.corr.map((row, i) => "   " + PAR[i].padEnd(6) + row.map((x) => x.toFixed(2).padStart(6)).join("")).join("\n"));
}
function fitSetColumns() {
    const FIT = new Set(["cancel", "decel", "step"]);
    return corpus(".").filter((r) => FIT.has(category(r.name))).map((r) => { const base = simulate(r, TRUTH), ts = [...base.keys()].filter((t) => t % STRIDE === 0 && r.mean.has(t)), cols = {};
        for (const k of PAR) { const o = simulate(r, { ...TRUTH, [k]: TRUTH[k] + STEP[k] }); cols[k] = ts.map((t) => (o.get(t) - base.get(t)) / STEP[k]); } return cols; });
}

// The rival hypotheses that the 22 fit runs and the 90 held-out runs cannot tell apart (TWO_CAR_MODEL.md, "補正の必要性"):
// the drive of the pair is weaker by a constant factor (no drop), or weaker by the factor and a smaller drop, or as the single car (eff 1, lam 1).
const HYP = { pairDrop: TRUTH, noDrop: { ...TRUTH, eff: 0.9914, lam: 0 }, bigDrop: { ...TRUTH, eff: 1, lam: 0.39 }, single: { ...TRUTH, eff: 1, lam: 1 } };
function distance(run, a, b) {
    const sa = simulate(run, a), sb = simulate(run, b); let q = 0, mx = 0, n = 0;
    for (const [t, va] of sa) { const vb = sb.get(t); if (vb === undefined) continue; q += (va - vb) ** 2; mx = Math.max(mx, Math.abs(va - vb)); n++; }
    return [Math.sqrt(q / n), mx];
}
if (process.argv[1] && process.argv[1].endsWith("pair_plan.mjs") && process.argv[2] === "discriminate") {
    const pairs = [["pairDrop", "noDrop"], ["pairDrop", "bigDrop"], ["noDrop", "bigDrop"]];
    console.log("rms / max difference of the predicted speed [m/s] between hypotheses, per experiment (closed loop on the first hypothesis of the pair)");
    console.log("experiment".padEnd(26) + pairs.map((p) => p.join(" vs ").padEnd(24)).join(""));
    const rows = EXP.map((e) => ({ id: e.id, d: pairs.map(([x, y]) => distance(synth(e, HYP[x]), HYP[x], HYP[y])) })).sort((u, v) => v.d[0][0] - u.d[0][0]);
    for (const r of rows) console.log(r.id.padEnd(26) + r.d.map(([q, m]) => `${q.toFixed(3)} / ${m.toFixed(3)}`.padEnd(24)).join(""));
    process.exit(0);
}
if (process.argv[1] && process.argv[1].endsWith("pair_plan.mjs")) {
    const [cmd, a1, a2] = process.argv.slice(2);
    if (cmd === "table") {
        // The experiment table of a pair from data/pair_config.json (single-car parameters and vtop): the equilibrium-speed levels, the checks.
        const W = 0.5, K = P.A.Sc * P.A.slope + P.B.Sc * P.B.slope, k = P.A.k + P.B.k, vtop = CONFIG.vtop;
        // The drive of the pair from the plateau speeds of the one-car runs (flow step 0; e = 1, wA = 0.5 when they are not measured). Model: v' = wA (e K_A m_A - kA v) + (1 - wA) (e K_B m_B - kB v) - k2 v^2,
        // so a plateau satisfies  e wA K_A m_A = (wA kA + wB kB) v_A + k2 v_A^2  (and B alike). Solving the two plateaus gives e and wA (the mass fraction of car A) by a fixed-point iteration.
        const KA0 = P.A.Sc * P.A.slope, KB0 = P.B.Sc * P.B.slope;
        const plateau = (car) => {
            const f = path.join(DATA, "twocar", `pf_drive_only${car}_f60`, `${car}.csv`), prog = EXP.find((e) => e.id === `drive_only${car}_f60`);
            if (!fs.existsSync(f) || !prog) return null;
            const rows = fs.readFileSync(f, "utf8").trim().split("\n").slice(1).map((l) => l.split(",")).filter((c) => +c[10] === 1 && Math.abs(+c[7]) > 0), tail = rows.slice(-600);
            return { m: prog.segs[0].m[car === "A" ? 0 : 1], v: tail.reduce((s, c) => s + Math.abs(+c[6]), 0) / tail.length };
        };
        const pA = plateau("A"), pB = SINGLE ? null : plateau("B");
        let e = 1, wA = SINGLE ? 1 : 0.5;
        if (SINGLE && pA) e = (P.A.k * pA.v + K2 * pA.v * pA.v) / (KA0 * pA.m);   // one car: e K_A m = k v + k2 v^2 at the plateau
        if (pA && pB) {
            for (let it = 0; it < 50; it++) {
                const kmix = wA * P.A.k + (1 - wA) * P.B.k, X = (kmix * pA.v + K2 * pA.v * pA.v) / (KA0 * pA.m), Y = (kmix * pB.v + K2 * pB.v * pB.v) / (KB0 * pB.m);
                e = X + Y; wA = X / (X + Y);
            }
        }
        // --guard: a drive e that differs from the single-car K by more than 20%, or a mass fraction outside 0.3 - 0.7, means that the single-car parameters do not describe the vehicle as it stands (equipment, wiring): the flow ends here (exit 5)
        if (process.argv.includes("--guard") && (e < 0.8 || e > 1.2 || (!SINGLE && (wA < 0.3 || wA > 0.7)))) { console.log(`GUARD: drive e ${e.toFixed(3)}, mass fraction of A ${wA.toFixed(3)} (outside 0.8 - 1.2 / 0.3 - 0.7)`); process.exit(5); }
        const kmixE = wA * P.A.k + (1 - wA) * P.B.k, mEq = (v) => (kmixE * v + K2 * v * v) / (e * (wA * KA0 + (1 - wA) * KB0)), mAcc = 1 / (e * (wA * KA0 + (1 - wA) * KB0));
        const seg = (len, vend, cancel, m, b) => ({ len, vend, cancel, m: [m, m], b });
        const out = [];
        const KA = KA0, KB = KB0, mOne = (K1, v) => SINGLE ? (P.A.k * v + K2 * v * v) / K1 : ((P.A.k + P.B.k) / 2 * v + K2 * v * v) / (0.5 * K1);   // motor of one car (the other car 0, no cancel) for the equilibrium speed v
        for (const [car, K1] of [["A", KA], ["B", KB]].filter(([c]) => CARS.includes(c))) out.push({ id: `drive_only${car}_f60`, role: "fit", targets: ["eff", "wA"], note: `${car} 車だけに一定のモーター（相殺なし。もう片方は 0）を 80 秒かける。平衡速度は約 ${(0.6 * vtop).toFixed(1)} m/s（vtop の 0.6）。駆動の弱さが車ごとに別れるかを分ける`, segs: [{ len: 4800, vend: +(vtop + 1).toFixed(1), cancel: false, m: car === "A" ? [+mOne(K1, 0.6 * vtop).toFixed(4), 0] : [0, +mOne(K1, 0.6 * vtop).toFixed(4)], b: [0, 0] }] });
        for (const f of [0.24, 0.48, 0.72, 0.83, 0.94, 0.99]) out.push({ id: `terminal_f${Math.round(f * 100)}`, role: "fit", targets: ["eff", "lam"], note: `両車に一定のモーター（相殺なし）を 80 秒かける。平衡速度は約 ${(f * vtop).toFixed(1)} m/s（vtop の ${f}）。速度が vtop + 1 に達したら区間を終える`, segs: [{ ...seg(4800, vtop + 1, false, +mEq(f * vtop).toFixed(4), [0, 0]) }] });
        out.push({ id: "coast", role: "fit", targets: ["kappa"], note: "0.92 vtop まで加速したあと、モーターもブレーキも 0 で惰行する", segs: [seg(4800, +(0.92 * vtop).toFixed(1), true, +mAcc.toFixed(4), [0, 0]), seg(4800, -1.5, false, 0, [0, 0])] });
        const brk = (b, vFrac, car = "A") => [seg(4800, +(vFrac * vtop).toFixed(1), true, +mAcc.toFixed(4), [0, 0]), { ...seg(4800, -3, true, 0, car === "A" ? [b, 0] : [0, b]) }];
        out.push({ id: "brake_cancelA_0.05", role: SINGLE ? "check" : "fit", targets: ["phi"], note: "0.65 vtop で両車を相殺のモーターにして、A 車だけにブレーキ 0.05", segs: brk(0.05, 0.65) });
        for (const car of CARS) for (const b of [0.0085, 0.0105]) out.push({ id: `brake_dz${car}_${b}`, role: "check", targets: ["beta"], note: `0.79 vtop から ${car} 車だけにブレーキ ${b}。${car} 車の不感帯の境の位置`, segs: brk(b, 0.79, car) });
        out.push({ id: "drive_high_a1", role: "fit", targets: ["eff", "lam"], note: "常用の領域の確認: 相殺に 1 m/s2 の加速を足して 0.98 vtop まで加速する", segs: [seg(4800, +(0.98 * vtop).toFixed(1), true, +mAcc.toFixed(4), [0, 0]), seg(900, 0, true, 0, [0, 0])] });
        for (const car of CARS) out.push({ id: `brake_cancel${car}_0.08`, role: SINGLE ? "check" : "fit", targets: ["phi"], note: `0.79 vtop で両車を相殺のモーターにして、${car} 車だけに強いブレーキ 0.08。使用の条件（抵抗相殺は常に ON）での強いブレーキの確認`, segs: brk(0.08, 0.79, car) });
        for (const car of CARS) out.push({ id: `brake_only${car}_0.08`, role: "info", targets: ["brake"], note: `0.79 vtop から ${car} 車だけに強いブレーキ 0.08（モーター 0）。使用の条件ではないので、結果に載せるが判定に入れない`, segs: [seg(4800, +(0.79 * vtop).toFixed(1), true, +mAcc.toFixed(4), [0, 0]), { ...seg(4800, -2, false, 0, car === "A" ? [0.08, 0] : [0, 0.08]) }] });
        const file = { note: `pair_plan.mjs table が data/pair_config.json（vtop ${vtop}）から作った実験表。segs: len=区間の最長 tick、vend=区間の終わりの速度（>0 で |v| がこれ以上、<0 でこれ以下、0 で時間のみ）、cancel=抵抗相殺を重ねるか、m=相殺に足す各車の追加モーター（+x 向きを正）、b=各車のブレーキ。各実験の最後に、停止のブレーキが付く。role: fit=当てはめに使う、check=当てはめず予測を確かめる、info=結果に載せるだけ`, experiments: out };
        const target = process.argv.includes("--write") ? new URL("./pair_experiments.json", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1") : new URL("./pair_experiments.generated.json", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
        fs.writeFileSync(target, JSON.stringify(file, null, 1)); console.log(`wrote ${target} (${out.length} experiments)`);
        for (const x of out.filter((x) => x.role === "fit")) console.log(`${x.id}: motor ${x.segs[0].m.join(" / ")}  (e ${e.toFixed(3)}, mass fraction of A ${wA.toFixed(3)})`);
        process.exit(0);
    }
    if (cmd === "program") { const e = EXP.find((x) => x.id === a1); if (!e) { console.error("no experiment", a1); process.exit(1); } console.log(JSON.stringify(programs(e, +a2))); }
    else {
        const fit = fitSetColumns(); const synthCols = new Map(EXP.map((e) => [e.id, colsOf(e.id, synth(e, TRUTH))]));
        if (cmd === "baseline") { show(`the ${fit.length} fit runs`, standardErrors(fit)); show(`all ${EXP.length} experiments of the plan`, standardErrors([...synthCols.values()])); show(`the fit runs + all experiments`, standardErrors([...fit, ...synthCols.values()])); }
    }
}
