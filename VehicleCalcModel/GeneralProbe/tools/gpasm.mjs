// Assembler for the general probe VM (BYTECODE_SPEC.md).
// assemble(source) -> { words, mem, N, symbols }; messages(result, opts) -> wire lines.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));

export function loadOps(path = here + "../src/ops.txt") {
  const ops = {};
  for (const m of readFileSync(path, "utf8").matchAll(/^(\w+) (\d+)$/gm)) ops[m[1]] = Number(m[2]);
  return ops;
}

// Operand kinds in written order, as field names: a = address, p = port, t = jump target.
// `w` marks the field a computing instruction writes (a literal there is an error).
const SIG = {
  NOP: [], HALT: [],
  MOV: [["d", "a", true], ["a", "a"]],
  ABS: [["d", "a", true], ["a", "a"]], FLR: [["d", "a", true], ["a", "a"]],
  SQRT: [["d", "a", true], ["a", "a"]], SIN: [["d", "a", true], ["a", "a"]],
  F2I: [["d", "a", true], ["a", "a"]], I2F: [["d", "a", true], ["a", "a"]],
  LD: [["d", "a", true], ["a", "a"]],
  ST: [["d", "a"], ["a", "a"]],
  PLD: [["d", "a", true], ["a", "p"]],
  PST: [["d", "p"], ["a", "a"]],
  JMP: [["a", "t"]],
  JGZ: [["a", "t"], ["b", "a"]],
};
for (const n of ["ADD", "SUB", "MUL", "DIV", "MIN", "MAX", "CLP", "LT", "LE", "CMOV", "AND", "OR", "XOR", "SHL", "SHR"])
  SIG[n] = [["d", "a", true], ["a", "a"], ["b", "a"]];

const MEMS = 65536;

// Macros expand to primitive instructions at assembly time (the VM has no immediates or compare-to-bool ops).
// Booleans are 0/1 cells. __s1/__s2 are hidden scratch cells.
const MACROS = {
  NOT: (d, a) => [["SUB", d, "#1", a]],
  GT: (d, a, b) => [["LT", d, b, a]],
  GE: (d, a, b) => [["LE", d, b, a]],
  EQ: (d, a, b) => [["LE", "__s1", a, b], ["LE", "__s2", b, a], ["MUL", d, "__s1", "__s2"]],
  NE: (d, a, b) => [["LE", "__s1", a, b], ["LE", "__s2", b, a], ["MUL", d, "__s1", "__s2"], ["SUB", d, "#1", d]],
  SEL: (d, c, a, b) => [["MOV", "__s1", b], ["CMOV", "__s1", a, c], ["MOV", d, "__s1"]],
  JT: (label, x) => [["JGZ", label, x]],
  JF: (label, x) => [["SUB", "__s1", "#1", x], ["JGZ", label, "__s1"]],
};
const MACRO_ARITY = { NOT: 2, GT: 3, GE: 3, EQ: 3, NE: 3, SEL: 4, JT: 2, JF: 2 };

function expandIncludes(source, baseDir, where = "main", depth = 0) {
  if (depth > 8) throw new Error("include nesting too deep");
  const out = [];
  source.split(/\r?\n/).forEach((text, idx) => {
    const m = /^\s*\.include\s+(\S+)\s*$/.exec(text.replace(/;.*/, ""));
    if (!m) { out.push({ text, where: `${where}:${idx + 1}` }); return; }
    const path = resolvePath(baseDir, m[1]);
    out.push(...expandIncludes(readFileSync(path, "utf8"), dirname(path), m[1], depth + 1));
  });
  return out;
}

