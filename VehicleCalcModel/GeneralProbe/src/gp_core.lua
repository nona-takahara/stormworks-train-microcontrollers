-- General probe VM: pure logic, no Stormworks API (see BYTECODE_SPEC.md).
-- Entry layer (composite/HTTP) calls the global gp_* functions below.
-- API: gp_init() gp_budget(B) gp_cut(on) gp_guard(port, lo, hi)
--      gp_msg(line) -> "OK"|"E1"|"E2"
--      gp_tick(in_num, in_bool) -> out_num, out_bool   (tables 1..32)
--      gp_n() gp_rec(i)   host-visible head of M (N values)
--      gp_stat() -> aborts, hb, ncode, code_id    gp_instr() -> instructions of the last tick

local KINDS, MEMS, NPORT = 30, 65536, 64
local M, ncode, N, B
local cop, cd, ca, cb       -- decoded code: op, d, a, b (roles resolved at load)
local pending               -- committed batches, applied at the next tick start
local staged_ops, staged_code, staged_N, staged_adler_a, staged_adler_b
local aborts, hb, cut, code_id
local hold_n, hold_b, glo, ghi
local pst_p, pst_v
local cnt  -- instructions executed by the last tick

-- Values that computing instructions read: NaN -> 0, +-inf -> +-1e30.
local function nz(x)
    if x ~= x then return 0.0 end
    if x > 1e30 then return 1e30 end
    if x < -1e30 then return -1e30 end
    return x
end

-- Result of a computing instruction: always a finite float.
local function norm(r)
    if r ~= r then return 0.0 end
    if r > 1e30 then return 1e30 end
    if r < -1e30 then return -1e30 end
    return r + 0.0
end

local function addr(x) return math.tointeger(math.floor(nz(x)) % MEMS) end
local function u32(x) return math.tointeger(math.floor(nz(x)) % 4294967296) end

local function adler_feed(a, b, s)
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return a, b
end

function gp_adler(s)
    local a, b = adler_feed(1, 0, s)
    return b * 65536 + a
end

local function clear_staged()
    staged_ops, staged_code, staged_N = {}, nil, 0
    staged_adler_a, staged_adler_b = 1, 0
end

function gp_init()
    M, ncode, N, B, cnt = {}, 0, 0, 1000, 0
    cop, cd, ca, cb = {}, {}, {}, {}
    pending = {}
    aborts, hb, cut, code_id = 0, false, false, 0
    hold_n, hold_b, glo, ghi = {}, {}, {}, {}
    for i = 1, 32 do hold_n[i] = 0.0; hold_b[i] = false end
    clear_staged()
end

function gp_budget(b) B = math.max(1, math.min(65535, math.floor(b))) end
function gp_cut(on) cut = on and true or false end
function gp_guard(port, lo, hi) glo[port], ghi[port] = lo, hi end
function gp_n() return N end
function gp_rec(i) return M[i] or 0.0 end
function gp_stat() return aborts, hb, ncode, code_id end
function gp_instr() return cnt end

-- Message layer ------------------------------------------------------------

