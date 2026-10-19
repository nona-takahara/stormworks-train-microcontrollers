import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { adler, assemble, loadOps, messages } from "../tools/gpasm.mjs";

const here = fileURLToPath(new URL(".", import.meta.url));
const core = here + "../src/gp_core.lua";

test("checksum golden vectors (same as the Lua suite)", () => {
  assert.equal(adler("K:"), 13762694);
  assert.equal(adler("R:"), 14680205);
  assert.equal(adler("M:0,1"), 59179285);
  assert.equal(adler("C:8,0,22,0,0,0"), 357040822);
});

test("ops.txt matches the instruction table in BYTECODE_SPEC.md", () => {
  const spec = readFileSync(here + "../BYTECODE_SPEC.md", "utf8");
  const fromSpec = {};
  for (const m of spec.matchAll(/^\| (\d+) \| `(\w+)[^`]*` \|/gm)) fromSpec[m[2]] = Number(m[1]);
  assert.deepEqual(fromSpec, loadOps());
});

test("encoding: fields follow the operand order of the spec table", () => {
  const ops = loadOps();
  const r = assemble(".host 4\n.pub a\n.pub b\n.pub c\nADD a, b, c\nPLD c, 5\nPST 3, a\nJGZ 0, b", ops);
  assert.deepEqual(r.words, [ops.ADD, 0, 1, 2, ops.PLD, 2, 5, 0, ops.PST, 3, 0, 0, ops.JGZ, 0, 0, 1]);
});

test("labels resolve forward and backward; literals are pooled", () => {
  const ops = loadOps();
  // cells: x = 0, literal #1 = 2 (host region is 2 wide)
  const r = assemble(".host 2\n.pub x\nstart: ADD x, x, #1\nJGZ end, x\nJMP start\nend: HALT", ops);
  assert.deepEqual(r.words, [
    ops.ADD, 0, 0, 2,
    ops.JGZ, 0, 3, 0,   // forward label: instruction 3; condition cell x = 0
    ops.JMP, 0, 0, 0,   // backward label: instruction 0
    ops.HALT, 0, 0, 0,
  ]);
  const r2 = assemble(".host 2\n.pub x\nADD x, x, #1\nADD x, x, #1\nADD x, x, #2", ops);
  assert.equal(r2.constCells.length, 2);
  assert.equal(r2.words[3], r2.words[7]);
  assert.notEqual(r2.words[3], r2.words[11]);
  assert.deepEqual(r2.mem, [[2, 1], [3, 2]]);
});

test("assembler rejects malformed source", () => {
  assert.throws(() => assemble("FOO 1"), /unknown instruction/);
  assert.throws(() => assemble(".pub a\nADD a, a"), /takes 3 operands/);
  assert.throws(() => assemble(".pub a\nADD #1, a, a"), /cannot be written/);
  assert.throws(() => assemble("MOV zz, zz"), /unknown symbol/);
  assert.throws(() => assemble("l: NOP\nl: NOP"), /duplicate label/);
  assert.throws(() => assemble(".host 1\n.pub a\n.pub b"), /full/);
});

test("messages: chunking and offsets", () => {
  const r = assemble(".host 4\n.pub a\n" + "ADD a, a, a\n".repeat(5));
  const lines = messages(r, { chunkWords: 8, reset: true });
  assert.match(lines[0], /^R:\*/);
  assert.match(lines[1], /^C:4,0,/);
  assert.match(lines[2], /^C:4,8,/);
  assert.match(lines[3], /^C:4,16,/);
  assert.match(lines.at(-1), /^K:\*/);
});

// End to end: assembler -> Lua core.
function runLua(lines, ticks) {
  const script = `
    dofile(${JSON.stringify(core)})
    gp_budget(100)
    ${lines.map((l) => `assert(gp_msg(${JSON.stringify(l)}) == "OK")`).join("\n")}
    local function arr(t) local o = {} for i = 1, 32 do o[i] = t[i] or 0.0 end return o end
    local bt = {} for i = 1, 32 do bt[i] = false end bt[32] = true
    ${ticks.map(([t, p]) => `do local inn = arr({${t}, ${p}}); local on = gp_tick(inn, bt); print(string.format("%.17g %.17g", on[1], on[2])) end`).join("\n")}
  `;
  const res = spawnSync("lua", ["-"], { input: script, encoding: "utf8" });
  assert.equal(res.status, 0, res.stderr);
  return res.stdout.trim().split("\n").map((l) => l.split(" ").map(Number));
}

test("air_brake_basic.asm matches the reference formula in the Lua core", () => {
  const src = readFileSync(here + "../programs/air_brake_basic.asm", "utf8");
  const lines = messages(assemble(src));
  const cases = [[1.5, 1.0], [1.0, 1.2], [1.0, 1.005], [3, 1], [1, 3], [1.2, 1.0], [1.0, 1.0]];
  const out = runLua(lines, cases);
  cases.forEach(([tgt, pbc], i) => {
    const err = tgt - pbc;
    let u = Math.min(1, Math.max(-1, err * 2));
    if (Math.abs(err) < 0.01) u = 0;
    const [uin, uex] = out[i];
    assert.ok(Math.abs(uin - Math.max(u, 0)) < 1e-12, `uin for ${tgt},${pbc}`);
    assert.ok(Math.abs(uex - Math.max(-u, 0)) < 1e-12, `uex for ${tgt},${pbc}`);
    assert.ok(uin === 0 || uex === 0, "valves are never open together");
  });
});
