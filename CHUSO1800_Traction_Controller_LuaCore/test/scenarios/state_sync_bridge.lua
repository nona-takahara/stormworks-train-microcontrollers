-- Verifies deploy/main.lua (the storm-lua-minify build input: a flat
-- script that dofile()s ../../lib/state_sync.lua and ../src/chuso1800_core.lua
-- in place, since Stormworks has no require/dofile of its own -- minify
-- expands those dofile() calls textually at build time). Two things need
-- checking:
--
-- 1. The global `calculateTick(stateless_in, state_in)` it defines -- the
--    function lib/state_sync.lua actually calls -- must decode/encode
--    state slots 1-2 (already-uint32 STATE_LATCHES_LAYOUT/STATE_TIMERS_LAYOUT
--    bitfields) untouched, and slots 3-7 (raw-double physics/BC quasi-state)
--    through the same float32-bit-pattern round trip lib/state_sync.lua uses
--    for its own state feedback, so its "state入出力はinteger前提" contract
--    holds for every slot, not just the pre-packed ones.
-- 2. lib/state_sync.lua's onTick() driver itself must run for many ticks
--    without erroring (regression guard for the `caluculateTick` typo fixed
--    in this same change) and settle to self-consistent output once its
--    simulated feedback loop closes.
--
-- deploy/main.lua's dofile() calls are literal relative paths (required so
-- storm-lua-minify's static scan can find them) and therefore only resolve
-- when the working directory is deploy/ itself -- this scenario is run
-- from there, out-of-process, so the rest of the suite's own working
-- directory is unaffected either way.

local core = require("chuso1800_core")

-- Lua's default tostring()/table.concat number formatting (~14 significant
-- digits) silently rounds doubles -- not enough to survive a round trip
-- through a generated driver script's source text without corrupting the
-- comparison. "%.17g" is the minimum precision that always round-trips a
-- full IEEE 754 double exactly.
local function serialize_numbers(arr)
    local parts = {}
    for i, v in ipairs(arr) do
        parts[i] = string.format("%.17g", v)
    end
    return table.concat(parts, ", ")
end

local function locate_deploy_dir()
    local this_file = debug.getinfo(1, "S").source:sub(2)
    local this_dir = this_file:match("(.*/)") or "./"
    return this_dir .. "../../deploy"
end

-- Runs `driver_code` (a self-contained Lua chunk as a string) as a
-- subprocess with cwd=deploy/, and returns its stdout. The driver is
-- expected to `dofile("main.lua")` itself and print `OK` as the last line
-- on success, or raise an error (surfaced as non-"OK" output) on failure.
local function run_in_deploy_dir(h, driver_code)
    local deploy_dir = locate_deploy_dir()
    local driver_path = os.tmpname()
    local f = assert(io.open(driver_path, "w"))
    f:write(driver_code)
    f:close()

    local proc = assert(io.popen(
        string.format("cd '%s' && lua '%s' 2>&1", deploy_dir, driver_path)))
    local output = proc:read("*a")
    proc:close()
    os.remove(driver_path)

    h.assert_true(output:match("OK%s*$") ~= nil,
        "deploy/main.lua subprocess succeeded, output:\n" .. output)
    return output
end

return function(h)
    -- --- Part 1: bridge round-trip / decode-encode correctness ---
    --
    -- Test values for state_in slots 3-7 are chosen as exact multiples of
    -- small powers of 2 so they are already float32-exact: the bridge's
    -- i2f(f2i(x)) round trip should then be a lossless no-op, letting this
    -- assert an exact match against calling core.calculateTick directly
    -- (rather than a float32-tolerance match, which a later part of this
    -- same scenario covers for non-exact values via state_out).
    local raw_state = core.encode_state({
        position_counter = 8, phase1_latch = true, phase2_latch = false,
        regen_latch = false, traction_advance_counter = 3,
        field_current_excess_counter = 5, regen_delay_level = 240,
        phase1_cap_counter = 4, phase2_cap_counter = 0,
        current_below_limit_cap_counter = 2,
        OLD_I = 137.25, OLD_IF_A = 162.5, OLD_PHI = 0.028125,
        regen_bc_smooth = -0.0625, bc_target_smooth = -0.015625,
    })
    local stateless_in = core.encode_stateless_in({
        speed = 8, catenary_voltage_sw = 1500, brake_pressure_sw = 5,
        sap_pressure_sw = 3, direction = 1, notch_pos = 4,
    })
    local expected_out, expected_state_out = core.calculateTick(stateless_in, raw_state)

    local part1 = string.format([[
dofile("main.lua")

local raw_state = { %s }
local stateless_in = { %s }
local expected_out = { %s }
local expected_state_out = { %s }

local bridge_state_in = {
    raw_state[1], raw_state[2],
    f2i(raw_state[3]), f2i(raw_state[4]), f2i(raw_state[5]),
    f2i(raw_state[6]), f2i(raw_state[7]),
    raw_state[8],
}
local bridge_out, bridge_state_out = calculateTick(stateless_in, bridge_state_in)

for i = 1, 8 do
    assert(math.abs(bridge_out[i] - expected_out[i]) < 1e-9,
        "stateless_out[" .. i .. "] mismatch: " .. bridge_out[i] .. " vs " .. expected_out[i])
end
assert(bridge_state_out[1] == expected_state_out[1], "state_out[1] not passed through unconverted")
assert(bridge_state_out[2] == expected_state_out[2], "state_out[2] not passed through unconverted")
for i = 3, 7 do
    local decoded = i2f(bridge_state_out[i])
    local eps = math.max(math.abs(expected_state_out[i]) * 2e-7, 1e-9)
    assert(math.abs(decoded - expected_state_out[i]) < eps,
        "state_out[" .. i .. "] round trip mismatch: " .. decoded .. " vs " .. expected_state_out[i])
end
assert(bridge_state_out[8] == expected_state_out[8], "state_out[8] not passed through unconverted")

print("OK")
]],
        serialize_numbers(raw_state),
        serialize_numbers(stateless_in),
        serialize_numbers(expected_out),
        serialize_numbers(expected_state_out))

    run_in_deploy_dir(h, part1)

    -- --- Part 2: onTick() driver runs for many ticks without erroring ---
    -- (regression guard for the caluculateTick typo, which broke every
    -- single tick unconditionally). Feedback is looped back through a
    -- simple 1-tick delay to exercise the sync/resync path repeatedly.
    local part2 = string.format([[
dofile("main.lua")

local stateless_in = { %s }
local in_vals, out_vals = {}, {}
input = { getNumber = function(ch) return in_vals[ch] or 0 end }
output = { setNumber = function(ch, v) out_vals[ch] = v end }

for i = 1, 8 do in_vals[i] = stateless_in[i] end
for i = 1, 24 do in_vals[8 + i] = 0 end

for tick = 1, 30 do
    onTick()
    local v = out_vals[17]
    assert(type(v) == "number" and v == v, "onTick tick " .. tick .. " produced a non-NaN output N17")
    for i = 1, 8 do
        in_vals[i] = stateless_in[i]
        in_vals[8 + i] = stateless_in[i]
        in_vals[16 + i] = out_vals[16 + i]
        in_vals[24 + i] = out_vals[24 + i]
    end
end

print("OK")
]],
        serialize_numbers(stateless_in))

    run_in_deploy_dir(h, part2)
end
