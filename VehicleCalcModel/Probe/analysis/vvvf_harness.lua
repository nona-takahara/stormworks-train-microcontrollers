-- Runs two instances of the 2000-series traction controller (CHUSO/CHUSO2000_Traction_Controller/scripts/n485.lua) as a 1M1T unit,
-- connected by Momelink, one tick per input line. Usage: lua vvvf_harness.lua <path to n485.lua>
-- stdin : "v pN bN dir eb disable_rb"      v [m/s], pN power notch, bN brake notch 0-31, dir +1/-1, eb/disable_rb 0 or 1
-- stdout: "M_N2 M_N1 T_N1 M_B16 M_N25 M_N24"   motor acceleration of the M car, friction brake deceleration of the M car and of the T car
local path = arg[1]
local code = assert(io.open(path)):read("a")

local function instance(is_M)
    local env = setmetatable({}, { __index = _G })
    local inN, inB, outN, outB = {}, {}, {}, {}
    env.input = { getNumber = function(c) return inN[c] or 0 end, getBool = function(c) return inB[c] or false end }
    env.output = { setNumber = function(c, v) outN[c] = v end, setBool = function(c, v) outB[c] = v end }
    assert(load(code, "n485", "t", env))()
    return { tick = env.onTick, inN = inN, inB = inB, outN = outN, outB = outB, is_M = is_M }
end

local M, T = instance(true), instance(false)
for line in io.lines() do
    local v, pN, bN, dir, eb, drb = line:match("^(%S+) (%S+) (%S+) (%S+) (%S+) (%S+)")
    v, pN, bN, dir = tonumber(v), tonumber(pN), tonumber(bN), tonumber(dir)
    for _, c in ipairs({ M, T }) do
        c.inN[1], c.inN[2], c.inN[3], c.inN[4], c.inN[5], c.inN[6], c.inN[7] = v, 1500, pN, bN, dir, 0, 1.32
        c.inB[1], c.inB[2], c.inB[3], c.inB[4] = eb == "1", false, drb == "1", c.is_M
    end
    -- Momelink between the cars (the values of the previous tick)
    T.inN[8], T.inN[9] = 1, 3.5                      -- one T car; the largest friction brake share
    M.inN[30], M.inN[31] = T.outN[30] or 0, T.outN[31] or 0
    T.inN[15], T.inN[23], T.inN[24], T.inN[25], T.inN[29] = M.outN[15] or 0, M.outN[23] or 0, M.outN[24] or 0, M.outN[25] or 0, M.outN[29] or 0
    T.inB[16], T.inB[20] = M.outB[16] or false, M.outB[20] or false
    M.tick(); T.tick()
    io.write(string.format("%.6f %.6f %.6f %d %.6f %.6f\n", M.outN[2] or 0, M.outN[1] or 0, T.outN[1] or 0, (M.outB[16] and 1 or 0), M.outN[25] or 0, M.outN[24] or 0))
    io.flush()
end
