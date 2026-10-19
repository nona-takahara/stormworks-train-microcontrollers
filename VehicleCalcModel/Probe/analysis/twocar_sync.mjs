#!/usr/bin/env node
// Time offset between two probes from the sawtooth in aux2 (ch23: +1 per tick, period 300 tick, the same wave on both cars).
//   a probe's wave phase is (t + a) mod 300, so the same instant has tB = tA + d with d = a_A - a_B (mod 300).
//   The receive time recv_ms gives d only coarsely (tens of ticks); it picks the multiple of 300 (needs |error| < 150 tick).
// Usage: node twocar_sync.mjs <logA.csv> <logB.csv> [fromRow]   (rows from fromRow on; default all)
// Prints d [tick] (tB = tA + d), the coarse d, and whether each probe's a is constant over the rows.
import fs from "node:fs";

const P = 300, TICK_MS = 1000 / 60;
const wrap = (x) => ((x % P) + P) % P, signed = (x) => wrap(x + P / 2) - P / 2;
const median = (xs) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)];

export function readProbe(file, from = 0) {
    const [head, ...lines] = fs.readFileSync(file, "utf8").trim().split("\n"), cols = head.split(",");
    return lines.slice(from).map((l) => Object.fromEntries(l.split(",").map((v, i) => [cols[i], +v])));
}

// a = (aux2 - t) mod 300 per row; c = recv_ms in ticks minus t (the receive time of a row is later than its tick by the batch wait, the same kind for both probes)
function describe(rows) {
    const a = rows.map((r) => wrap(r.aux2 - r.t)), a0 = median(a);
    const spread = Math.max(...a.map((x) => Math.abs(signed(x - a0))));
    return { a: a0, spread, c: median(rows.map((r) => r.recv_ms / TICK_MS - r.t)) };
}

export function offset(rowsA, rowsB) {
    const A = describe(rowsA), B = describe(rowsB);
    const coarse = A.c - B.c, fine = wrap(A.a - B.a);
    const d = fine + P * Math.round((coarse - fine) / P);
    return { d, coarse, residual: d - coarse, spreadA: A.spread, spreadB: B.spread, aA: A.a, aB: B.a };
}

if (process.argv[1] && process.argv[1].endsWith("twocar_sync.mjs")) {
    const [fa, fb, from] = process.argv.slice(2), r = offset(readProbe(fa, +from || 0), readProbe(fb, +from || 0));
    console.log(`d = ${r.d} tick (tB = tA + d); coarse ${r.coarse.toFixed(1)}, fine - coarse ${r.residual.toFixed(1)} (must be within +-150)`);
    console.log(`wave phase a: A ${r.aA}, B ${r.aB}; spread within the rows: A ${r.spreadA}, B ${r.spreadB} tick (0 = the wave keeps the tick count)`);
    if (Math.abs(r.residual) >= 150) { console.log("  UNRELIABLE: the coarse offset is not within half a period"); process.exit(1); }
}
