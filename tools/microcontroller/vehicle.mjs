// ビークルXMLの中のマイコンを、本リポジトリのプロジェクトから作ったマイコンに差し替える。
// 流れは二段で、vehicle-swapが手元(vehicle-out/)へ書き出し、vehicle-installが
// バックアップを取ってゲーム側へ置く。ゲーム側へ書くのはvehicle-installだけである。
// 個体ごとに違う値(Door Sideのドロップダウンのiなど)はプロジェクトに持たせず、
// 対応表(<名前>.map.json)の set から差し替えの際に注入する。
// 正本のビークルはリポジトリ内のvehicles/で、vehicle-swapは読むだけ。結果はvehicle-out/に出す。
import fs from "node:fs";
import path from "node:path";
import {
    parseMicrocontrollerXml,
    parseVehicleXml,
    serializeVehicleXml,
} from "@sw-file-lib/xml";
import { discoverProjectJsonProjects } from "./discovery.mjs";
import { installWithRollback, timestamp, withGeneratedXml } from "./operations.mjs";

// 個体ごとに違う値を持つ property 部品(type)と、その値の属性。
// ドロップダウンの値は選択番号 i で、v は扱わない(意味が未確認)。
// 属性が省略されているときは、ゲームの既定値(数値は0、トグルは false、ドロップダウンは0番)を表す。
const PROPERTY_VALUE_ATTRIBUTES = new Map([
    [34, ["v"]], // 数値
    [19, ["v"]], // スライダー
    [33, ["v"]], // トグル
    [58, ["v"]], // テキスト
    [20, ["i"]], // ドロップダウン
]);

// ラベルは、ドロップダウンでは name、ほかの property では n。
const labelOf = (object) => object?.n ?? object?.name;

const propertyComponents = (definition) =>
    (definition.group?.components ?? []).filter((c) => PROPERTY_VALUE_ATTRIBUTES.has(c.type) && labelOf(c.object));

// ビークルの指定は vehicles/ からの相対パス(例: CHUSO2000/CHUSO2000_2001)。拡張子は省いてよい。
// 系列ごとのディレクトリに、ビークルのXML・PNG・対応表(<名前>.map.json)を平置きする。
// ゲーム側は平らなので、設置先のファイル名はパスの最後の部分だけを使う。
export function resolveVehicle(config, name) {
    const id = name.replace(/\\/gu, "/").replace(/\.xml$/u, "");
    const segments = id.split("/");
    // vehicles/ の外を指せる指定(絶対パス、..、空の区間)は受け付けない。
    if (segments.some((s) => s === "" || s === "." || s === "..") || /^[A-Za-z]:/u.test(id)) {
        throw new Error(`Vehicle must be a relative path under vehicles/: ${name}`);
    }
    return {
        id,
        fileName: `${segments.at(-1)}.xml`,
        source: path.join(config.vehicleSourceDir, ...segments.slice(0, -1), `${segments.at(-1)}.xml`),
        map: path.join(config.vehicleSourceDir, ...segments.slice(0, -1), `${segments.at(-1)}.map.json`),
        out: path.join(config.vehicleOutDir, ...segments.slice(0, -1), `${segments.at(-1)}.xml`),
    };
}

const vpOf = (component) => {
    const vp = component.o?.vp ?? {};
    return [vp.x ?? 0, vp.y ?? 0, vp.z ?? 0];
};

// ビークル内のマイコンを、所属するbodyのunique_idと位置(vp)つきで列挙する。
export function findMicrocontrollers(vehicle) {
    const found = [];
    for (const body of vehicle.bodies ?? []) {
        for (const component of body.components ?? []) {
            const definition = component.o?.microprocessor_definition;
            if (definition) found.push({ body: Number(body.unique_id), vp: vpOf(component), component, definition });
        }
    }
    return found;
}

const samePosition = (item, entry) =>
    item.body === Number(entry.body) && item.vp.every((value, index) => value === entry.vp[index]);

function locate(microcontrollers, entry) {
    const matches = microcontrollers.filter((item) => samePosition(item, entry));
    if (matches.length !== 1) {
        throw new Error(`Expected one microcontroller at body ${entry.body} vp [${entry.vp}], found ${matches.length}`);
    }
    return matches[0];
}

// 対応表は、ビークル内のマイコンのエントリの配列。ファイルが無ければ空。
export function readMap(file, fsApi = fs) {
    if (!fsApi.existsSync(file)) return [];
    let entries;
    try {
        entries = JSON.parse(fsApi.readFileSync(file, "utf8"));
    } catch (error) {
        throw new Error(`Invalid JSON in ${file}: ${error.message}`);
    }
    if (!Array.isArray(entries)) throw new Error(`${file} must be an array of entries`);
    for (const entry of entries) {
        if (!Number.isFinite(Number(entry?.body)) || !Array.isArray(entry.vp) || entry.vp.length !== 3) {
            throw new Error(`${file} has an entry without body and vp [x, y, z]`);
        }
    }
    return entries;
}

