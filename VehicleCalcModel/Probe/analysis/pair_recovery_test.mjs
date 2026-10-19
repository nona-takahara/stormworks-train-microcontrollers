// A simulation test of the identification procedure (PAIR_FIT_PLAN.md), not a measurement: for a pair (single-car parameters) and a true model, the runs of the experiment table are
// generated on the model with measurement noise, written in the form of the probe logs, and pair_loop.mjs runs on them in a copy of this folder. It shows whether the flow recovers the
// true values and whether its guards fire. A larger form that contains the true one can be chosen with its extra coefficient at the neutral value (lam = 1); the test asks for the recovered values (eff, wA, dvk, dead zone), not for the form. It cannot show that the eight forms of the table cover a pair of the real game: only a measured pair can.
//   node pair_recovery_test.mjs        runs the cases below (CASES=0,3 for a few of them; one full case takes about 20 minutes)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const HERE = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), DATA = path.join(HERE, "..", "data");
const CASES = [
    { name: "mo1800 + ku2100 (unequal masses)", A: "params_mo1800.json", B: "params_ku2100.json", vtop: 30.5, truth: { eff: 0.995, wA: 0.57, kappa: 0.99, phi: 1.2, dvk: 4 }, dz: 0.0098, want: { eff: 0.995, wA: 0.57, dvk: 4, dz: 0.0098, exit: 0 } },
    { name: "mo2000 + ku2100 (equal masses)", A: "params_mo2000.json", B: "params_ku2100.json", vtop: 30.5, truth: { eff: 0.985, wA: 0.5, kappa: 1, phi: 1, dvk: 8 }, dz: 0.0095, want: { eff: 0.985, wA: 0.5, dvk: 8, dz: 0.0095, exit: 0 } },
    { name: "dead zone below the levels run", A: "params_mo2000.json", B: "params_ku2100.json", vtop: 30.5, truth: { eff: 0.985, wA: 0.5, dvk: 8 }, dz: 0.007, want: { exit: 4 } },
    { name: "a pair at 70% of its single-car drive (wiring fault)", A: "params_mo1800.json", B: "params_ku2100.json", vtop: 30.5, truth: { eff: 0.7, wA: 0.57 }, dz: 0.0098, want: { exit: 5 } },
    // a single car: the config has no "B"
    { name: "single car mo1800", A: "params_mo1800.json", vtop: 30.5, truth: { eff: 0.99, kappa: 0.99, phi: 1.15, dvk: 5 }, dz: 0.0098, promote: true, want: { eff: 0.99, dvk: 5, dz: 0.0098, exit: 0 } },
    { name: "single car, dead zone below the levels run", A: "params_mo2000.json", vtop: 30.5, truth: { eff: 0.99, dvk: 8 }, dz: 0.007, want: { exit: 4 } },
    // the brake weakening phi of a single car is not fitted: the cancel-brake checks notice phi = 1.3 (not 1.15)
    { name: "single car with phi = 1.3 (not fitted)", A: "params_mo1800.json", vtop: 30.5, truth: { eff: 0.99, phi: 1.3 }, dz: 0.0098, want: { exit: 4 } },   // phi = 1.15 passes (case 4), 1.3 trips the check
    { name: "single car at 70% of its drive (wiring fault)", A: "params_ku2100.json", vtop: 30.5, truth: { eff: 0.7 }, dz: 0.0098, want: { exit: 5 } },
];
const rng = (seed) => () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };
const gauss = (r) => Math.sqrt(-2 * Math.log(1 - r())) * Math.cos(2 * Math.PI * r());

