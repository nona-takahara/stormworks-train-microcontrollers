-- Entry point: `lua test/run_all.lua` from any directory.
local dir = (debug.getinfo(1, "S").source:sub(2):match("(.*/)")) or "./"
dofile(dir .. "../src/probe_core.lua")

SITE_LO, SITE_HI = 0, 10000


-- ps(delay, len, vmin, motor c0..ci, brake c0..ci, ...) : old 10-number segments expanded
-- to the 17-number segments of probe_set (vend 0, no ramp, no sine).
local function ps(delay, ...)
    local a, out = {...}, {}
    for i = 1, #a, 10 do
        for _, x in ipairs({a[i], 0, a[i + 1], a[i + 2], a[i + 3], a[i + 4], a[i + 5], 0, 0, 0,
            a[i + 6], a[i + 7], a[i + 8], a[i + 9], 0, 0, 0}) do out[#out + 1] = x end
    end
    probe_set(delay, table.unpack(out))
end

local n, failed = 0, 0
local function check(name, cond)
    n = n + 1
    if not cond then failed = failed + 1; print("FAIL: " .. name) end
end
local function near(a, b) return math.abs(a - b) < 1e-9 end

-- Each scenario starts from a fresh process state: IDLE, no jog, dir unknown.
-- The core keeps its state in upvalues, so reload it per scenario.
local function fresh()
    dofile(dir .. "../src/probe_core.lua")
end
local function run(ticks, x, v, ready)
    local m, b, s, r, t
    for _ = 1, ticks do m, b, s, r, t = probe_tick(x, 0, v, ready) end
    return m, b, s, r, t
end

-- shape: constant / proportional / inverse, clamped (v is |speed|)
fresh(); ps(0, 10, 1, 0.1, 0, 0, 0, 0, 0, 0, 0)
local m = run(1, 5000, 10, 1)
check("constant term", near(m, 0.1))
fresh(); ps(0, 10, 1, 0, 0.01, 0, 0, 0, 0, 0, 0)
check("proportional to |v|", near(run(1, 5000, -20, 1), 0.2))
fresh(); ps(0, 10, 2, 0, 0, 0, 0, 0, 0, 0, 1)
local _, b = run(1, 5000, 4, 1)
check("inverse term", near(b, 0.25))
_, b = (function() fresh(); ps(0, 10, 2, 0, 0, 0, 0, 0, 0, 0, 1); return run(1, 5000, 0, 1) end)()
check("inverse term floored by vmin", near(b, 0.5))
fresh(); ps(0, 10, 1, 9, 0, 0, 0, 9, 0, 0, 0)
local m2, b2 = run(1, 5000, 10, 1)
check("no saturation at the vehicle range", near(m2, 9) and near(b2, 9))
fresh(); ps(0, 10, 1, -9e9, 0, 0, 0, 9e9, 0, 0, 0)
local m3, b3 = run(1, 5000, 10, 1)
check("overflow bound at +-1e6", near(m3, -1e6) and near(b3, 1e6))

-- window: output only inside [start, start+len), then back to IDLE
fresh(); ps(3, 4, 1, 0.1, 0, 0, 0, 0, 0, 0, 0)
local ms, st = {}, nil
for i = 1, 10 do local mm; mm, _, st = probe_tick(5000, 0, 10, 1); ms[i] = mm end
check("window starts after delay", ms[2] == 0 and near(ms[4], 0.1))
check("window ends and returns to idle", ms[8] == 0 and st == 0)

-- program: segments run back to back, no gap, then IDLE
fresh(); ps(0, 3, 1, 0.1, 0, 0, 0, 0, 0, 0, 0,   2, 1, 0.2, 0, 0, 0, 0, 0, 0, 0)
local seq, last_st = {}, nil
for i = 1, 7 do local mm; mm, _, last_st = probe_tick(5000, 0, 10, 1); seq[i] = mm end
check("two segments run back to back", seq[1] == 0.1 and seq[3] == 0.1 and seq[4] == 0.2 and seq[5] == 0.2 and seq[6] == 0)
check("program ends in idle", last_st == 0)
fresh(); ps(0, 5, 1, 0.1, 0, 0, 0, 0, 0, 0, 0); probe_tick(5000, 0, 10, 1)
ps(0, 5, 1, 0.9, 0, 0, 0, 0, 0, 0, 0)
check("probe_set is ignored while running", near(select(1, probe_tick(5000, 0, 10, 1)), 0.1))

-- start refusal: ready off / outside area / site limits unset
fresh(); ps(0, 10, 1, 0.1, 0, 0, 0, 0, 0, 0, 0)
check("no start without ready", select(3, run(1, 5000, 10, 0)) == 0)
fresh(); ps(0, 10, 1, 0.1, 0, 0, 0, 0, 0, 0, 0)
check("no start outside area", select(3, run(1, 100, 0, 1)) == 0)
SITE_LO = nil
fresh(); ps(0, 10, 1, 0.1, 0, 0, 0, 0, 0, 0, 0)
check("no start while limits unset", select(1, run(1, 5000, 0, 1)) == 0)
SITE_LO = 0

-- aborts: each condition, brake held, motor cut
local function abort_case(x, v, ready)
    fresh(); ps(0, 100, 1, 0.1, 0, 0, 0, 0, 0, 0, 0)
    run(2, 5000, 10, 1)
    return run(1, x, v, ready)
end
local am, ab, as, ar = abort_case(5000, 10, 0)
check("abort: ready off", as == 2 and ar == 1 and am == 0 and ab == 1)
_, _, as, ar = abort_case(9900, 10, 1)
check("abort: outside area (low speed margin 200 m)", as == 2 and ar == 2)
_, _, as, ar = abort_case(5000, 56, 1)
check("abort: over speed", as == 2 and ar == 3)
_, _, as, ar = abort_case(9700, 50, 1)
check("abort margin grows with speed", as == 2 and ar == 2)
check("margin: floor and growth", near(probe_margin(0), 200) and probe_margin(50) > 200)

-- ack only while stopped; abort holds brake until then
fresh(); ps(0, 100, 1, 0.1, 0, 0, 0, 0, 0, 0, 0)
run(2, 5000, 10, 1); run(1, 5000, 10, 0)
probe_ack(5); local _, b3, s3 = run(1, 5000, 5, 1)
check("ack ignored while moving", s3 == 2 and b3 == 1)
probe_ack(0); _, b3, s3 = run(1, 5000, 0, 1)
check("ack accepted when stopped", s3 == 0 and b3 == 0)

-- jog: refused when dir unknown, toward-area only, speed cap, timeout
fresh(); probe_jog(0.2, 0, 5)
check("jog refused while dir unknown", run(1, -500, 0, 0) == 0)
fresh(); probe_dir(1); probe_jog(0.2, 0, 3)
check("jog toward area passes", near(run(1, -500, 0, 0), 0.2))
check("jog times out", run(3, -500, 0, 0) == 0)
fresh(); probe_dir(1); probe_jog(-0.2, 0, 5)
check("jog away from area is cut", run(1, -500, 0, 0) == 0)
fresh(); probe_dir(-1); probe_jog(-0.2, 0, 5)
check("jog follows dir", near(run(1, -500, 0, 0), -0.2))
fresh(); probe_dir(1); probe_jog(0.2, 0, 5)
check("jog from the high side", run(1, 10500, 0, 0) == 0)
fresh(); probe_dir(1); probe_jog(-0.2, 0, 5)
check("jog from the high side, toward", near(run(1, 10500, 0, 0), -0.2))
fresh(); probe_dir(1); probe_jog(0.2, 0, 5)
check("jog speed cap", run(1, -500, 6, 0) == 0)
fresh(); probe_dir(1); probe_jog(0.2, 0, 5)
check("jog ends inside area", run(1, 5000, 0, 0) == 0)

-- fall: y drops in one tick -> FALLEN (3, reason 4), terminal, even from IDLE
-- or ABORT; slopes do not trigger it
fresh(); probe_tick(5000, 10, 0, 1)
local _, fb, fs_, fr = probe_tick(5000, 8, 0, 1)
check("fall -> FALLEN from idle", fs_ == 3 and fr == 4 and fb == 1)
probe_ack(0); ps(0, 10, 1, 0.1, 0, 0, 0, 0, 0, 0, 0); probe_dir(1); probe_jog(0.2, 0, 5)
local fm
fm, fb, fs_ = probe_tick(-500, 8, 0, 1)
check("FALLEN ignores ack, set and jog", fs_ == 3 and fm == 0 and fb == 1)
fresh(); ps(0, 100, 1, 0.1, 0, 0, 0, 0, 0, 0, 0)
run(2, 5000, 10, 1); run(1, 5000, 10, 0)
probe_tick(5000, 0, 0, 1)
fs_ = select(3, probe_tick(5000, -3, 0, 1))
check("fall during ABORT -> FALLEN", fs_ == 3)
probe_ack(0)
check("ack does not release FALLEN", select(3, probe_tick(5000, -3, 0, 1)) == 3)
fresh(); probe_tick(5000, 10, 50, 1)
check("gentle slope is not a fall", select(3, probe_tick(5000, 9.95, 50, 1)) == 0)


-- segment fields: vend (both signs), ramp ct, sine A/f, segment number in reason, cancel
local function seg17(len, vend, vm, m, b) -- m, b: 7 numbers each
    local o = {len, vend, vm}
    for _, x in ipairs(m) do o[#o + 1] = x end
    for _, x in ipairs(b) do o[#o + 1] = x end
    return o
end
local function setp(delay, ...)
    local all = {}
    for _, g in ipairs({...}) do for _, x in ipairs(g) do all[#all + 1] = x end end
    probe_set(delay, table.unpack(all))
end
local Z = {0, 0, 0, 0, 0, 0, 0}

fresh(); setp(0, seg17(100, 5, 1, {0.1, 0, 0, 0, 0, 0, 0}, Z), seg17(100, 0, 1, {0.2, 0, 0, 0, 0, 0, 0}, Z))
local mm, _, ss, rr = probe_tick(5000, 0, 1, 1)
check("segment number is reported in RUN", mm == 0.1 and ss == 1 and rr == 1)
mm, _, ss, rr = probe_tick(5000, 0, 5, 1)
check("vend > 0: next segment once |v| reaches it", mm == 0.2 and rr == 2)

fresh(); setp(0, seg17(100, -0.1, 1, Z, {1, 0, 0, 0, 0, 0, 0}), seg17(100, 0, 1, {0.3, 0, 0, 0, 0, 0, 0}, Z))
_, b4 = probe_tick(5000, 0, 3, 1)
check("vend < 0: holds while still fast", b4 == 1)
mm = probe_tick(5000, 0, 0.05, 1)
check("vend < 0: next segment once slowed to it", mm == 0.3)

fresh(); setp(0, seg17(10, 0, 1, {0.1, 0, 0, 0, 0, 0, 0}, Z), seg17(200, 0, 1, {0, 0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0.6, 0, 0}))
run(10, 5000, 1, 1)  -- first segment: ticks 1..10 (the 11th tick is the second one's tau = 0)
local _, b0 = probe_tick(5000, 0, 1, 1)
local _, b1 = run(60, 5000, 1, 1)
check("ramp term ct*tau (tau in s; 0 at the segment start)", near(b0, 0) and near(b1, 0.6))

fresh(); setp(0, seg17(200, 0, 1, {0, 0, 0, 0, 0, 0.2, 1}, Z))
local ms = {}
for i = 1, 40 do ms[i] = probe_tick(5000, 0, 1, 1) end
check("sine term A*sin(2*pi*f*tau)", near(ms[1], 0) and near(ms[16], 0.2 * math.sin(2 * math.pi * 15 / 60)) and near(ms[31], 0.2 * math.sin(2 * math.pi * 30 / 60)))

fresh(); ps(0, 100, 1, 0.1, 0, 0, 0, 0, 0, 0, 0)
run(3, 5000, 1, 1); probe_cancel()
local cm, cb, cs = run(1, 5000, 1, 1)
check("cancel returns to idle with zero outputs", cm == 0 and cb == 0 and cs == 0)
fresh(); ps(5, 100, 1, 0.1, 0, 0, 0, 0, 0, 0, 0); probe_cancel()
check("cancel also disarms a program that has not started", run(10, 5000, 1, 1) == 0)


-- NaN (0/0) must not saturate: vmin = 0 at v = 0 with ci = 0
fresh(); setp(0, seg17(50, 0, 0, Z, Z))
local nm, nb = probe_tick(5000, 0, 0, 1)
check("0/0 does not saturate to the bound", nm == 0 and nb == 0)

-- short or malformed commands never raise
fresh()
local okcalls = pcall(function()
    probe_set(); probe_set(nil, 1, 2); probe_dir(); probe_jog(); probe_jog(0.1); probe_ack(); probe_cancel()
    for _ = 1, 50 do probe_tick(5000, 0, 1, 1) end
    probe_set(0, 5, 0, 1, 0.1) -- an old, short segment
    for _ = 1, 20 do probe_tick(5000, 0, 1, 1) end
end)
check("malformed calls do not raise", okcalls)

-- IDLE protection: outside the area and fast -> ABORT (reason 2); over speed -> reason 3; armed is cleared
fresh(); probe_dir(1)
check("idle, outside the area at 11 m/s -> abort", select(3, probe_tick(-500, 0, 11, 1)) == 2)
fresh(); ps(0, 10, 1, 0.1, 0, 0, 0, 0, 0, 0, 0)
probe_tick(-500, 0, 11, 1)             -- aborts; the armed program must be dropped
probe_ack(0)
check("a stale armed program does not start after the ack", select(3, run(5, 5000, 0, 1)) == 0)
fresh(); local _, _, s1, r1 = probe_tick(5000, 0, 56, 1)
check("idle over speed -> abort reason 3", s1 == 2 and r1 == 3)
fresh(); probe_dir(1); probe_jog(0.2, 0, 5)
check("jog at 5 m/s outside the area still passes", near(select(1, probe_tick(-500, 0, 5, 1)), 0.2))

-- SITE_DIR survives a reload (probe_dir overrides it)
SITE_DIR = 1; fresh(); probe_jog(0.2, 0, 3)
check("SITE_DIR lets the jog work without probe_dir", near(select(1, probe_tick(-500, 0, 0, 1)), 0.2))
fresh(); probe_dir(-1); probe_jog(0.2, 0, 3)
check("probe_dir overrides SITE_DIR", select(1, probe_tick(-500, 0, 0, 1)) == 0)
SITE_DIR = nil

print(string.format("%d checks, %d failed", n, failed))
os.exit(failed == 0 and 0 or 1)
