-- Entry point: `lua test/run_all.lua` from any directory.
local dir = (debug.getinfo(1, "S").source:sub(2):match("(.*/)")) or "./"
dofile(dir .. "../src/gp_core.lua")
dofile(dir .. "../../../lib/state_sync.lua")   -- i2f/f2i oracle

local OP = {}
for name, num in io.open(dir .. "../src/ops.txt"):read("a"):gmatch("(%u%w*) (%d+)") do OP[name] = tonumber(num) end

local n, failed = 0, 0
local function check(name, cond)
    n = n + 1
    if not cond then failed = failed + 1; print("FAIL: " .. name) end
end
local function near(a, b) return math.abs(a - b) < 1e-9 end
local function same(a, b) return a == b or (a ~= a and b ~= b) end

-- independent Adler-32 for building messages
local function adler(s)
    local a, b = 1, 0
    for i = 1, #s do a = (a + s:byte(i)) % 65521; b = (b + a) % 65521 end
    return b * 65536 + a
end
local function fmt(x)
    if x == math.huge then return "1e999" elseif x == -math.huge then return "-1e999" end
    return math.type(x) == "integer" and tostring(x) or string.format("%.17g", x)
end
local function msg(kind, nums)
    local t = {}
    for i, x in ipairs(nums or {}) do t[i] = fmt(x) end
    local body = kind .. ":" .. table.concat(t, ",")
    return body .. "*" .. adler(body)
