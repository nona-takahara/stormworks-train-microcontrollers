-- Verifies deploy/chuso1800_deploy.lua (the auto-generated, Stormworks-
-- pasteable concatenation of ../../lib/state_sync.lua + src/chuso1800_core.lua
-- + deploy/bridge.lua). Two things need checking:
--
-- 1. The bridge's global `calculateTick(stateless_in, state_in)` -- the
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

local core = require("chuso1800_core")

local function locate_deploy()
    local this_file = debug.getinfo(1, "S").source:sub(2)
    local this_dir = this_file:match("(.*/)") or "./"
    return this_dir .. "../../deploy/chuso1800_deploy.lua"
end

return function(h)
    local deploy_path = locate_deploy()
    local chunk = assert(loadfile(deploy_path), "could not load " .. deploy_path)
    chunk()

    h.assert_true(type(calculateTick) == "function", "deploy script defines global calculateTick")
    h.assert_true(type(onTick) == "function", "deploy script defines global onTick")
    h.assert_true(type(i2f) == "function" and type(f2i) == "function", "deploy script exposes i2f/f2i")

    -- --- Part 1: bridge round-trip / decode-encode correctness ---

    local raw_state = core.encode_state({
        position_counter = 8, phase1_latch = true, phase2_latch = false,
        regen_latch = false, traction_advance_counter = 3,
        field_current_excess_counter = 5, regen_delay_level = 240,
        phase1_cap_counter = 4, phase2_cap_counter = 0,
        current_below_limit_cap_counter = 2,
        OLD_I = 137.25, OLD_IF_A = 162.5, OLD_PHI = 0.028125,
        regen_bc_smooth = -0.0625, bc_target_smooth = -0.015625,
    })

    -- Slots 1-2 are already exact uint32 bitfields: bridge must pass them
    -- through with zero conversion.
    local bridge_state_in = {
        raw_state[1], raw_state[2],
        f2i(raw_state[3]), f2i(raw_state[4]), f2i(raw_state[5]),
        f2i(raw_state[6]), f2i(raw_state[7]),
        raw_state[8],
    }

    local stateless_in = core.encode_stateless_in({
        speed = 8, catenary_voltage_sw = 1500, brake_pressure_sw = 5,
        sap_pressure_sw = 3, direction = 1, notch_pos = 4,
    })

    local bridge_out, bridge_state_out = calculateTick(stateless_in, bridge_state_in)

    -- Reference: call core.calculateTick directly with the SAME state,
    -- pre-rounded to float32 exactly the way the bridge's i2f(f2i(x)) would
    -- (chosen values above -- multiples of small powers of 2 -- are already
    -- float32-exact, so this round trip should be a no-op; asserting that
    -- confirms the bridge introduces no rounding beyond what state_sync.lua
    -- itself would apply for genuinely float32-exact state).
    local reference_state_in = {
        raw_state[1], raw_state[2],
        i2f(f2i(raw_state[3])), i2f(f2i(raw_state[4])), i2f(f2i(raw_state[5])),
        i2f(f2i(raw_state[6])), i2f(f2i(raw_state[7])),
        raw_state[8],
    }
    for i = 3, 7 do
        h.assert_near(reference_state_in[i], raw_state[i], 1e-9,
            "float32-exact test values round-trip losslessly, slot " .. i)
    end

    local expected_out, expected_state_out = core.calculateTick(stateless_in, reference_state_in)

    for i = 1, 8 do
        h.assert_near(bridge_out[i], expected_out[i], 1e-9, "stateless_out[" .. i .. "] matches direct core call")
    end

    -- state_out: slots 1-2 pass through as exact integers (no encoding at
    -- all); slots 3-7 must come back through the bridge already f2i-encoded
    -- (an "integer" in state_sync.lua's domain), decoding back via i2f to
    -- the expected double.
    h.assert_eq(bridge_state_out[1], expected_state_out[1], "state_out[1] (STATE_LATCHES_LAYOUT) passes through unconverted")
    h.assert_eq(bridge_state_out[2], expected_state_out[2], "state_out[2] (STATE_TIMERS_LAYOUT) passes through unconverted")
    for i = 3, 7 do
        -- float32 has ~7 significant decimal digits; physics magnitudes run
        -- up to a few hundred, so an absolute epsilon needs to scale with
        -- the value rather than being a tiny fixed constant.
        local eps = math.max(math.abs(expected_state_out[i]) * 2e-7, 1e-9)
        h.assert_near(i2f(bridge_state_out[i]), expected_state_out[i], eps,
            "state_out[" .. i .. "] round-trips through f2i encoding, decoded back matches")
    end
    h.assert_eq(bridge_state_out[8], expected_state_out[8], "state_out[8] (spare) passes through unconverted")

    -- --- Part 2: onTick() driver runs for many ticks without erroring ---
    -- (regression guard for the caluculateTick typo, which broke every
    -- single tick unconditionally). Feedback is looped back through a
    -- simple 1-tick delay to exercise the sync/resync path repeatedly.

    local in_vals, out_vals = {}, {}
    input = { getNumber = function(ch) return in_vals[ch] or 0 end }
    output = { setNumber = function(ch, v) out_vals[ch] = v end }

    for i = 1, 8 do in_vals[i] = stateless_in[i] end
    for i = 1, 24 do in_vals[8 + i] = 0 end

    for tick = 1, 30 do
        onTick()
        h.assert_true(type(out_vals[17]) == "number" and out_vals[17] == out_vals[17],
            "onTick tick " .. tick .. " produces a non-NaN output N17")
        -- Loop this tick's fresh output/state (N17-32) back as next tick's
        -- delayed-feedback inputs (N17-32), and re-present the same
        -- stateless sensor reading at N1-16 (both "current" and "1-tick
        -- delayed" copies, per the header comment's wiring convention).
        for i = 1, 8 do
            in_vals[i] = stateless_in[i]
            in_vals[8 + i] = stateless_in[i]
            in_vals[16 + i] = out_vals[16 + i]
            in_vals[24 + i] = out_vals[24 + i]
        end
    end
end
