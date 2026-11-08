// ビークルXMLの結線を、XMLを直接読まずに引くための歩き方。
// パースは @sw-file-lib/xml に任せ、ここでは「マイコンのノード → つながる先」の有向グラフを作る。
//
// ビークルの logic_node_links は、ボクセル座標の対で結線を表す(voxel_pos_0 が送り側、voxel_pos_1 が受け側)。
// マイコンのノードのボクセル座標は、マイコンの vp に、回転 r を掛けたノードの位置(x, z)を足したもの。
//   - r は 9 個の数を、列ごとに並べた回転行列として読む(世界座標 = vp + 列の和)。
//   - 1 つのセルに複数のノードが重なる(入力と出力、型違い)ので、リンクの type と
//     ノードの type が一致し、送り側は出力、受け側は入力のものに絞る。省略された type は 0(bool)。
//   - マイコン以外の部品(ボタン、センサー、サイン、コネクタ等)のノードは定義を持たないので、
//     つなぎ先は「部品名@x,y,z」の文字列で返す。部品名は、そのセルを原点(vp)とする部品の名前で、
//     原点が別のセルにある部品のノードは「?」になる。同じセルに複数の部品があれば「|」で並べる。
//     部品を貫通した先は追わない。
import path from "node:path";
import { parseVehicleXml } from "@sw-file-lib/xml";

const TYPE_NAMES = { 0: "bool", 1: "number", 5: "composite", 6: "video", 7: "audio" };
const cellKey = (p) => `${p?.x ?? 0},${p?.y ?? 0},${p?.z ?? 0}`;

// 戻り値: { microcontrollers: [{ name, body, vp, nodes: [{ label, dir, type, out: [...], in: [...] }] }], ambiguous }
// ノードの out / in は、つなぎ先のノード(マイコン)か文字列(マイコン以外)の配列。
export function buildWiring(vehicle) {
    const cells = new Map();
    const others = new Map();
    const microcontrollers = [];
    for (const body of vehicle.bodies ?? []) {
        for (const component of body.components ?? []) {
            const vp = component.o?.vp ?? {};
            const definition = component.o?.microprocessor_definition;
            if (!definition) {
                const key = cellKey(vp);
                if (!others.has(key)) others.set(key, new Set());
                others.get(key).add(component.d);
                continue;
            }
            const m = (component.o.r ?? "1,0,0,0,1,0,0,0,1").split(",").map(Number);
            const mc = { name: definition.name, body: Number(body.unique_id), vp: [vp.x ?? 0, vp.y ?? 0, vp.z ?? 0], nodes: [] };
            for (const { node } of definition.nodes ?? []) {
                const { x = 0, y = 0, z = 0 } = node.position ?? {};
                const pos = cellKey({
                    x: mc.vp[0] + m[0] * x + m[3] * y + m[6] * z,
                    y: mc.vp[1] + m[1] * x + m[4] * y + m[7] * z,
                    z: mc.vp[2] + m[2] * x + m[5] * y + m[8] * z,
                });
                const entry = { mc, label: node.label, dir: node.mode === 1 ? "in" : "out", type: node.type ?? 0, pos, out: [], in: [] };
                mc.nodes.push(entry);
                if (!cells.has(pos)) cells.set(pos, []);
                cells.get(pos).push(entry);
            }
            microcontrollers.push(mc);
        }
    }

    const pick = (pos, dir, type) => (cells.get(pos) ?? []).filter((n) => n.dir === dir && n.type === type);
    const ambiguous = [];
    for (const link of vehicle.logic_node_links ?? []) {
        const type = link.type ?? 0;
        const a = cellKey(link.voxel_pos_0);
        const b = cellKey(link.voxel_pos_1);
        const sources = pick(a, "out", type);
        const sinks = pick(b, "in", type);
        if (sources.length > 1 || sinks.length > 1) ambiguous.push({ from: a, to: b, type });
        const outside = (pos) => `${[...(others.get(pos) ?? ["?"])].join("|")}@${pos}`;
        for (const s of sources.length ? sources : [null]) {
            for (const d of sinks.length ? sinks : [null]) {
                if (s && d) { s.out.push(d); d.in.push(s); }
                else if (s) s.out.push(outside(b));
                else if (d) d.in.push(outside(a));
            }
        }
    }
    return { microcontrollers, ambiguous };
}

export const portName = (node) => (typeof node === "string" ? node : `${node.mc.name}.${node.label}`);

// マイコン間(両端がマイコン)の結線だけを、重複なしで "送り側 ==> 受け側" の行にする。
export function microcontrollerEdges(wiring) {
    const lines = new Set();
    for (const mc of wiring.microcontrollers) {
        for (const node of mc.nodes) {
            for (const peer of node.out) if (typeof peer !== "string") lines.add(`${portName(node)}  ==>  ${portName(peer)}`);
        }
    }
    return [...lines].sort();
}

// マイコンごとに、ポートとつなぎ先を並べる。マイコン以外へのつなぎ先も出す。
export function formatWiring(wiring) {
    const lines = [];
    for (const mc of wiring.microcontrollers) {
        lines.push(`## ${mc.name} (body ${mc.body}, vp [${mc.vp}])`);
        for (const node of mc.nodes) {
            const peers = [...new Set((node.dir === "in" ? node.in : node.out).map(portName))];
            const arrow = node.dir === "in" ? "<-" : "->";
            lines.push(`  ${node.dir} ${TYPE_NAMES[node.type] ?? node.type} "${node.label}" ${arrow} ${peers.join("; ") || "(none)"}`);
        }
        lines.push("");
    }
    if (wiring.ambiguous.length > 0) lines.push(`## 一意に決まらなかったリンク\n${JSON.stringify(wiring.ambiguous)}`);
    return lines.join("\n");
}

export function readWiring(bytes) {
    return buildWiring(parseVehicleXml(new Uint8Array(bytes)));
}

// ビークルの指定は vehicles/ からの相対パス(例: CHUSO2000/CHUSO2000_2001)。拡張子は省いてよい。
// vehicles/ の外を指せる指定(絶対パス、..、空の区間)は受け付けない。
export function vehicleSourcePath(repoRoot, name) {
    const id = name.replace(/\\/gu, "/").replace(/\.xml$/u, "");
    const segments = id.split("/");
    if (segments.some((s) => s === "" || s === "." || s === "..") || /^[A-Za-z]:/u.test(id)) {
        throw new Error(`Vehicle must be a relative path under vehicles/: ${name}`);
    }
    return path.join(repoRoot, "vehicles", ...segments.slice(0, -1), `${segments.at(-1)}.xml`);
}