export function assemble(source, ops = loadOps(), { baseDir = "." } = {}) {
  const symbols = new Map();
  for (let i = 1; i <= 32; i++) { symbols.set(`N${i}`, i - 1); symbols.set(`B${i}`, 31 + i); }
  let N = 16, pub = 0, priv = null;
  const mem = new Map();          // address -> value (nonzero only)
  const pool = new Map();         // literal value -> address
  const constCells = new Set();
  const insts = [];               // {where, name, operands}
  const labels = new Map();

  const err = (where, msg) => { throw new Error(`${where}: ${msg}`); };
  const num = (tok, where) => {
    let v = Number(tok);
    if (tok !== "" && Number.isNaN(v) && /^[-+0-9.eE*/() ]+$/.test(tok)) {
      try { v = Function(`"use strict"; return (${tok});`)(); } catch { v = NaN; }
    }
    if (tok === "" || typeof v !== "number" || Number.isNaN(v)) err(where, `not a number: ${tok}`);
    return v;
  };
  const allocPriv = (where) => {
    if (priv === null) priv = N;
    if (priv >= MEMS) err(where, "out of memory cells");
    return priv++;
  };
  const setMem = (addr, v) => { if (v !== 0) mem.set(addr, v); else mem.delete(addr); };
  const scratch = (name, where) => {
    if (!symbols.has(name)) symbols.set(name, allocPriv(where));
    return name;
  };

  // pass 1: directives, labels, macro expansion
  expandIncludes(source, baseDir).forEach(({ text: raw, where }) => {
    let text = raw.replace(/;.*/, "").trim();
    if (!text) return;
    let m;
    while ((m = /^([A-Za-z_]\w*):\s*(.*)$/.exec(text))) {
      if (labels.has(m[1])) err(where, `duplicate label ${m[1]}`);
      labels.set(m[1], insts.length);
      text = m[2];
    }
    if (!text) return;
    const [head, ...rest] = text.split(/\s+/);
    const body = rest.join(" ");
    const args = body.split(",").map((s) => s.trim()).filter((s) => s.length);
    if (head.startsWith(".")) {
      const dir = head.toLowerCase();
      const words = body.split(/[\s,]+/).filter((s) => s.length);
      if (dir === ".host") { N = num(args[0], where); }
      else if (dir === ".def") {
        if (words.length !== 2) err(where, ".def name value");
        symbols.set(words[0], num(words[1], where));
      } else if (dir === ".pub" || dir === ".var") {
        const [name, init] = words;
        if (!name) err(where, `${dir} name`);
        let a;
        if (dir === ".pub") { if (pub >= N) err(where, "host-visible region full"); a = pub++; }
        else a = allocPriv(where);
        symbols.set(name, a);
        if (init !== undefined) setMem(a, num(init, where));
      } else if (dir === ".vars") {
        words.forEach((name) => symbols.set(name, allocPriv(where)));
      } else if (dir === ".table") {
        const [name, ...vals] = words;
        if (!name || vals.length === 0) err(where, ".table name v1,v2,...");
        vals.forEach((v, i) => { const a = allocPriv(where); if (i === 0) symbols.set(name, a); setMem(a, num(v, where)); });
      } else if (dir === ".mem") {
        const [target, val] = words;
        const a = symbols.has(target) ? symbols.get(target) : num(target, where);
        setMem(a, num(val, where));
      } else err(where, `unknown directive ${head}`);
      return;
    }
    const name = head.toUpperCase();
    if (name in MACROS) {
      if (args.length !== MACRO_ARITY[name]) err(where, `${name} takes ${MACRO_ARITY[name]} operands`);
      for (const [n, ...o] of MACROS[name](...args)) {
        o.forEach((x) => { if (x === "__s1" || x === "__s2") scratch(x, where); });
        insts.push({ where, name: n, operands: o });
      }
      return;
    }
    insts.push({ where, name, operands: args });
  });

  // pass 2: encode
  const words = [];
  const literal = (v, where) => {
    if (!pool.has(v)) { const a = allocPriv(where); pool.set(v, a); constCells.add(a); setMem(a, v); }
    return pool.get(v);
  };
  const resolve = (tok, kind, written, where) => {
    if (tok.startsWith("#") || tok.startsWith("@")) {
      if (kind !== "a") err(where, `literal not allowed here: ${tok}`);
      if (written) err(where, `literal cannot be written: ${tok}`);
      if (tok.startsWith("@")) {
        if (!symbols.has(tok.slice(1))) err(where, `unknown symbol ${tok.slice(1)}`);
        return literal(symbols.get(tok.slice(1)), where);
      }
      return literal(num(tok.slice(1), where), where);
    }
    if (kind === "t" && labels.has(tok)) return labels.get(tok);
    if (symbols.has(tok)) return symbols.get(tok);
    if (/^[-+]?(\d|\.\d)/.test(tok)) return num(tok, where);
    err(where, `unknown symbol ${tok}`);
  };
  for (const { where, name, operands } of insts) {
    if (!(name in ops)) err(where, `unknown instruction ${name}`);
    const sig = SIG[name];
    if (operands.length !== sig.length) err(where, `${name} takes ${sig.length} operands`);
    const f = { d: 0, a: 0, b: 0 };
    sig.forEach(([field, kind, written], i) => { f[field] = resolve(operands[i], kind, written, where); });
    words.push(ops[name], f.d, f.a, f.b);
  }
  const memList = [...mem.entries()].sort((x, y) => x[0] - y[0]);
  return { words, mem: memList, N, symbols: Object.fromEntries(symbols), labels: Object.fromEntries(labels), constCells: [...constCells] };
}

export function adler(text) {
  let a = 1, b = 0;
  for (const byte of Buffer.from(text, "utf8")) { a = (a + byte) % 65521; b = (b + a) % 65521; }
  return b * 65536 + a;
}

const line = (kind, nums) => {
  const body = `${kind}:${nums.map(String).join(",")}`;
  return `${body}*${adler(body)}`;
};

// opts: reset (prepend R), chunkWords (words per C message), chunkPairs (pairs per M message)
export function messages(res, { reset = false, chunkWords = 400, chunkPairs = 100 } = {}) {
  const out = [];
  if (reset) out.push(line("R", []));
  if (res.words.length === 0) out.push(line("C", [res.N, 0]));
  for (let off = 0; off < res.words.length; off += chunkWords)
    out.push(line("C", [res.N, off, ...res.words.slice(off, off + chunkWords)]));
  for (let i = 0; i < res.mem.length; i += chunkPairs)
    out.push(line("M", res.mem.slice(i, i + chunkPairs).flat()));
  out.push(line("K", []));
  return out;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
  const file = args.find((a, i) => !a.startsWith("--") && !(i > 0 && args[i - 1].startsWith("--") && args[i - 1] !== "--reset"));
  if (!file) { console.error("usage: node gpasm.mjs file.asm [--reset] [--chunk-words n] [--out file] [--symbols-lua file]"); process.exit(2); }
  const res = assemble(readFileSync(file, "utf8"), loadOps(), { baseDir: dirname(resolvePath(file)) });
  const text = messages(res, { reset: args.includes("--reset"), chunkWords: Number(opt("--chunk-words") ?? 400) }).join("\n");
  if (opt("--out")) writeFileSync(opt("--out"), text + "\n"); else console.log(text);
  if (opt("--symbols-lua")) {
    const lines = Object.entries(res.symbols).filter(([k]) => /^[A-Za-z_]\w*$/.test(k)).map(([k, v]) => `  ${k} = ${v},`);
    writeFileSync(opt("--symbols-lua"), `return {\n${lines.join("\n")}\n}\n`);
  }
}
