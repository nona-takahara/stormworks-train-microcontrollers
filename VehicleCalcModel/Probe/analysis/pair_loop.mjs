// Fit the drive corrections of the pair on the experiments of role "fit", read the dead zone of the brake, and judge. No step needs a person or a model to decide anything.
//   node pair_loop.mjs      fit on the pf_ runs of role fit, read the dead zone from the runs of role check, judge; result in data/pair_fit_result.json
// The form of the drive drop is chosen by the machine from the table FORMS: each form is fitted on all fit runs but one and scored on the one left out (leave-one-out);
// the form with the smallest mean error is fitted on all fit runs. No older run takes part: the choice rests on the data of this flow only.
// The dead zone of the brake command is read from the brake_dz runs: the boundaries that reproduce every one of them form an interval; its middle is the dead zone of the model.
// Judgement (exit code): a check run (not fitted) passes when the model is within ORACLE_MARGIN of the freely fitted reference (below) on that run. The info runs (conditions outside the use of the pair) are reported and not judged.
// Older runs, when present, are only reported. 0 pass; 4 a check fails, a fitted value sits on a bound, the dead zone is not bracketed or differs between the cars (more runs do not help). pair_plan.mjs --guard ends the flow earlier with 5.
import fs from "node:fs";
import { corpus, score, simulate, category, THETA1, THETA2, SINGLE } from "./fwd.mjs";
const WA = SINGLE ? [] : ["wA"];   // the mass fraction of car A: not fitted for a single car (weight 1)
const PHI = SINGLE ? [] : ["phi"];   // a single car keeps its measured brake weakening (c1 with F(1) = 0, stage 3c of axle2); the cancel-brake runs are checks there

