// Usage: node fit_fwd.mjs [free params] [fixed/initial values as JSON]; ITER=n sets the number of rounds (default 14).
// Fits theta of fwd.mjs on the isolation runs (cancel holds, ftest, creep, decel paths, step runs) by a coordinate search, and reports the held-out runs
// (use*, verify*, vvvf*) before and after. Usage: node fit_fwd.mjs [free params, comma separated; default all]
import { corpus, score, category, THETA0, THETA1 } from "./fwd.mjs";

const free = (process.argv[2] ?? "w,beta,eff,lam,phi,kappa,k2").split(",");
const runs = corpus("."), FIT = new Set(["cancel", "decel", "step"]);
const fit = runs.filter((r) => FIT.has(category(r.name))), held = runs.filter((r) => !FIT.has(category(r.name)));
const cost = (th, set) => Math.sqrt(set.reduce((s, r) => s + score(r, th).rms ** 2, 0) / set.length);
const step0 = { w: 0.01, beta: 0.03, eff: 0.02, lam: 0.3, phi: 0.3, kappa: 0.02, k2: 4e-5, dscale: 0.5 }, bounds = { lam: [0, 1.5], phi: [0, 4], k2: [-2e-4, 3e-4], dscale: [0, 12] };
let th = { ...(process.env.START === "1" ? THETA1 : THETA0), ...JSON.parse(process.argv[3] ?? "{}") }, steps = { ...step0 }, best = cost(th, fit);
console.log(`fit set ${fit.length} runs, held-out ${held.length} runs; the old model: fit rms ${best.toFixed(4)}`);
const ITER = +(process.env.ITER ?? 14);
for (let it = 0; it < ITER; it++) {
  let improved = false;
  for (const k of free) for (const sgn of [1, -1]) {
    const t2 = { ...th, [k]: th[k] + sgn * steps[k] }; if (bounds[k] && (t2[k] < bounds[k][0] || t2[k] > bounds[k][1])) continue;
    const c = cost(t2, fit); if (c < best - 1e-6) { best = c; th = t2; improved = true; }
  }
  if (!improved) for (const k of free) steps[k] /= 2;
  if (it % 5 === 4 || it === ITER - 1) console.log(`it ${it}: fit rms ${best.toFixed(4)}  theta`, JSON.stringify(Object.fromEntries(Object.entries(th).map(([k, v]) => [k, +v.toPrecision(4)]))));
}
const byCat = (set, t) => { const c = {}; for (const r of set) { const s = score(r, t); (c[category(r.name)] ??= []).push(s); } return c; };
const show = (label, t) => { for (const [setName, set] of [["fit", fit], ["held-out", held]]) { const c = byCat(set, t); console.log(label.padEnd(5), setName.padEnd(8), Object.entries(c).map(([k, rs]) => `${k} rms ${(rs.reduce((a, r) => a + r.rms, 0) / rs.length).toFixed(3)} max ${Math.max(...rs.map((r) => r.max)).toFixed(3)} bias ${(rs.reduce((a, r) => a + r.bias, 0) / rs.length).toFixed(3)}`).join(" | ")); } };
show("old", THETA0); show("new", th);
console.log("theta", JSON.stringify(th));
