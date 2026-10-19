// Shared by freqresp2.mjs and fitdelay.mjs: the complex component of a signal at f, and the speed/motor response of a sweep run.
import { simulate2 } from "./axle2.mjs";

export const comp = (ts, ys, f) => { // complex component at f of y(t): least squares on [1, t, t^2, sin, cos], so that a drifting mean (a speed still changing) does not leak into f
    const n = ts.length, t0 = ts[0], X = ts.map((t) => { const x = (t - t0) / (ts[n - 1] - t0), w = 2 * Math.PI * f * t / 60; return [1, x, x * x, Math.sin(w), Math.cos(w)]; });
    const A = Array.from({ length: 5 }, () => new Array(6).fill(0));
    X.forEach((r, i) => { for (let a = 0; a < 5; a++) { for (let b = 0; b < 5; b++) A[a][b] += r[a] * r[b]; A[a][5] += r[a] * ys[i]; } });
    for (let c = 0; c < 5; c++) { let p = c; for (let r = c + 1; r < 5; r++) if (Math.abs(A[r][c]) > Math.abs(A[p][c])) p = r; [A[c], A[p]] = [A[p], A[c]];
        for (let r = 0; r < 5; r++) if (r !== c) { const q = A[r][c] / A[c][c]; for (let k = c; k < 6; k++) A[r][k] -= q * A[c][k]; } }
    const sn = A[3][5] / A[3][3], cs = A[4][5] / A[4][4];   // y ~ ... + sn sin(wt) + cs cos(wt) = Re[(cs - j sn) e^{jwt}] -> component (cs, -sn) in the form used below
    return [cs, -sn];
};
export const div = ([a, b], [c, d]) => { const q = c * c + d * d; return [(a * c + b * d) / q, (b * c - a * d) / q]; };

// per sine segment (segment 2 and on of a sweep): G(f) = V/U measured and of the model P (simulate2 driven by the logged inputs)
export function responses(run, freqs, P) {
    const sim = simulate2(run, P), sgn = Math.sign(run.reduce((s, x) => s + x.v, 0)) || 1, out = [];
    freqs.forEach((f, i) => {
        const w = run.filter((x) => x.seg === i + 2); if (w.length < 8) return;
        const T = 60 / f, t0 = w[0].t + T, nper = Math.floor((w[w.length - 1].t - t0) / T); if (nper < 1) return;
        const idx = w.map((x, j) => j).filter((j) => w[j].t >= t0 && w[j].t < t0 + nper * T), ts = idx.map((j) => w[j].t);
        const u = comp(ts, idx.map((j) => sgn * w[j].motor), f), k0 = run.indexOf(w[0]);
        out.push({ f, nper, g: div(comp(ts, idx.map((j) => sgn * w[j].v), f), u), gm: div(comp(ts, idx.map((j) => sgn * sim[k0 + j].v), f), u) });
    });
    return out;
}