const ORACLE_MARGIN = 0.03, HI_V = 20;
const url = (f) => new URL(f, import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
const exps = JSON.parse(fs.readFileSync(url("./pair_experiments.json"), "utf8")).experiments;
const runs = corpus("."), planRuns = runs.filter((r) => category(r.name) === "plan");
const byRole = (role) => planRuns.filter((r) => exps.find((e) => `pf_${e.id}` === r.name)?.role === role);
const cost = (th, set) => Math.sqrt(set.reduce((s, r) => s + score(r, th).rms ** 2, 0) / set.length);
const hi = (set, t) => { let q = 0, n = 0; for (const r of set) { const sim = simulate(r, t); for (const [tt, vr] of r.mean) { const m = sim.get(tt); if (m !== undefined && Math.abs(vr) >= HI_V) { q += (m - vr) ** 2; n++; } } } return Math.sqrt(q / n); };
const coordinate = (start, free, step, bounds, set) => {
    let th = { ...start }, st = { ...step }, best = cost(th, set);
    for (let it = 0; it < 80; it++) {
        let improved = false;
        for (const k of free) for (const sg of [1, -1]) { const t2 = { ...th, [k]: th[k] + sg * st[k] }; if (bounds[k] && (t2[k] < bounds[k][0] || t2[k] > bounds[k][1])) continue; const c = cost(t2, set); if (c < best - 1e-7) { best = c; th = t2; improved = true; } }
        if (!improved) { for (const k of free) st[k] /= 2; if (Math.min(...free.map((k) => st[k] / step[k])) < 1e-3) break; }
    }
    return th;
};

const info = byRole("info"), fit = byRole("fit"), check = byRole("check");
if (fit.length < 3) { console.log("fewer than 3 runs of role fit"); process.exit(2); }

// the dead zone of the brake command, read per braking car (the brake_dz runs brake one car with a constant small command): on a grid of boundaries, the ones that reproduce every run of
// a car form an interval; the model takes the middle of the intersection of the cars' intervals. Intervals that do not meet (the cars have different dead zones) or that reach the edge
// of the grid (the dead zone lies outside the levels that were run) are flagged, and the flow ends with code 4.
// The forms of the drive drop are not picked one by one: every non-empty subset of {lam, dvk, dpow} is a form (the slope of the drop, the shift of its knee, the power of the excess over the knee;
// the ones not freed stay at the single-car values lam = 1, dvk = 0, dpow = 1), and one knee for both cars (vkp). eff is free in all. A form whose fitted value sits on a bound is not eligible.
const base = { ...THETA2, eff: 1, lam: 1, vkp: undefined, dvk: undefined, dpow: undefined };
// A single car keeps the drop model of axle2.mjs (1 - gamma * max(0, |v| - vk), power 1): only the forms that can be written back into gamma and vk (lam, dvk, lam + dvk) take part.
const SUBSETS = (SINGLE ? [["lam"], ["dvk"], ["lam", "dvk"]] : [["lam"], ["dvk"], ["dpow"], ["lam", "dvk"], ["lam", "dpow"], ["dvk", "dpow"], ["lam", "dvk", "dpow"]]);
const INIT = { lam: 0.5, dvk: 8, dpow: 1.5 }, STEP = { phi: 0.2, kappa: 0.01, wA: 0.03, eff: 0.01, lam: 0.2, dvk: 3, dpow: 0.3, vkp: 2 }, BOUNDS = { phi: [0, 4], kappa: [0.9, 1.1], wA: [0.2, 0.8], lam: [0, 3], dvk: [-5, 30], dpow: [0.5, 8], vkp: [0, 40] };
const FORMS = Object.fromEntries([...SUBSETS.map((sub) => [sub.join("+"), { free: ["eff", ...WA, "kappa", ...PHI, ...sub], start: { ...base, eff: 0.995, wA: 0.5, ...Object.fromEntries(sub.map((k) => [k, INIT[k]])) }, step: STEP, bounds: BOUNDS }]),
    ...(SINGLE ? [] : [["common-knee", { free: ["eff", ...WA, "kappa", ...PHI, "vkp"], start: { ...base, eff: 0.995, wA: 0.5, vkp: 20 }, step: STEP, bounds: BOUNDS }]])]);
const onBoundOf = (F, t) => F.free.filter((k) => F.bounds[k] && F.bounds[k].some((b) => Math.abs(t[k] - b) < 2e-3 * (F.bounds[k][1] - F.bounds[k][0])));   // within 0.2% of the range of a bound
const fullFits = Object.fromEntries(Object.entries(FORMS).map(([name, F]) => [name, coordinate(F.start, F.free, F.step, F.bounds, fit)]));
const eligible = Object.keys(FORMS).filter((name) => onBoundOf(FORMS[name], fullFits[name]).length === 0);
// the fit on all runs is the start of every leave-one-out fit
const loo = Object.fromEntries(eligible.map((name) => { const F = FORMS[name]; return [name, fit.map((r, i) => score(r, coordinate(fullFits[name], F.free, F.step, F.bounds, fit.filter((_, j) => j !== i))).rms)]; }));
const looMean = Object.fromEntries(Object.entries(loo).map(([k, v]) => [k, +(v.reduce((a, b) => a + b, 0) / v.length).toFixed(4)]));
const chosen = eligible.reduce((a, b) => (looMean[b] < looMean[a] ? b : a)), F = FORMS[chosen];
const th = fullFits[chosen];
const dzRuns = byRole("check").filter((r) => r.name.startsWith("pf_brake_dz"));
let dz = null, dzRange = null, dzUnbracketed = false, dzPerCar = null, dzMismatch = false;
if (dzRuns.length >= 2) {
    // the scan runs on the drive fitted from the fit runs (which have no brake in them but the stop at 0.5), not on the check runs, so a drive that is too strong or weak does not read as a dead zone
    const neutral = { ...th }, grid = Array.from({ length: 33 }, (_, i) => 0.002 + i * 0.0005);
    const interval = (set) => { const cs = grid.map((d) => set.reduce((q, r) => q + score(r, { ...neutral, dz: d }).rms, 0) / set.length), best = Math.min(...cs), ok = grid.filter((_, i) => cs[i] <= best + 0.02); return [Math.min(...ok), Math.max(...ok)]; };
    const cars = [...new Set(dzRuns.map((r) => r.name.slice("pf_brake_dz".length, "pf_brake_dz".length + 1)))];
    dzPerCar = Object.fromEntries(cars.map((c) => [c, interval(dzRuns.filter((r) => r.name.startsWith(`pf_brake_dz${c}_`)))]));
    dzRange = [Math.max(...Object.values(dzPerCar).map((v) => v[0])), Math.min(...Object.values(dzPerCar).map((v) => v[1]))];
    dzMismatch = dzRange[0] > dzRange[1];
    dz = dzMismatch ? null : (dzRange[0] + dzRange[1]) / 2;
    dzUnbracketed = Object.values(dzPerCar).some((v) => v[0] <= grid[0] || v[1] >= grid.at(-1));
}

if (dz !== null) th.dz = dz;
const onBound = onBoundOf(F, th);   // empty by the choice; kept in the result
const rejected = Object.keys(FORMS).filter((name) => !eligible.includes(name));

// scoring
const old = runs.filter((r) => category(r.name) !== "plan");
const rep = (set, t) => (set.length ? { rms: +cost(t, set).toFixed(4), max: +Math.max(...set.map((r) => score(r, t).max)).toFixed(3) } : null);
const cats = {}; for (const r of old) (cats[category(r.name)] ??= []).push(r);
const out = { chosenForm: chosen, leaveOneOut: looMean, rejectedOnBound: rejected, deadZone: dzPerCar === null ? null : { value: dz === null ? null : +dz.toFixed(4), range: dzRange, perCar: dzPerCar },
    fitted: Object.fromEntries(F.free.map((k) => [k, +th[k].toPrecision(4)])), fitRuns: fit.map((r) => r.name), fitError: rep(fit, th),
    olderRuns: old.length ? { n: old.length, fitted: rep(old, th), record: rep(old, THETA1), highSpeedRms: { fitted: +hi(old, th).toFixed(4), record: +hi(old, THETA1).toFixed(4) } } : null,
    perCategory: Object.fromEntries(Object.entries(cats).map(([c, rs]) => [c, { n: rs.length, fitted: rep(rs, th).rms, record: rep(rs, THETA1).rms }])),
    check: check.map((r) => ({ run: r.name, fitted: +score(r, th).rms.toFixed(4) })),
    info: info.map((r) => ({ run: r.name, fitted: +score(r, th).rms.toFixed(4), max: +score(r, th).max.toFixed(3) })) };   // reported, not judged
// The reference of the judgement: the freely fitted model (eff, lam, phi, kappa, k2 and the mass fraction wA, all free) on the fit and check runs of this flow, so that a pair whose error floor is high
// is not judged by a fixed number. A check run passes when the model is within ORACLE_MARGIN of the reference on that run. The info runs take no part.
const oracleSet = [...fit, ...check];
const ORACLE_FREE = ["eff", "lam", "phi", "kappa", "k2", ...WA], ORACLE_STEP = { eff: 0.01, lam: 0.2, phi: 0.2, kappa: 0.01, k2: 3e-5, wA: 0.02 }, ORACLE_BOUNDS = { lam: [0, 1.5], phi: [0, 4], k2: [-2e-4, 3e-4] };
const oracleTheta = coordinate({ ...base, ...(dz === null ? {} : { dz }), eff: th.eff, wA: th.wA, kappa: th.kappa, phi: th.phi, k2: THETA2.k2, lam: 1 }, ORACLE_FREE, ORACLE_STEP, ORACLE_BOUNDS, oracleSet);
out.oracle = { theta: Object.fromEntries(ORACLE_FREE.map((k) => [k, +oracleTheta[k].toPrecision(4)])), rms: +cost(oracleTheta, oracleSet).toFixed(4), procedureRms: +cost(th, oracleSet).toFixed(4) };
out.check = out.check.map((c) => ({ ...c, oracle: +score(check.find((r) => r.name === c.run), oracleTheta).rms.toFixed(4) }));
const failed = out.check.filter((c) => c.fitted > c.oracle + ORACLE_MARGIN).map((c) => c.run);
out.checkFailed = failed; out.onBound = onBound; out.deadZoneUnbracketed = dzUnbracketed; out.deadZoneMismatch = dzMismatch;
out.pass = failed.length === 0 && onBound.length === 0 && !dzUnbracketed && !dzMismatch;
console.log(JSON.stringify(out, null, 1)); fs.writeFileSync(url(`../data/pair_fit_result.json`), JSON.stringify({ theta: th, ...out }, null, 1));
process.exit(out.pass ? 0 : 4);   // on a bound, an unbracketed dead zone or cars with different dead zones: 4 (more fit runs do not help)