local function parse_numbers(payload)
    local t = {}
    if payload == "" then return t end
    for tok in (payload .. ","):gmatch("([^,]*),") do
        local v = tonumber(tok)
        if v == nil then return nil end
        t[#t + 1] = v
    end
    return t
end

local function stage(kind, nums, prefix)
    if kind == "R" then
        if #nums ~= 0 then return false end
        staged_ops[#staged_ops + 1] = false
    elseif kind == "M" then
        if #nums % 2 ~= 0 then return false end
        staged_ops[#staged_ops + 1] = nums
    elseif kind == "C" then
        if #nums < 2 or (#nums - 2) % 4 ~= 0 then return false end
        local off = nums[2]
        if off == 0 then
            staged_code = {}
            staged_adler_a, staged_adler_b = 1, 0
        elseif staged_code == nil or off ~= #staged_code then
            return false
        end
        staged_N = nums[1]
        for i = 3, #nums do staged_code[#staged_code + 1] = nums[i] end
        staged_adler_a, staged_adler_b = adler_feed(staged_adler_a, staged_adler_b, prefix)
    elseif kind == "K" then
        if #nums ~= 0 then return false end
        pending[#pending + 1] = {staged_ops, staged_code, staged_N,
            staged_adler_b * 65536 + staged_adler_a}
        clear_staged()
    else
        return false
    end
    return true
end

local function fail(code)
    clear_staged()
    return code
end

function gp_msg(line)
    local star = line:match(".*()%*")
    if not star then return fail("E2") end
    local prefix, sumtxt = line:sub(1, star - 1), line:sub(star + 1)
    if not sumtxt:match("^%d+$") then return fail("E2") end
    if gp_adler(prefix) ~= math.tointeger(tonumber(sumtxt)) then return fail("E1") end
    local kind, payload = prefix:match("^(%u):(.*)$")
    local nums = kind and parse_numbers(payload)
    if not nums or not stage(kind, nums, prefix) then return fail("E2") end
    return "OK"
end

-- Commit ---------------------------------------------------------------------

local function load_code(words, n)
    local nw = #words // 4
    ncode, cop, cd, ca, cb = nw, {}, {}, {}, {}
    N = math.max(0, math.min(MEMS, math.floor(nz(n))))
    for i = 1, nw do
        local w = (i - 1) * 4
        local op = math.floor(nz(words[w + 1])) % KINDS
        local d, a, b = words[w + 2], words[w + 3], words[w + 4]
        if op == 18 then       -- PLD: a = port
            d, a, b = addr(d), math.floor(nz(a)) % NPORT, 0
        elseif op == 19 then   -- PST: d = port, a = address
            d, a, b = math.floor(nz(d)) % NPORT, addr(a), 0
        elseif op == 20 or op == 21 then   -- JMP/JGZ: a = target
            d, a, b = 0, math.floor(nz(a)) % nw, addr(b)
        else
            d, a, b = addr(d), addr(a), addr(b)
        end
        cop[i], cd[i], ca[i], cb[i] = op, d, a, b
    end
end

local function apply_batch(batch)
    local ops, code, n, id = batch[1], batch[2], batch[3], batch[4]
    for _, op in ipairs(ops) do
        if op == false then
            M = {}
        else
            for i = 1, #op, 2 do M[addr(op[i])] = op[i + 1] end
        end
    end
    if code then
        if #code == 0 then ncode, N, cop, cd, ca, cb = 0, math.max(0, math.min(MEMS, math.floor(nz(n)))), {}, {}, {}, {}
        else load_code(code, n) end
        code_id = id
    end
end

-- Execution --------------------------------------------------------------------

local function port_in(p, inn, inb)
    if p < 32 then return inn[p + 1] or 0.0 end
    return inb[p - 31] and 1.0 or 0.0
end

-- Runs one pass. Returns true when completed within the budget.
local function run(inn, inb)
    local pc, np = 0, 0
    cnt = 0
    while pc < ncode do
        if cnt >= B then return false end
        cnt = cnt + 1
        local op, d, a, b = cop[pc + 1], cd[pc + 1], ca[pc + 1], cb[pc + 1]
        pc = pc + 1
        if op == 0 then -- NOP
        elseif op == 1 then M[d] = M[a] or 0.0
        elseif op == 2 then M[d] = norm(nz(M[a] or 0) + nz(M[b] or 0))
        elseif op == 3 then M[d] = norm(nz(M[a] or 0) - nz(M[b] or 0))
        elseif op == 4 then M[d] = norm(nz(M[a] or 0) * nz(M[b] or 0))
        elseif op == 5 then
            local y = nz(M[b] or 0)
            M[d] = y == 0 and 0.0 or norm(nz(M[a] or 0) / y)
        elseif op == 6 then
            local x, y = nz(M[a] or 0), nz(M[b] or 0)
            M[d] = norm(x < y and x or y)
        elseif op == 7 then
            local x, y = nz(M[a] or 0), nz(M[b] or 0)
            M[d] = norm(x > y and x or y)
        elseif op == 8 then M[d] = norm(math.abs(nz(M[a] or 0)))
        elseif op == 9 then M[d] = norm(math.floor(nz(M[a] or 0)))
        elseif op == 10 then
            local x = nz(M[a] or 0)
            M[d] = x < 0 and 0.0 or norm(math.sqrt(x))
        elseif op == 11 then M[d] = norm(math.sin(nz(M[a] or 0)))
        elseif op == 12 then
            local x, lo, hi = nz(M[d] or 0), nz(M[a] or 0), nz(M[b] or 0)
            if lo > hi then x = hi else x = x < lo and lo or (x > hi and hi or x) end
            M[d] = norm(x)
        elseif op == 13 then M[d] = nz(M[a] or 0) < nz(M[b] or 0) and 1.0 or 0.0
        elseif op == 14 then M[d] = nz(M[a] or 0) <= nz(M[b] or 0) and 1.0 or 0.0
        elseif op == 15 then
            if nz(M[b] or 0) > 0 then M[d] = M[a] or 0.0 end
        elseif op == 16 then M[d] = M[addr(M[a] or 0)] or 0.0
        elseif op == 17 then M[addr(M[d] or 0)] = M[a] or 0.0
        elseif op == 18 then M[d] = port_in(a, inn, inb)
        elseif op == 19 then
            if not (d == 62 or d == 63) then
                np = np + 1
                pst_p[np], pst_v[np] = d, M[a] or 0.0
            end
        elseif op == 20 then pc = a
        elseif op == 21 then
            if nz(M[b] or 0) > 0 then pc = a end
        elseif op == 22 then break
        elseif op == 23 then M[d] = (string.unpack("<I4", string.pack("<f", M[a] or 0.0))) + 0.0
        elseif op == 24 then M[d] = (string.unpack("<f", string.pack("<I4", u32(M[a] or 0))))
        elseif op == 25 then M[d] = (u32(M[a] or 0) & u32(M[b] or 0)) + 0.0
        elseif op == 26 then M[d] = (u32(M[a] or 0) | u32(M[b] or 0)) + 0.0
        elseif op == 27 then M[d] = (u32(M[a] or 0) ~ u32(M[b] or 0)) + 0.0
        elseif op == 28 then M[d] = ((u32(M[a] or 0) << (u32(M[b] or 0) % 32)) & 0xFFFFFFFF) + 0.0
        elseif op == 29 then M[d] = (u32(M[a] or 0) >> (u32(M[b] or 0) % 32)) + 0.0
        end
    end
    return true
end

function gp_tick(inn, inb)
    for _, batch in ipairs(pending) do apply_batch(batch) end
    pending = {}
    local gate = inb[32] and true or false
    if ncode > 0 then
        pst_p, pst_v = {}, {}
        if run(inn, inb) then
            for i = 1, #pst_p do
                local p = pst_p[i]
                if p < 32 then hold_n[p + 1] = pst_v[i] else hold_b[p - 31] = nz(pst_v[i]) > 0 end
            end
            hb = not hb
        else
            aborts = aborts + 1
        end
    end
    local on, ob = {}, {}
    for i = 1, 32 do
        if gate then
            local v = hold_n[i]
            local lo, hi = glo[i - 1], ghi[i - 1]
            if lo then v = nz(v); v = v < lo and lo or (v > hi and hi or v) end
            on[i], ob[i] = v, hold_b[i]
        else
            on[i], ob[i] = 0.0, false
        end
    end
    ob[31], ob[32] = hb, cut
    return on, ob
end

gp_init()