// ビークルのリンクはノードの位置(ボクセル座標)で結ばれるので、ポートの同一性は
// 位置と入出力の別と信号の種類で決まる。ノードのidはstorm-mclが書き出しのたびに振り直す
// 内部の番号で、ラベルは表示用なので、比べない。
function portSummary(definition) {
    const nodes = new Map();
    for (const { node } of definition.nodes ?? []) {
        const key = `${node?.mode === 1 ? "in" : "out"} type ${node?.type ?? 0} at x ${node?.position?.x ?? 0} z ${node?.position?.z ?? 0}`;
        nodes.set(key, (nodes.get(key) ?? 0) + 1);
    }
    return { size: `${definition.width}x${definition.length}`, nodes };
}

// ポートの位置が動くと車両の再結線が必要になる。差があれば人が読める形で返す。
export function diffPorts(before, after) {
    const a = portSummary(before);
    const b = portSummary(after);
    const differences = [];
    if (a.size !== b.size) differences.push(`size ${a.size} -> ${b.size}`);
    for (const key of new Set([...a.nodes.keys(), ...b.nodes.keys()])) {
        const delta = (b.nodes.get(key) ?? 0) - (a.nodes.get(key) ?? 0);
        if (delta < 0) differences.push(`port lost: ${key}${delta < -1 ? ` (x${-delta})` : ""}`);
        if (delta > 0) differences.push(`port added: ${key}${delta > 1 ? ` (x${delta})` : ""}`);
    }
    return differences;
}

const scriptsOf = (definition) =>
    (definition.group?.components ?? []).map((c) => c.object?.script).filter((s) => typeof s === "string");

// ラベルで property 部品を探して属性を書く。部品のidと並びは版で変わるので使わない。
// 値が null の属性は取り除く(ビークルで省略されていた値を、既定に戻すため)。
// component_statesにも同じ部品の状態があるので、あれば合わせて書く。
export function injectValues(definition, set = {}) {
    const injected = [];
    for (const [label, attributes] of Object.entries(set)) {
        const targets = propertyComponents(definition).map((c) => c.object).filter((o) => labelOf(o) === label);
        if (targets.length === 0) throw new Error(`No property named "${label}" in microcontroller "${definition.name}"`);
        // component_statesは配列でなく、c0、c1…をキーに持つオブジェクト。
        const states = Object.values(definition.group?.component_states ?? {}).filter((o) => labelOf(o) === label);
        for (const target of [...targets, ...states]) {
            for (const [attribute, value] of Object.entries(attributes)) {
                if (value === null) delete target[attribute];
                else target[attribute] = structuredClone(value);
            }
        }
        injected.push(`${label}: ${JSON.stringify(attributes)}`);
    }
    return injected;
}

// 対応表に無いマイコンの位置と、ビークルが持つ property の値を書き出す素材にする。
// 既存のエントリには触れない。project は空で書き出し、人が埋める(名前で推測しない)。
export function scanVehicle(vehicle, existing) {
    const added = [];
    for (const item of findMicrocontrollers(vehicle)) {
        if (existing.some((entry) => samePosition(item, entry))) continue;
        // すべての property の値を控える。ビークルで省略されている値は null で控える。
        // 控えた行を消せば、その property はプロジェクト側の既定値のままになる。
        const set = {};
        for (const c of propertyComponents(item.definition)) {
            set[labelOf(c.object)] = Object.fromEntries(
                PROPERTY_VALUE_ATTRIBUTES.get(c.type).map((attribute) => [attribute, c.object[attribute] ?? null]));
        }
        const entry = { body: item.body, vp: item.vp, name: item.definition.name, project: "" };
        if (Object.keys(set).length > 0) entry.set = set;
        added.push(entry);
    }
    return added;
}

// entries のうち project が空でないものを差し替える。generate(projectId) は
// プロジェクトから作ったマイコン(parseMicrocontrollerXmlの結果)を返す。
export async function swapVehicle(vehicleBytes, entries, generate) {
    const vehicle = parseVehicleXml(vehicleBytes);
    const microcontrollers = findMicrocontrollers(vehicle);
    const reports = [];
    for (const entry of entries) {
        const label = `body ${entry.body} vp [${entry.vp}]${entry.name ? ` ${entry.name}` : ""}`;
        if (!entry.project) {
            reports.push({ label, skipped: true });
            continue;
        }
        const target = locate(microcontrollers, entry);
        const replacement = await generate(entry.project);
        const injected = injectValues(replacement, entry.set);
        const before = scriptsOf(target.definition);
        const after = scriptsOf(replacement);
        const luaChanged = after.filter((s, i) => s !== before[i]).length + Math.max(0, before.length - after.length);
        const portDifferences = diffPorts(target.definition, replacement);
        target.component.o.microprocessor_definition = replacement;
        reports.push({ label, project: entry.project, luaChanged, luaCount: after.length, portDifferences, injected });
    }
    // 対応表にエントリが無いマイコンは、差し替えの対象から外れるだけで、変更されない。知らせるために数える。
    const unlisted = microcontrollers.filter((item) => !entries.some((entry) => samePosition(item, entry))).length;
    return { xml: serializeVehicleXml(vehicle), reports, unlisted };
}