const ONLY = process.env.CASES?.split(",").map(Number);   // e.g. CASES=0,1 runs the first two
for (const [ci, c] of CASES.entries()) {
    if (ONLY && !ONLY.includes(ci)) continue;
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "pairtest-")), an = path.join(tmp, "analysis"), dt = path.join(tmp, "data");
    fs.mkdirSync(an); fs.mkdirSync(path.join(dt, "twocar"), { recursive: true });
    for (const f of fs.readdirSync(HERE)) if (/\.(mjs|json)$/.test(f) && f !== "pair_experiments.generated.json") fs.copyFileSync(path.join(HERE, f), path.join(an, f));
    for (const f of [c.A, c.B].filter(Boolean)) fs.copyFileSync(path.join(DATA, f), path.join(dt, f));
    fs.writeFileSync(path.join(dt, "pair_config.json"), JSON.stringify({ vtop: c.vtop, k2: 8e-5, A: { params: c.A, port: 0, log: "", sign: 1 }, ...(c.B ? { B: { params: c.B, port: 0, log: "", sign: -1 } } : {}) }));
    const run = (...args) => spawnSync("node", args, { cwd: an, encoding: "utf8" });
    run("pair_plan.mjs", "table", "--write");
    // the true model: the model of record with the true values, plus the true dead zone
    const gen = `
import fs from "node:fs"; import path from "node:path";
import { synth, programs } from "./pair_plan.mjs"; import { THETA2, SINGLE } from "./fwd.mjs";
const truth = ${JSON.stringify({ ...c.truth, dz: c.dz })}, seed = ${c.name.length * 7919};
const th = { ...THETA2, eff: 1, dvk: undefined, vkp: undefined, dpow: undefined, ...truth };
let s = seed; const r = () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; }; const gauss = () => Math.sqrt(-2 * Math.log(1 - r())) * Math.cos(2 * Math.PI * r());
const E = JSON.parse(fs.readFileSync("pair_experiments.json", "utf8")).experiments;
const ONLYIDS = process.argv[2] === "pilot" ? ["drive_onlyA_f60", "drive_onlyB_f60"] : null;
for (const e of E.filter((x) => !ONLYIDS || ONLYIDS.includes(x.id))) {
  const run = synth(e, th), dir = path.join("..", "data", "twocar", "pf_" + e.id); fs.mkdirSync(dir, { recursive: true });
  const head = "recv_ms,dropped,t,x,y,z,v,motor,brake,batt,state,reason,slip,aux1,aux2";
  const mk = (rows, sign) => { let x = 0, out = [head, "0,0," + (rows[0].t - 5) + ",0,0,0,0,0,0,1,0,0,0,0,0"]; for (const q of rows) { const v = run.mean.get(q.t) ?? 0; x += v / 60; out.push([0, 0, q.t, x.toFixed(2), 0, 0, (sign * v + 0.01 * gauss()).toFixed(3), q.motor.toFixed(5), q.brake.toFixed(5), 1, 1, q.reason, 0, 0, 0].join(",")); } out.push("0,0," + (rows.at(-1).t + 10) + "," + x.toFixed(2) + ",0,0,0,0,0,1,0,0,0,0,0"); return out.join("\\n"); };
  fs.writeFileSync(path.join(dir, "A.csv"), mk(run.A, 1)); if (!SINGLE) fs.writeFileSync(path.join(dir, "B.csv"), mk(run.B, -1));
  fs.writeFileSync(path.join(dir, "programs.json"), JSON.stringify(programs(e, 1)));
}`;
    fs.writeFileSync(path.join(an, "gen.mjs"), gen);
    const g = run("gen.mjs", "pilot"); if (g.status !== 0) { console.log(c.name, "generation failed:", g.stderr.slice(-300)); continue; }
    const t2 = run("pair_plan.mjs", "table", "--write", "--guard");   // the levels from the pilots; the guard ends the flow here
    let l = t2, res = null;
    if (t2.status === 0) {
        const g2 = run("gen.mjs", "all"); if (g2.status !== 0) { console.log(c.name, "generation failed:", g2.stderr.slice(-300)); continue; }
        l = run("pair_loop.mjs");
        try { res = JSON.parse(fs.readFileSync(path.join(dt, "pair_fit_result.json"), "utf8")); } catch { /* the loop stopped before writing */ }
    }
    const got = res ? { form: res.chosenForm, fitRms: res.fitError?.rms, ...res.fitted, dz: res.deadZone?.value, range: res.deadZone?.range, onBound: res.onBound, unbracketed: res.deadZoneUnbracketed } : null;
    const ok = l.status === c.want.exit && (c.want.dvk === undefined || Math.abs(got.dvk - c.want.dvk) < 1) && (!got || got.lam === undefined || Math.abs(got.lam - 1) < 0.05) && (c.want.eff === undefined || Math.abs(got.eff - c.want.eff) < 0.01) && (c.want.wA === undefined || Math.abs(got.wA - c.want.wA) < 0.01) && (c.want.dz === undefined || Math.abs(got.dz - c.want.dz) < 0.0012);
    console.log(`${ok ? "OK  " : "FAIL"} ${c.name}: exit ${l.status} (want ${c.want.exit}); truth ${JSON.stringify({ ...c.truth, dz: c.dz })}; recovered ${JSON.stringify(got)}`);
    if (c.promote && res) {   // write the result back, refit against the promoted parameters: the corrections should be neutral (eff 1, kappa 1, dvk 0)
        const pr = run("promote_single.mjs", path.join("..", "data", c.A), path.join("..", "data", "pair_fit_result.json"), path.join("..", "data", "params_promoted.json"));
        fs.writeFileSync(path.join(dt, "pair_config.json"), JSON.stringify({ vtop: c.vtop, k2: 8e-5, A: { params: "params_promoted.json", port: 0, log: "", sign: 1 } }));
        const l2 = run("pair_loop.mjs"); let r2 = null; try { r2 = JSON.parse(fs.readFileSync(path.join(dt, "pair_fit_result.json"), "utf8")); } catch { /* none */ }
        console.log(`     promoted: ${pr.stdout.trim()}\n     refit against the promoted parameters: exit ${l2.status}, ${JSON.stringify(r2?.fitted)}, dead zone ${r2?.deadZone?.value}`);
    }
    fs.rmSync(tmp, { recursive: true, force: true });
}
