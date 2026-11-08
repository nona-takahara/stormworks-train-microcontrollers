#!/usr/bin/env node
// ビークルXMLの中のマイコンを取り出し、storm-mcl で sw-net に起こす。
// 生のXMLを人が読まずに済むよう、取り出しから検査までを一気に流し、結果の要約だけを出す。
// 出力はすべて --out のディレクトリに作る。リポジトリには何も置かない。
//
// 使い方:
//   node extract.mjs <vehicle> <name | --at body,x,y,z> --out <dir>
//   <vehicle> は vehicles/ からの相対パス(例: CHUSO2000/CHUSO2000_2001)。拡張子は省ける。
//   マイコンはビークル内の名前(完全一致)か、--at の位置で指す。
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseVehicleXml, serializeMicrocontrollerXml } from "@sw-file-lib/xml";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const mcl = path.join(repoRoot, "node_modules", "storm-microcontroller-language", "dist", "cli", "main.js");

function fail(message) {
    console.error(`[error] ${message}`);
    process.exit(1);
}

const args = process.argv.slice(2);
const outIndex = args.indexOf("--out");
if (outIndex < 0 || !args[outIndex + 1]) fail("--out <dir> is required (use the scratchpad directory)");
const outDir = path.resolve(args[outIndex + 1]);
args.splice(outIndex, 2);
const atIndex = args.indexOf("--at");
let at;
if (atIndex >= 0) {
    at = (args[atIndex + 1] ?? "").split(",").map(Number);
    if (at.length !== 4 || at.some((n) => !Number.isFinite(n))) fail("--at needs body,x,y,z");
    args.splice(atIndex, 2);
}
const [vehicleArg, name] = args;
if (!vehicleArg || (!name && !at)) fail("usage: extract.mjs <vehicle> <name | --at body,x,y,z> --out <dir>");

const id = vehicleArg.replace(/\\/gu, "/").replace(/\.xml$/u, "");
if (id.split("/").some((s) => s === "" || s === "." || s === "..") || /^[A-Za-z]:/u.test(id)) {
    fail(`vehicle must be a relative path under vehicles/: ${vehicleArg}`);
}
const vehiclePath = path.join(repoRoot, "vehicles", `${id}.xml`);
if (!fs.existsSync(vehiclePath)) fail(`not found: ${vehiclePath}`);

const vehicle = parseVehicleXml(new Uint8Array(fs.readFileSync(vehiclePath)));
const found = [];
for (const body of vehicle.bodies ?? []) {
    for (const component of body.components ?? []) {
        const definition = component.o?.microprocessor_definition;
        if (!definition) continue;
        const vp = [component.o.vp?.x ?? 0, component.o.vp?.y ?? 0, component.o.vp?.z ?? 0];
        found.push({ body: Number(body.unique_id), vp, definition });
    }
}
const matches = at
    ? found.filter((m) => m.body === at[0] && m.vp.every((v, i) => v === at[i + 1]))
    : found.filter((m) => m.definition.name === name);
if (matches.length === 0) {
    fail(`no microcontroller matched. names in this vehicle: ${[...new Set(found.map((m) => m.definition.name))].join(" | ")}`);
}
const target = matches[0];
const variants = new Set(matches.map((m) => JSON.stringify(m.definition))).size;

const base = target.definition.name.replace(/[^A-Za-z0-9._-]+/gu, "_");
fs.mkdirSync(outDir, { recursive: true });
const xmlPath = path.join(outDir, `${base}.xml`);
fs.writeFileSync(xmlPath, serializeMicrocontrollerXml(target.definition));

const run = (...argv) => spawnSync(process.execPath, [mcl, ...argv], { encoding: "utf8" });
const dslDir = path.join(outDir, `${base}_dsl`);
const imported = run("xml2dsl", xmlPath, "--out-dir", dslDir);
if (imported.status !== 0) fail(`xml2dsl failed:\n${imported.stdout}${imported.stderr}`);

// sourceName に一時ファイルの絶対パスが入るので、ほかのプロジェクトと同じ単体のファイル名に直す。
for (const file of ["project.json", "main.sw-mcl"]) {
    const p = path.join(dslDir, file);
    if (!fs.existsSync(p)) continue;
    const json = JSON.parse(fs.readFileSync(p, "utf8"));
    json.sourceName = `${base}.xml`;
    fs.writeFileSync(p, `${JSON.stringify(json, null, 2)}\n`);
}
const projectJson = path.join(dslDir, "project.json");
const checks = {
    "check-dsl": run("check-dsl", projectJson),
    "typecheck-dsl": run("typecheck-dsl", projectJson),
};

const components = target.definition.group?.components ?? [];
const typeCounts = {};
for (const c of components) typeCounts[c.type] = (typeCounts[c.type] ?? 0) + 1;
const lua = components.filter((c) => typeof c.object?.script === "string").length;
const nodes = target.definition.nodes?.length ?? 0;
// 個体ごとに違う property の値。抽出物にはビークルの値がそのまま入る。
const PROPERTY_VALUE_ATTRIBUTES = new Map([[34, ["v"]], [19, ["v"]], [33, ["v"]], [58, ["v"]], [20, ["i"]]]);
const propertyValues = components
    .filter((c) => PROPERTY_VALUE_ATTRIBUTES.has(c.type))
    .flatMap((c) => PROPERTY_VALUE_ATTRIBUTES.get(c.type)
        .filter((attribute) => c.object[attribute] !== undefined)
        .map((attribute) => `${c.object.n ?? c.object.name} ${attribute}=${JSON.stringify(c.object[attribute])}`));
const warnings = `${imported.stdout}${imported.stderr}`.split(/\r?\n/u).filter((l) => /warning/iu.test(l));

console.log(`name: ${target.definition.name}`);
console.log(`source: ${id}.xml  body ${target.body} vp [${target.vp}]  instances ${matches.length} (distinct definitions ${variants})`);
console.log(`size: ${target.definition.width}x${target.definition.length}  nodes: ${nodes}  components: ${components.length}  Lua: ${lua}`);
console.log(`component types: ${JSON.stringify(typeCounts)}`);
console.log(`property values in this extract: ${propertyValues.length ? propertyValues.join("; ") : "none"}`);
if (nodes === 0 && components.length === 0) console.log("EMPTY: ノード・部品・Lua のいずれもない。リポジトリには置かない。");
for (const [label, result] of Object.entries(checks)) console.log(`${label}: ${result.status === 0 ? "passed" : `FAILED\n${result.stdout}${result.stderr}`}`);
for (const w of warnings) console.log(w.replace(outDir, "<out>"));
console.log(`xml: ${xmlPath}`);
console.log(`dsl: ${dslDir}`);