export function printReports(reports, log = console.log) {
    const skipped = reports.filter((r) => r.skipped).length;
    if (skipped > 0) log(`  skip    ${skipped} entries (project is empty)`);
    for (const r of reports) {
        if (r.skipped) continue;
        log(`  replace ${r.label} <- ${r.project}: Lua ${r.luaChanged}/${r.luaCount} changed` +
            (r.injected.length ? `, inject ${r.injected.join("; ")}` : ""));
        for (const d of r.portDifferences) log(`  WARNING port differs (rewiring needed): ${d}`);
    }
}

function requireVehiclesDir(config) {
    if (!config.vehiclesDir) throw new Error("STORMWORKS_VEHICLES_DIR is required in .env for vehicle commands");
    return config.vehiclesDir;
}

export async function runVehicleCommand(command, name, config, adapter, dependencies = {}) {
    const fsApi = dependencies.fs ?? fs;
    const log = dependencies.log ?? console.log;
    const vehicle = resolveVehicle(config, name);

    if (command === "vehicle-scan") {
        const parsed = parseVehicleXml(new Uint8Array(fsApi.readFileSync(vehicle.source)));
        const existing = readMap(vehicle.map, fsApi);
        const added = scanVehicle(parsed, existing);
        if (added.length === 0) return log(`Nothing to add for ${vehicle.id}`);
        fsApi.writeFileSync(vehicle.map, `${JSON.stringify([...existing, ...added], null, 2)}\n`);
        return log(`Added ${added.length} entries to ${vehicle.map} (fill in "project" for each one to swap)`);
    }

    if (command === "vehicle-swap") {
        const entries = readMap(vehicle.map, fsApi);
        if (entries.length === 0) throw new Error(`No entries in ${vehicle.map}; run vehicle-scan first`);
        const projects = (dependencies.discoverProjects ?? discoverProjectJsonProjects)(config.repoRoot);
        // 差し替えの途中で失敗したとき、手元にも中途半端な出力を残さない。
        // 出力は全エントリの処理が成功した後で、一度に書く。
        const generate = async (projectId) => {
            const project = projects.find((candidate) => candidate.id === projectId);
            if (!project) throw new Error(`Unknown project: ${projectId}`);
            return withGeneratedXml(config, project, adapter, dependencies,
                (xml) => parseMicrocontrollerXml(new Uint8Array(fsApi.readFileSync(xml))));
        };
        const source = new Uint8Array(fsApi.readFileSync(vehicle.source));
        const { xml, reports, unlisted } = await swapVehicle(source, entries, generate);
        fsApi.mkdirSync(path.dirname(vehicle.out), { recursive: true });
        fsApi.writeFileSync(vehicle.out, xml);
        printReports(reports, log);
        if (unlisted > 0) log(`  note    ${unlisted} microcontrollers are not in ${vehicle.map} and were left as they are (run vehicle-scan to add them)`);
        return log(`Wrote ${vehicle.out}`);
    }

    if (command === "vehicle-install") {
        const vehiclesDir = requireVehiclesDir(config);
        const source = vehicle.out;
        if (!fsApi.existsSync(source)) throw new Error(`Run vehicle-swap first: ${source} not found`);
        // 壊れた出力をゲーム側へ置かないよう、読めることだけ確かめる。
        parseVehicleXml(new Uint8Array(fsApi.readFileSync(source)));
        const destination = path.join(vehiclesDir, vehicle.fileName);
        if (fsApi.existsSync(destination) && fsApi.readFileSync(destination).equals(fsApi.readFileSync(source))) {
            return log(`No write: ${destination}`);
        }
        // バックアップが取れなければ、installWithRollbackは置き換えの前に例外で止まる。
        const backup = path.join(config.backupDir, "vehicles", `${path.basename(vehicle.fileName, ".xml")}-${timestamp(dependencies.now?.())}.xml`);
        installWithRollback(source, destination, backup, fsApi);
        return log(`Installed ${destination}` + (fsApi.existsSync(backup) ? ` (backup: ${backup})` : " (new file, no backup needed)"));
    }

    throw new Error(`Unknown vehicle command: ${command}`);
}