end
local function I(name, d, a, b) return {OP[name], d or 0, a or 0, b or 0} end
local function words(prog)
    local w = {}
    for _, ins in ipairs(prog) do for k = 1, 4 do w[#w + 1] = ins[k] end end
    return w
end

local function fresh(B)
    gp_init()
    gp_budget(B or 1000)
end
-- load a program (list of I(...)), optional constants {addr, val, ...}; N host-visible cells
local function load(prog, N, consts, reset)
    local c = {N or 64, 0}
    for _, w in ipairs(words(prog)) do c[#c + 1] = w end
    local r = {}
    if reset then r[#r + 1] = gp_msg(msg("R")) end
    r[#r + 1] = gp_msg(msg("C", c))
    if consts then r[#r + 1] = gp_msg(msg("M", consts)) end
    r[#r + 1] = gp_msg(msg("K"))
    return table.concat(r, ",")
end
local function zeros() local t = {} for i = 1, 32 do t[i] = 0.0 end return t end
local function bools(gate) local t = {} for i = 1, 32 do t[i] = false end t[32] = gate ~= false return t end
local function tick(inn, inb) return gp_tick(inn or zeros(), inb or bools()) end
local function cell(i) return gp_rec(i) end

-- 1. checksum golden vectors
check("adler K:", gp_adler("K:") == 13762694)
check("adler R:", gp_adler("R:") == 14680205)
check("adler M:0,1", gp_adler("M:0,1") == 59179285)
check("adler C:8,0,22,0,0,0", gp_adler("C:8,0,22,0,0,0") == 357040822)

-- 2. semantics of each computing op (direct values via MEM)
do
    local function eval(inst, init)
        fresh()
        load({inst}, 64, init)
        tick()
        return cell(0)
    end
    local function op1(name, x, expect, label)
        check(label or name, same(eval(I(name, 0, 1), {1, x}), expect))
    end
    local function op2(name, x, y, expect, label)
        check(label or name, same(eval(I(name, 0, 1, 2), {1, x, 2, y}), expect))
    end
    op2("ADD", 2, 3, 5.0); op2("SUB", 2, 3, -1.0); op2("MUL", 2, 3, 6.0)
    op2("DIV", 6, 3, 2.0); op2("DIV", 6, 0, 0.0, "DIV by zero")
    op2("MIN", 2, 3, 2.0); op2("MAX", 2, 3, 3.0)
    op1("ABS", -4, 4.0); op1("FLR", 2.7, 2.0); op1("FLR", -2.2, -3.0)
    op1("SQRT", 9, 3.0); op1("SQRT", -9, 0.0, "SQRT negative")
    op1("SIN", 0, 0.0)
    op2("LT", 1, 2, 1.0); op2("LT", 2, 2, 0.0, "LT equal"); op2("LE", 2, 2, 1.0)
    op2("MUL", 1e20, 1e20, 1e30, "MUL clamps to 1e30")
    op2("SUB", -1e20, 1e20 * 1e20, -1e30, "SUB clamps to -1e30")
    -- CLP: d is also input
    fresh(); load({I("CLP", 0, 1, 2)}, 64, {0, 5, 1, 0, 2, 3}); tick()
    check("CLP high", cell(0) == 3.0)
    fresh(); load({I("CLP", 0, 1, 2)}, 64, {0, -5, 1, 0, 2, 3}); tick()
    check("CLP low", cell(0) == 0.0)
    fresh(); load({I("CLP", 0, 1, 2)}, 64, {0, 5, 1, 4, 2, 3}); tick()
    check("CLP reversed bounds -> hi", cell(0) == 3.0)
    -- CMOV
    fresh(); load({I("CMOV", 0, 1, 2)}, 64, {0, 9, 1, 7, 2, 1}); tick()
    check("CMOV taken", cell(0) == 7.0)
    fresh(); load({I("CMOV", 0, 1, 2)}, 64, {0, 9, 1, 7, 2, 0}); tick()
    check("CMOV not taken", cell(0) == 9.0)
    -- bit ops
    op2("AND", 12, 10, 8.0); op2("OR", 12, 10, 14.0); op2("XOR", 12, 10, 6.0)
    op2("SHL", 1, 31, 2147483648.0); op2("SHL", 1, 32, 1.0, "SHL amount mod 32")
    op2("SHL", 3, 31, 2147483648.0, "SHL truncates to 32 bits")
    op2("SHR", 2147483648, 31, 1.0)
    op2("AND", -1, 255, 255.0, "AND negative wraps mod 2^32")
    op2("AND", 4294967296 + 5, 7, 5.0, "AND wraps mod 2^32")
end

-- 3. memory: indirect access, sparse, address wrap at 65536
do
    fresh()
    load({I("ST", 1, 2), I("LD", 0, 1)}, 64, {1, 70000, 2, 42})
    tick()
    check("ST/LD with address wrap", cell(0) == 42.0 and gp_rec(70000 % 65536) == 42.0)
    fresh()
    load({I("LD", 0, 1)}, 64, {1, -1, 65535, 7}); tick()
    check("negative address wraps to 65535", cell(0) == 7.0)
    fresh()
    local c = {}
    for k = 1, 200 do c[#c + 1] = (k * 311) % 65536; c[#c + 1] = k end
    load({I("NOP")}, 64, c); tick()
    local all = true
    for k = 1, 200 do if gp_rec((k * 311) % 65536) ~= k then all = false end end
    check("sparse writes read back", all)
end

-- 4. ports
do
    fresh()
    load({I("PLD", 0, 0), I("PLD", 1, 33), I("PST", 0, 0), I("PST", 33, 1), I("PST", 62, 1), I("PST", 63, 1)})
    local inn = zeros(); inn[1] = 2.5
    local inb = bools(); inb[2] = true
    local on, ob = tick(inn, inb)
    check("PLD number", cell(0) == 2.5)
    check("PLD bool is 1/0", cell(1) == 1.0)
    check("PST number out", on[1] == 2.5)
    check("PST bool out (M[a] > 0)", ob[2] == true)
    check("PST to HB/CUT ignored", ob[31] == true and ob[32] == false)   -- HB toggled by tick, CUT untouched
    -- PLD wraps port number: 64 -> 0
    fresh(); load({I("PLD", 0, 64)}); inn = zeros(); inn[1] = 9; tick(inn)
    check("port number wraps", cell(0) == 9.0)
    -- input sampled at tick start: constant inside the tick (tick passes one table)
    fresh(); load({I("PLD", 0, 0), I("PLD", 1, 0), I("SUB", 2, 0, 1)}); tick(inn)
    check("input constant within tick", cell(2) == 0.0)
    -- output holds last value
    fresh(); load({I("PLD", 0, 0), I("PST", 0, 0)}); inn = zeros(); inn[1] = 4
    tick(inn); inn[1] = 5
    local on2 = tick(inn)
    check("output follows", on2[1] == 5.0)
end

-- 5. stopped when not loaded; heartbeat
do
    fresh()
    local on, ob = tick()
    local _, hb, ncode = gp_stat()
    check("not loaded: stopped", ncode == 0 and hb == false and ob[31] == false and on[1] == 0.0)
    load({I("NOP")}); local _, ob1 = tick(); local _, ob2 = tick()
    check("heartbeat toggles per completed tick", ob1[31] ~= ob2[31])
end

-- 6. budget
do
    fresh(5)
    load({I("JMP", 0, 0)}); tick()
    local ab = gp_stat()
    check("infinite loop aborted", ab == 1)
    -- exactly B instructions completes, B+1 aborts
    fresh(3); load({I("NOP"), I("NOP"), I("NOP")}); tick()
    check("exactly B completes", (gp_stat()) == 0)
    fresh(3); load({I("NOP"), I("NOP"), I("NOP"), I("NOP")}); tick()
    check("B+1 aborts", (gp_stat()) == 1)
    fresh(3); load({I("NOP"), I("NOP"), I("HALT"), I("NOP")}); tick()
    check("HALT counts and ends the tick", (gp_stat()) == 0)
    -- abort discards PST, keeps previous output, does not toggle HB, keeps partial memory writes
    fresh(2)
    load({I("PLD", 0, 0), I("PST", 0, 0), I("ADD", 5, 0, 0), I("NOP")})
    local inn = zeros(); inn[1] = 3
    local on = tick(inn)
    check("aborted tick: PST discarded", on[1] == 0.0)
    local _, hb, _, _ = gp_stat()
    check("aborted tick: HB not toggled", hb == false)
    check("aborted tick: memory not rolled back", cell(0) == 3.0)
    fresh(10); load({I("PLD", 0, 0), I("PST", 0, 0)})
    tick(inn)
    gp_budget(1)
    inn[1] = 8
    local on3 = tick(inn)
    check("abort keeps last completed output", on3[1] == 3.0 and (gp_stat()) == 1)
end

-- 7. state: low-pass filter equals a Lua reference tick by tick
do
    fresh()
    load({I("PLD", 0, 0), I("SUB", 3, 0, 1), I("MUL", 3, 3, 2), I("ADD", 1, 1, 3), I("PST", 0, 1)},
        64, {2, 0.25})
    local y = 0.0
    local ok = true
    for t = 1, 40 do
        local x = (t % 10 < 5) and 1.0 or -0.5
        y = y + (x - y) * 0.25
        local inn = zeros(); inn[1] = x
        local on = tick(inn)
        if math.abs(on[1] - y) > 1e-12 then ok = false end
    end
    check("low-pass matches reference", ok)
end

-- 8. injection
do
    fresh()
    -- changes apply at the next tick boundary, only after K
    local prog = {I("PLD", 0, 0), I("PST", 0, 0)}
    load(prog)
    local inn = zeros(); inn[1] = 6
    local on = tick(inn)
    check("code applied at next tick", on[1] == 6.0)
    -- checksum mismatch discards staged and keeps running program
    local c = {64, 0}
    for _, w in ipairs(words({I("NOP")})) do c[#c + 1] = w end
    local bad = msg("C", c):gsub("%*%d+$", "*1")
    check("E1 on checksum mismatch", gp_msg(bad) == "E1")
    check("K after E1 changes nothing", gp_msg(msg("K")) == "OK")
    on = tick(inn); check("running program unchanged after E1", on[1] == 6.0)
    -- malformed
    check("E2 odd pairs", gp_msg(msg("M", {1, 2, 3})) == "E2")
    check("E2 off mismatch", gp_msg(msg("C", {64, 4, 0, 0, 0, 0})) == "E2")
    check("E2 words not multiple of 4", gp_msg(msg("C", {64, 0, 0, 0, 0})) == "E2")
    check("E2 no checksum", gp_msg("K:") == "E2")
    check("E2 unknown kind", gp_msg(msg("Z")) == "E2")
    check("E2 bad number", gp_msg("M:a,b*" .. adler("M:a,b")) == "E2")
    -- staged ops lost on error
    fresh(); load({I("NOP")}, 64, {5, 11}); tick()
    gp_msg(msg("M", {5, 99})); gp_msg("garbage")
    gp_msg(msg("K")); tick()
    check("error clears staged ops", cell(5) == 11.0)
    -- MEM only: code and other cells unchanged
    fresh(); load({I("ADD", 1, 1, 2)}, 64, {1, 10, 2, 1}); tick()
    gp_msg(msg("M", {2, 5})); gp_msg(msg("K")); tick()
    check("MEM-only commit keeps state and code", cell(1) == 16.0)
    -- CODE only: memory kept
    gp_msg(msg("C", (function() local c2 = {64, 0} for _, w in ipairs(words({I("NOP")})) do c2[#c2 + 1] = w end return c2 end)()))
    gp_msg(msg("K")); tick()
    check("CODE-only commit keeps memory", cell(1) == 16.0)
    -- RESET zeroes memory
    gp_msg(msg("R")); gp_msg(msg("K")); tick()
    check("RESET zeroes memory", cell(1) == 0.0 and cell(2) == 0.0)
    -- chunked CODE
    fresh()
    local w = words({I("PLD", 0, 0), I("PST", 0, 0)})
    local c1 = {64, 0}; for k = 1, 4 do c1[#c1 + 1] = w[k] end
    local c2 = {64, 4}; for k = 5, 8 do c2[#c2 + 1] = w[k] end
    check("chunk 1", gp_msg(msg("C", c1)) == "OK")
    check("chunk 2", gp_msg(msg("C", c2)) == "OK")
    gp_msg(msg("K")); local inn2 = zeros(); inn2[1] = 3; on = tick(inn2)
    check("chunked code runs", on[1] == 3.0)
    -- code identity = Adler over the concatenated C message texts
    local t1, t2 = msg("C", c1):gsub("%*%d+$", ""), msg("C", c2):gsub("%*%d+$", "")
    local _, _, _, id = gp_stat()
    check("code identity", id == adler(t1 .. t2))
    -- empty code unloads
    gp_msg(msg("C", {64, 0})); gp_msg(msg("K")); tick()
    local _, _, nc = gp_stat(); check("empty C unloads", nc == 0)
    -- N and host-visible record
    fresh(); load({I("NOP")}, 7); tick()
    check("N from CODE", gp_n() == 7)
end

-- 9. guard and health gate
do
    fresh()
    load({I("PLD", 0, 0), I("PST", 0, 0), I("PST", 1, 0), I("PST", 33, 0)})
    gp_guard(0, -1.0, 1.0)
    local inn = zeros(); inn[1] = 5
    local on, ob = tick(inn)
    check("guard clamps", on[1] == 1.0 and on[2] == 5.0)
    -- gate OFF: all zero/OFF, HB/CUT still out; ON again restores last values
    gp_cut(true)
    on, ob = tick(inn, bools(false))
    check("gate off: zeros", on[1] == 0.0 and on[2] == 0.0 and ob[2] == false)
    check("gate off: HB and CUT still out", ob[32] == true and (ob[31] == true or ob[31] == false))
    on, ob = tick(inn, bools(true))
    check("gate on restores outputs", on[2] == 5.0 and ob[2] == true)
    -- program keeps running while gated: state advances
    fresh(); load({I("ADD", 0, 0, 1)}, 64, {1, 1})
    tick(zeros(), bools(false)); tick(zeros(), bools(false))
    check("program runs while gated", cell(0) == 2.0)
end

-- 10. NaN/inf transport and bit fidelity vs state_sync
do
    local patterns = {0, 1, 0x3F800000, 0x7F800000, 0xFF800000, 0x7FC00000, 0x7F800001, 0xFFFFFFFF,
        0x00000001, 0x007FFFFF, 0x80000000, 0x12345678, 0xDEADBEEF}
    local ok = true
    for _, pat in ipairs(patterns) do
        -- I2F -> MOV -> LD/ST round trip -> F2I
        fresh()
        load({I("I2F", 1, 0), I("MOV", 2, 1), I("ST", 3, 2), I("LD", 4, 3), I("CMOV", 5, 4, 6), I("F2I", 7, 4)},
            64, {0, pat, 3, 100})
        tick()
        local expect = f2i(i2f(pat))
        if not same(cell(7), expect + 0.0) then ok = false; print("  pattern", string.format("%08x", pat), cell(7), expect) end
    end
    check("F2I(I2F(n)) matches state_sync f2i(i2f(n)) through MOV/ST/LD", ok)
    -- PST of NaN passes raw to an unguarded output
    fresh(); load({I("I2F", 1, 0), I("PST", 0, 1)}, 64, {0, 0x7FC00000}); local on = tick()
    check("PST passes NaN raw", on[1] ~= on[1])
    -- computing ops read NaN as 0 and never produce NaN
    fresh(); load({I("I2F", 1, 0), I("ADD", 2, 1, 3), I("MUL", 4, 1, 3), I("MIN", 5, 1, 3), I("LT", 6, 1, 3),
        I("FLR", 7, 1), I("LD", 8, 1), I("SHL", 9, 3, 1)}, 64, {0, 0x7FC00000, 3, 5})
    tick()
    check("NaN reads as 0 in computing ops", cell(2) == 5.0 and cell(4) == 0.0 and cell(5) == 0.0
        and cell(6) == 1.0 and cell(7) == 0.0 and cell(9) == 5.0)
    -- inf reads as 1e30
    fresh(); load({I("I2F", 1, 0), I("ADD", 2, 1, 3), I("MUL", 4, 1, 3)}, 64, {0, 0x7F800000, 3, 5})
    tick()
    check("inf reads as 1e30", cell(2) == 1e30 and cell(4) == 1e30)
end

-- 11. totality: random programs never raise errors
do
    math.randomseed(12345)
    local specials = {0, 1, -1, 0.5, 1e30, -1e30, 1e300, -1e300, 4294967295, 4294967296, 65535, 65536, 65537,
        -65536, 2 ^ 53, 1e999, -1e999, 3.14159, 123456789.123}
    local function rnd()
        local r = math.random()
        if r < 0.3 then return specials[math.random(#specials)] end
        if r < 0.6 then return math.random(-70, 70) end
        return (math.random() - 0.5) * 10 ^ math.random(0, 12)
    end
    local ok, err = true, nil
    for trial = 1, 300 do
        fresh(math.random(1, 300))
        local c = {64, 0}
        for _ = 1, 4 * math.random(1, 40) do c[#c + 1] = rnd() end
        local m = {}
        for _ = 1, 40 do m[#m + 1] = math.random(0, 80); m[#m + 1] = rnd() end
        local good, e = pcall(function()
            if gp_msg(msg("C", c)) ~= "OK" or gp_msg(msg("M", m)) ~= "OK" then error("rejected") end
            gp_msg(msg("K"))
            for t = 1, 5 do
                local inn = zeros(); for i = 1, 32 do inn[i] = rnd() end
                tick(inn)
                for i = 0, 63 do local v = gp_rec(i); if v ~= v and false then error("nan") end end
            end
        end)
        if not good then ok = false; err = e; break end
    end
    check("random programs never error" .. (err and (": " .. tostring(err)) or ""), ok)
end

print(string.format("%d checks, %d failed", n, failed))
os.exit(failed == 0 and 0 or 1)
