#!/usr/bin/env node
// Runs a sequence of constant-input windows against the running probe server.
// Usage: node campaign.mjs [--url http://127.0.0.1:8765] [--vmax 22] motor:brake:len ...
//   e.g. node campaign.mjs 0:0:300 0.4:0:80 0:0.3:200
// A step may also give the full formula:  len/vmin/m0,m1,m2,mi/b0,b1,b2,bi  (u = c0+c1*v+c2*v^2+ci/max(v,vmin)).
// Each step is queued through POST /ctl and waited for via GET /state. The
// campaign stops at the first step whose probe state is not IDLE/RUN
// (ABORT or FALLEN), and refuses to start a step with motor > 0 while the
// speed is above --vmax (m/s), so the speed domain of the goal is not exceeded.
// A step whose motor formula exceeds --mmax (default 0.4), or whose brake formula leaves 0..--bmax
// (default 1), anywhere in 0..40 m/s is refused. The probe itself applies no such bound.
const args = process.argv.slice(2);
const opt = (name, d) => (args.includes(name) ? args[args.indexOf(name) + 1] : d);
const base = opt("--url", "http://127.0.0.1:8765");
const vmax = Number(opt("--vmax", 22));
const mmax = Number(opt("--mmax", 0.4)); // agreed motor bound; raise it only for slip-range tests
const bmax = Number(opt("--bmax", 1));   // brake range of the vehicle (bmin..bmax)
const bmin = Number(opt("--bmin", 0));
// One segment is  motor:brake:len  (constants), or
//   len/vmin/m/b   or   len/vend/vmin/m/b
// where m and b are  c0,c1,c2,ci[,ct,A,f]  (u = c0 + c1*v + c2*v^2 + ci/max(v,vmin) + ct*tau + A*sin(2*pi*f*tau)).
// vend > 0 ends the segment once |v| >= vend, vend < 0 once |v| <= -vend. A step is segments joined by ';'
// that the probe runs back to back.
const pad7 = (c) => [...c, 0, 0, 0].slice(0, 7).map((x, i) => (i < c.length ? x : 0));
const parseSegment = (a) => {
    if (!a.includes("/")) { const [m, b, len] = a.split(":").map(Number); return { len, vend: 0, vmin: 1, m: pad7([m, 0, 0, 0]), b: pad7([b, 0, 0, 0]) }; }
    const p = a.split("/");
    const [len, vend, vmin, m, b] = p.length === 4 ? [p[0], "0", p[1], p[2], p[3]] : p;
    const nums = (x) => pad7(x.split(",").map(Number));
    return { len: Number(len), vend: Number(vend), vmin: Number(vmin), m: nums(m), b: nums(b) };
};
const steps = args.filter((a, i) => !a.startsWith("--") && !args[i - 1]?.startsWith("--")).filter((a) => /^-?[\d.]+:[\d.]+:\d+/.test(a) || a.includes("/")).map((a) => ({ label: a, segs: a.split(";").map(parseSegment) }));

const state = async () => (await fetch(`${base}/state`)).json();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

for (const { segs, label } of steps) {
    const before = await state();
    const v = before.last?.v ?? 0;
    const at = (f, x, vmin, len) => f[0] + f[1] * x + f[2] * x * x + f[3] / Math.max(x, vmin) + Math.abs(f[4]) * len / 60 + Math.abs(f[5]);
    const xs = [0, 10, 20, 30, 40];
    const mpeak = Math.max(...segs.flatMap((g) => xs.map((x) => Math.abs(at(g.m, x, g.vmin, g.len)))));
    const bvals = segs.flatMap((g) => xs.map((x) => at(g.b, x, g.vmin, g.len)));
    if (Math.max(...bvals) > bmax + 1e-9 || Math.min(...bvals) < bmin - 1e-9) { console.log(`stop: brake formula leaves ${bmin}..${bmax}`); process.exit(1); }
    if (mpeak > mmax + 1e-9) { console.log(`stop: motor formula reaches ${mpeak.toFixed(3)} > --mmax ${mmax}`); process.exit(1); }
    if (before.last?.state !== 0) { console.log(`stop: probe state ${before.last?.state}`); process.exit(1); }
    if (segs.some((g) => g.m.some((c) => c !== 0)) && Math.abs(v) > vmax) { console.log(`stop: v=${v} exceeds ${vmax} before a motor step`); process.exit(1); }
    const body = segs.map((g) => `${g.len},${g.vend},${g.vmin},${g.m.join(",")},${g.b.join(",")}`).join(",");
    await fetch(`${base}/ctl`, { method: "POST", body: `1,0,${body}` });
    let seenRun = false;
    for (let i = 0; i < 600; i++) { // up to ~3 min
        await sleep(300);
        const s = (await state()).last;
        if (!s) continue;
        if (s.state >= 2) { console.log(`stop: probe state ${s.state} reason ${s.reason} at t=${s.t} x=${s.x} v=${s.v}`); process.exit(1); }
        if (s.state === 1) seenRun = true;
        if (!seenRun && i >= 60) { console.log(`stop: the program did not start within 18 s (Ready off, outside the area, or the probe was reset) at t=${s.t} x=${s.x}`); process.exit(1); }
        if (seenRun && s.state === 0) break;
    }
    const after = (await state()).last;
    console.log(`${label}: done at t=${after.t} x=${after.x.toFixed(1)} v=${after.v.toFixed(2)}`);
}
