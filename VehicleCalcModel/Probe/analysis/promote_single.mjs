// Writes the result of the single-car block (pair_loop.mjs on a config without "B") back into the single-car parameters, as a NEW file (the old file is not touched):
//   slope <- eff * slope      (the drive scale; Sc stays with the s(t) fit of axle2 stage 3a)
//   k     <- kappa * k        (the resistance)
//   gamma <- lam * gamma, vk <- vk + dvk   (the drop of the drive; only the forms of axle2's drop model, power 1)
//   dz                         (the dead zone of the brake command; the constant 0.0113 of axle2.mjs / scenario.py / simulate.mjs is to be read from here: not done yet)
// phi is not written: a single car keeps c1 with F(1) = 0 (axle2 stage 3c).
//   node promote_single.mjs <params_in.json> <pair_fit_result.json> <params_out.json>
import fs from "node:fs";
const [, , inFile, resFile, outFile] = process.argv;
if (!inFile || !resFile || !outFile) { console.error("usage: node promote_single.mjs <params_in.json> <pair_fit_result.json> <params_out.json>"); process.exit(1); }
if (inFile === outFile) { console.error("the output must be a new file"); process.exit(1); }
const P = JSON.parse(fs.readFileSync(inFile, "utf8")), R = JSON.parse(fs.readFileSync(resFile, "utf8")), f = R.fitted ?? {}, out = { ...P };
if (!R.pass) console.error("note: the result did not pass (pair_fit_result.json: pass = false)");
if (f.eff !== undefined) out.slope = P.slope * f.eff;
if (f.kappa !== undefined) out.k = P.k * f.kappa;
if (f.lam !== undefined) out.gamma = P.gamma * f.lam;
if (f.dvk !== undefined) out.vk = P.vk + f.dvk;
if (R.deadZone?.value != null) out.dz = R.deadZone.value;
out.provenance = { from: inFile, fitted: f, chosenForm: R.chosenForm, pass: R.pass, note: "slope, k, gamma, vk, dz written by promote_single.mjs from the equilibrium block (SINGLE_FIT_PLAN.md)" };
fs.writeFileSync(outFile, JSON.stringify(out, null, 1));
console.log(`wrote ${outFile}: slope ${P.slope.toFixed(4)} -> ${out.slope.toFixed(4)}, k ${P.k.toFixed(5)} -> ${out.k.toFixed(5)}, gamma ${P.gamma.toExponential(3)} -> ${out.gamma.toExponential(3)}, vk ${P.vk.toFixed(2)} -> ${out.vk.toFixed(2)}, dz ${out.dz ?? "-"}`);
