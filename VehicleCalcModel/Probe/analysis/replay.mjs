// The exact commands of a run, rebuilt from the program text that was sent to the probe (programs.json of the run) and the logged speed.
// The probe log has motor and brake at %.3f; the small commands (the resistance cancel 0.001..0.08, a brake near the dead zone 0.011..0.02) lose several percent
// in that rounding, and 0.0114 is logged as 0.011 (under the dead zone 0.0113). The rebuilt value is  c0 + c1 v + c2 v^2 + ci/max(v,vmin) + ct tau + A sin(2 pi f tau)
// with v = |speed|, tau = seconds since the start of the segment (probe_core.lua `shape`).
//   fixCommands(rows, programText) -> rows with motor and brake replaced by the rebuilt values (RUN rows only)
//   node replay.mjs <twocar folder>   -> the largest difference from the logged values (it should be within the rounding, 0.0005)
import fs from "node:fs";
import path from "node:path";

const pad7 = (c) => [...c, 0, 0, 0, 0, 0, 0, 0].slice(0, 7);
function parseSegment(a) {
    if (!a.includes("/")) { const [m, b, len] = a.split(":").map(Number); return { len, vmin: 1, m: pad7([m]), b: pad7([b]) }; }
    const p = a.split("/"), [len, vmin, m, b] = p.length === 4 ? [p[0], p[1], p[2], p[3]] : [p[0], p[2], p[3], p[4]];
    return { len: +len, vmin: +vmin, m: pad7(m.split(",").map(Number)), b: pad7(b.split(",").map(Number)) };
}
const parseProgram = (text) => text.trim().split(/\s+/).filter(Boolean).map((step) => step.split(";").map(parseSegment));
const shape = (f, v, tau, vmin) => f[0] + f[1] * v + f[2] * v * v + f[3] / Math.max(v, vmin) + f[4] * tau + f[5] * Math.sin(6.2831853 * f[6] * tau);

export function fixCommands(rows, programText) {
    const steps = parseProgram(programText); let step = -1, prevReason = 99, prevT = -99, segStart = 0, curSeg = 0;
    return rows.map((r) => {
        if (r.state !== 1) { prevReason = 99; return r; }
        if (r.t - prevT > 6 || r.reason < prevReason) step++;                 // a new program (the probe was idle in between, or the segment number restarted)
        if (r.reason !== curSeg || r.t - prevT > 6) { segStart = r.t; curSeg = r.reason; }
        prevT = r.t; prevReason = r.reason;
        const seg = steps[step]?.[r.reason - 1]; if (!seg) return r;
        const v = Math.abs(r.v), tau = (r.t - segStart) / 60;
        return { ...r, motor: shape(seg.m, v, tau, seg.vmin), brake: shape(seg.b, v, tau, seg.vmin) };
    });
}

if (process.argv[1] && process.argv[1].endsWith("replay.mjs")) {
    const dir = process.argv[2], progs = JSON.parse(fs.readFileSync(path.join(dir, "programs.json"), "utf8"));
    for (const car of ["A", "B"]) {
        const rows = fs.readFileSync(path.join(dir, `${car}.csv`), "utf8").trim().split("\n").slice(1).map((l) => l.split(",")).map((c) => ({ t: +c[2], v: +c[6], motor: +c[7], brake: +c[8], state: +c[10], reason: +c[11] }));
        const fixed = fixCommands(rows, progs[car]); let md = 0, mb = 0, n = 0;
        rows.forEach((r, i) => { if (r.state === 1) { md = Math.max(md, Math.abs(fixed[i].motor - r.motor)); mb = Math.max(mb, Math.abs(fixed[i].brake - r.brake)); n++; } });
        console.log(`${car}: ${n} RUN rows, largest difference from the log: motor ${md.toFixed(4)}  brake ${mb.toFixed(4)}`);
    }
}
