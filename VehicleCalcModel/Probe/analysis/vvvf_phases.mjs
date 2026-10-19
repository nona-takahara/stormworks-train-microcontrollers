// The model - measured difference of a vvvf run, phase by phase (power notch / brake notch), for the old model (THETA0) and the model of record (THETA1).
//   node vvvf_phases.mjs <run name, e.g. vvvf_new_1>
import fs from "node:fs";
import path from "node:path";
import { loadRun, simulate, THETA0, THETA2 as THETA1 } from "./fwd.mjs";

const name = process.argv[2], tag = name.slice("vvvf_".length), data = path.join(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), "../data");
const log = JSON.parse(fs.readFileSync(path.join(data, "vvvf", `run_${tag}`, "commands.json"), "utf8")).log, res = JSON.parse(fs.readFileSync(path.join(data, "vvvf", `run_${tag}`, "result.json"), "utf8"));
const run = loadRun(name), sims = [simulate(run, THETA0), simulate(run, THETA1)], t0 = res.t0;
const label = (x) => (x.pN ? `P${x.pN}` : x.bN ? `B${x.bN}` : "coast");
console.log(`${name}: model - measured speed (mean of the two cars) by phase; old model | model of record   [m/s]  (rms / max / mean)`);
let i = 0;
while (i < log.length) {
  let j = i; while (j < log.length && label(log[j]) === label(log[i])) j++;
  if (j - i >= 30) {
    const st = sims.map(() => ({ s: 0, mx: 0, b: 0, n: 0 }));
    for (let k = i; k < j; k++) { const t = t0 + log[k].t, r = run.mean.get(t); if (r === undefined) continue; sims.forEach((sim, q) => { const e = (sim.get(t) ?? NaN) - r; if (e === e) { st[q].s += e * e; st[q].mx = Math.max(st[q].mx, Math.abs(e)); st[q].b += e; st[q].n++; } }); }
    const f = (x) => `${Math.sqrt(x.s / x.n).toFixed(3)} / ${x.mx.toFixed(3)} / ${(x.b / x.n >= 0 ? "+" : "") + (x.b / x.n).toFixed(3)}`;
    console.log(`${label(log[i]).padEnd(5)} ${(run.mean.get(t0 + log[i].t) ?? 0).toFixed(1).padStart(5)}->${(run.mean.get(t0 + log[j - 1].t) ?? 0).toFixed(1).padStart(5)} m/s ${String(j - i).padStart(5)} ticks | ${f(st[0])} | ${f(st[1])}`);
  }
  i = j;
}
