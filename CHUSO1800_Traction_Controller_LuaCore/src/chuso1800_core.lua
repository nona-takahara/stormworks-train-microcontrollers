-- CHUSO1800 traction controller: consolidated state machine + physics.
--
-- Pure-function contract: calculateTick(stateless_in, state_in) -> stateless_out, state_out.
-- stateless_in/out and state_in/out are arrays [1..8] of Lua numbers. state_out
-- from tick N is fed back verbatim as state_in on tick N+1. No persistent Lua
-- globals are used for control state (physics/BC quasi-state and packed
-- latch/timer bitfields live entirely in state_in/state_out).
--
-- See ../SIGNAL_MAP.md for the full signal-to-slot/bit mapping and provenance
-- of every formula below (cross-referenced to CHUSO1800_Traction_Controller/SPEC.md).
--
-- Modeling rule (see README.md "Tick model"): every node that has a feedback
-- path (SR latches, debounce timers, periodic pulses, the physics
-- quasi-state, BC smoothing) reads its OLD value (state_in) when computing
-- this tick's decisions, and writes a NEW value to state_out for next tick.
-- Purely combinational logic (derived only from fresh external inputs, or
-- from other freshly-computed combinational values) is evaluated fully
-- within the same tick -- unlike the literal gate-net model (SPEC.md §0.2,
-- "every gate output is 1-tick delayed"), this module lets combinational
-- chains settle instantly, which SPEC.md's own closing note anticipates and
-- accepts ("transient corner-case tick-counts may shrink, steady-state
-- conclusions are unchanged"). This collapsing is required to fit the whole
-- control surface in 8 state slots.
--
-- Below is organized into small functions, each roughly matching one
-- SPEC.md §3.x section, threaded together by calculateTick at the bottom --
-- rather than one large flat transliteration of every main.sw-net gate name
-- into a same-named local variable. Two mechanisms are deliberately
-- SIMPLER than a literal gate-for-gate port, at the cost of shifting exact
-- tick counts in corner cases (never steady-state behavior):
--   * periodic_pulse_step replaces the BLINKER+PULSE(rise) gate pair with a
--     single elapsed-tick counter, since nothing here ever reads a raw
--     on/off duty-cycle output -- only the periodic pulse it drives matters.
--   * regen_delay_step counts in whole ticks (a packed integer, not a
--     seconds-based float): 0.5s charge / 10s discharge is a 20x ratio, so
--     the level is scaled so charging adds 20/tick and discharging removes
--     1/tick, both exact integers -- avoiding the float-accumulation drift
--     a seconds-based accumulator would have (30 additions of 1/60 land at
--     0.49999999999999994, not exactly 0.5, which would need an epsilon
--     guard on every "charged" check; integers need none).
--
-- Physics (Newton-solve) is ported verbatim from
-- CHUSO1800_Traction_Controller/scripts/n409.lua -- that file is NOT modified;
-- test/scenarios/physics_regression_vs_n409.lua checks numeric parity.
--
-- This file makes no `require`/`dofile` calls of its own: it is `require`d
-- by deploy/main.lua (see DESIGN_LOG.md #12/#13) for actual Stormworks
-- deployment, and `require`d directly by the plain-`lua` test suite. The
-- bit-field helpers below (to_u32/get_bits/put_bits) are a plain
-- string.pack("I4",...)/string.unpack("I4",...) implementation inlined
-- here so this file has no dependency on anything else to be tested
-- standalone.

local M = {}

--------------------------------------------------------------------------
-- Constants (copied from n409.lua verbatim).
--------------------------------------------------------------------------

local K = 12.16
local Kmu = 0.00029
local MOT_RES = 0.07
local Ks = 0.85
local PHIs = 150

local MOT_CTRL = 4

local GEAR_RATIO = 5.31
local WHEEL_R = 0.86 / 2
local WEIGHT = 35 * 1000

local SR = { 7.428,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334,     0,2.568,1.734,1.218,0.7570,0.4110,0.1334}
local PR = {     0,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334, 3.714,2.568,1.734,1.218,0.7570,0.4110,0.1334}

-- Newton-solve iteration seed. NOTE: this is NOT OLD_I and NOT the field
-- current control law's `target_i` -- in n409.lua both channel reads (the
-- outer `target_i = input.getNumber(6)` and calc_current_phi's own internal
-- `input.getNumber(6)`) read the SAME hardcoded CONST(200) composite channel
-- independently; `target_i` gets locally reassigned for the field-current
-- law but that reassignment never reaches the Newton solve. Preserved here
-- as two independent uses of the same constant.
local NEWTON_SEED = 200

--------------------------------------------------------------------------
-- Stormworks `property` values, read once at script load ("spawn time" --
-- properties don't change mid-flight, so there is no need to re-read them
-- every tick). This is the mechanism that keeps the two numeric limits
-- genuinely tunable per-vehicle in Stormworks' property panel -- matching
-- the original main.sw-net PROPERTY_NUMBER node names exactly -- instead of
-- baking them into source. property.get*() sits entirely outside the 8+8
-- composite-channel budget, so this costs no input slots.
--
-- Outside Stormworks (this repo's plain-`lua` test suite), the `property`
-- global does not exist; fall back to the same defaults the original
-- main.sw-net PROPERTY_NUMBER nodes ship with (their value=... attribute).
--------------------------------------------------------------------------

local property = property
if type(property) ~= "table" then
    local DEFAULT_NUMBER_PROPERTIES = {
        ["Over Speed Th. [m/s]"] = 32,       -- main.sw-net's overspeed_threshold
        ["Power Limit Current [A]"] = 210,   -- main.sw-net's power_limit_current
    }
    property = {
        getNumber = function(name) return DEFAULT_NUMBER_PROPERTIES[name] end,
    }
end

local OVERSPEED_THRESHOLD = property.getNumber("Over Speed Th. [m/s]")     -- m/s
local POWER_LIMIT_CURRENT = property.getNumber("Power Limit Current [A]") -- A

-- Plain CONST nodes in main.sw-net (not PROPERTY_* -- never exposed as
-- in-game-tunable in the original design either), so these stay source
-- constants.
local BRAKE_MIN_PRESSURE = 4         -- atm
local BRAKE_LIMIT_300 = 300
local BRAKE_LIMIT_400 = 400
local REGEN_BC_MIN = -0.1
local BC_TARGET_MIN = -0.05

-- Tick-rate-derived timer constants (Stormworks assumed 60 ticks/sec, SPEC §0.2).
local CAP_DEBOUNCE_TICKS = 6              -- 0.1s debounce, instant reset when disabled
local CAM_ADVANCE_PERIOD_TICKS = 12       -- 0.1s+0.1s traction_blinker period
local FIELD_CURRENT_EXCESS_PERIOD_TICKS = 30     -- 0.1s+0.4s field_current_excess_blinker period

-- regen_delay was CAPACITOR(charge_time=0.5s, discharge_time=10s) --
-- 0.5s = 30 ticks, 10s = 600 ticks. `level` is scaled so that "full" equals
-- the LARGER of the two tick counts (600): discharging then decrements
-- exactly 1/tick (600 ticks to drain, matching 10s by construction), and
-- charging must fill the same 0..600 range in only 30 ticks, so it adds
-- 600/30 = 20/tick. Pure integer arithmetic -- both steps land exactly on
-- whole numbers, so "charged" is a plain `>= 600` with no epsilon needed.
local REGEN_DELAY_DISCHARGE_TICKS = 600   -- 10s
local REGEN_DELAY_CHARGE_TICKS = 30       -- 0.5s
local REGEN_DELAY_FULL = REGEN_DELAY_DISCHARGE_TICKS
local REGEN_DELAY_CHARGE_STEP = REGEN_DELAY_FULL // REGEN_DELAY_CHARGE_TICKS -- 20
local REGEN_DELAY_DISCHARGE_STEP = 1

--------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------

local function clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

-- Bit-field helpers for the packed state/status slots (bit layout is
-- documented in SIGNAL_MAP.md, not restated as a Lua table here -- see
-- DESIGN_LOG.md #13 for why). `to_u32` enforces the 32-bit boundary by
-- round-tripping through string.pack("I4",...)/string.unpack("I4",...), so
-- overflow wraps like a real 32-bit unsigned value; `get_bits`/`put_bits`
-- then extract/build individual fields by plain shift+mask, addressed by
-- bit position instead of by name. (state_sync.lua's own f2i/i2f use the
-- same string.pack/string.unpack round-trip technique for a different
-- purpose -- float32 bit-reinterpretation, not integer field packing --
-- so they aren't reusable here directly, but this file must stay
-- self-contained regardless: it's `require`d standalone by the test suite
-- with no state_sync.lua in scope.)
local function to_u32(value)
    return string.unpack("I4", string.pack("I4", math.floor(value or 0) & 0xFFFFFFFF))
end

local function get_bits(acc, shift, width)
    return (acc >> shift) & ((1 << width) - 1)
end

-- Single-bit field, returned as a boolean directly (most fields in
-- state_in[1]/[2] and stateless_out[5] are 1-bit latches/flags) -- shorter
-- at each call site than get_bits(acc, shift, 1) ~= 0.
local function get_bit(acc, shift)
    return (acc >> shift) & 1 ~= 0
end

local function put_bits(value, shift, width)
    return (math.floor(value or 0) & ((1 << width) - 1)) << shift
end

-- Counterpart to get_bit: packs a boolean directly, shorter at each call
-- site than put_bits(b and 1 or 0, shift, 1).
local function put_bit(b, shift)
    return (b and 1 or 0) << shift
end

-- Reset-priority SR latch (SPEC.md §0.1).
local function sr_latch(old_q, set, reset)
    if reset then return false end
    if set then return true end
    return old_q
end

-- Debounce (was CAPACITOR(charge_time=0.1s, discharge_time=0) in
-- main.sw-net): a plain "N consecutive enabled ticks" counter. Enabling
-- resets instantly, matching discharge_time=0.
local function debounce_step(old_counter, enable)
    if enable then
        return math.min(old_counter + 1, CAP_DEBOUNCE_TICKS)
    end
    return 0
end

local function debounce_charged(old_counter)
    return old_counter >= CAP_DEBOUNCE_TICKS
end

-- Periodic pulse (was BLINKER(on_ticks, off_ticks) + PULSE(rise) in
-- main.sw-net): fires once every `period_ticks` of continuous `enable`,
-- then restarts the count; disabling resets the count to 0. Nothing in this
-- module reads a raw on/off duty-cycle output, only the periodic pulse it
-- would drive (cam advance, regen-warning pulse) -- so a single elapsed-tick
-- counter stands in for the BLINKER+PULSE gate pair, with no separate
-- "previous phase" bit needed. Timing differs slightly from a literal port
-- (first pulse arrives at period_ticks after enabling, not at off_ticks);
-- see README.md "tick model".
local function periodic_pulse_step(old_counter, enable, period_ticks)
    if not enable then
        return 0, false
    end
    local counter = old_counter + 1
    if counter >= period_ticks then
        return 0, true
    end
    return counter, false
end

-- regen_delay (was CAPACITOR(charge_time=0.5s, discharge_time=10s)): see the
-- REGEN_DELAY_* constants above for the scaling derivation. `level` is a
-- packed integer field (STATE_TIMERS_LAYOUT), not a raw double.
local function regen_delay_step(old_level, enable)
    if enable then
        return math.min(old_level + REGEN_DELAY_CHARGE_STEP, REGEN_DELAY_FULL)
    end
    return math.max(old_level - REGEN_DELAY_DISCHARGE_STEP, 0)
end

local function regen_delay_charged(old_level)
    return old_level >= REGEN_DELAY_FULL
end

--------------------------------------------------------------------------
-- Physics (ported from n409.lua)
--------------------------------------------------------------------------

local function calc_phi(iF)
    return iF * Kmu * Ks * PHIs / (Ks * math.abs(iF) + PHIs)
end

local function deriv_phi(iF)
    return Kmu * Ks * PHIs * PHIs / ((Ks * math.abs(iF) + PHIs) * (Ks * math.abs(iF) + PHIs))
end

local function calc_iF(pF, ia, iF_a)
    return ia * pF + iF_a
end

local function deriv_iF(pF)
    return pF
end

local function calc_ia(ia, Vt, n, RpN, pF, iF_a)
    return K * calc_phi(calc_iF(pF, ia, iF_a)) * n - Vt + (MOT_RES + RpN) * ia
end

local function deriv_ia(ia, Vt, n, RpN, pF, iF_a)
    return K * deriv_phi(calc_iF(pF, ia, iF_a)) * deriv_iF(pF) * n + MOT_RES + RpN
end

local function calc_current_phi(Vt, n, RpN, pF, iF_a, seed)
    local i = seed
    for _ = 1, 5 do
        local ndf = deriv_ia(i, Vt, n, RpN, pF, iF_a)
        if math.abs(ndf) >= 0.000001 then
            i = i - calc_ia(i, Vt, n, RpN, pF, iF_a) / ndf
        else
            if ndf > 0 then
                i = i - calc_ia(i, Vt, n, RpN, pF, iF_a)
            elseif ndf < 0 then
                i = i + calc_ia(i, Vt, n, RpN, pF, iF_a)
            end
        end
    end
    return i, calc_phi(calc_iF(pF, i, iF_a))
end

-- physics_tick: byte-for-byte port of n409.lua's onTick body. Positional
-- params mirror the original sim_input composite channels /
-- traction_status_bool, in this order: speed, vl (=catenary_voltage_sw),
-- position_counter (OLD cam), direction, notch_eff, phase1, phase2, regen
-- (OLD latches), notch_ge1, low_bc_with_regen_flag (fresh bools),
-- regen_bc_smooth_seed (OLD, ch7), regen_bc_target (fresh, ch8), OLD_I,
-- OLD_IF_A, OLD_PHI (OLD physics quasi-state). Returns: motor_current,
-- back_emf, accel, W, iF_a, bcT, OLD_I, OLD_IF_A, OLD_PHI (new quasi-state).
function M.physics_tick(speed, vl, position_counter, direction, notch_eff, phase1, phase2, regen,
    notch_ge1, low_bc_with_regen_flag, regen_bc_smooth_seed, regen_bc_target, OLD_I, OLD_IF_A, OLD_PHI)
    local rpm = speed * 9.55 * GEAR_RATIO / WHEEL_R
    local notch = position_counter + 1 -- n409.lua's "notch" var is actually cam-position+1
    local res = 100000
    local srsmtr = 4
    local iF_a = 150
    local target_i = NEWTON_SEED

    if (not phase1) and (not phase2) then vl = 0 end
    if phase1 then srsmtr = 8 end
    if phase2 and notch == 1 then srsmtr = 4 end

    if regen then
        if low_bc_with_regen_flag then
            local oldtrq = direction * (MOT_CTRL * 9.55 * K * OLD_PHI * OLD_I * GEAR_RATIO * 0.99 / WHEEL_R / WEIGHT)
            iF_a = OLD_IF_A + (oldtrq - regen_bc_smooth_seed) * 20
            iF_a = iF_a * math.min(1, (470 / (K * math.abs(rpm))) / calc_phi(iF_a + OLD_I * 0.15))
        else
            if notch_ge1 and notch_eff <= 3 then target_i = OLD_IF_A end
            if not notch_ge1 then target_i = 0 end
            if target_i == 0 then target_i = math.max(math.min(0, OLD_I + 20), OLD_I - 20) end
            iF_a = OLD_IF_A + (OLD_I - target_i) * 0.1
        end
    else
        target_i = OLD_IF_A
        if notch_eff == 0 then target_i = 0 end
        iF_a = OLD_IF_A + (OLD_I - target_i) * 0.1
        if notch_eff ~= 0 and iF_a > 180 then iF_a = 180 end
    end

    if srsmtr == 8 then res = SR[notch] end
    if srsmtr == 4 then res = PR[notch] end

    if iF_a < 20 then iF_a = 20 elseif iF_a > 500 then iF_a = 500 end

    local i, phi = calc_current_phi(vl / srsmtr, rpm, res / srsmtr, direction * 0.2, iF_a * direction, NEWTON_SEED)
    if vl == 0 then i = 0; phi = 0 end

    local trqN = 9.55 * K * phi * i
    local bcT = math.min(direction * MOT_CTRL * trqN * GEAR_RATIO / WHEEL_R / WEIGHT, 0) - regen_bc_target
    if bcT < 0.01 and i < 0 then bcT = 0 end

    return i, K * phi * rpm, MOT_CTRL * trqN * GEAR_RATIO * 0.99 / WHEEL_R / WEIGHT, vl * i * (MOT_CTRL / srsmtr) * 2,
        iF_a, bcT, i, iF_a, phi
end

--------------------------------------------------------------------------
-- State (de)serialization helpers (used by calculateTick itself, and
-- directly by the test suite via test/harness.lua's named-table wrappers
-- -- these take/return plain positional values, not tables, for the same
-- minified-size reason as the tick sub-steps above; DESIGN_LOG.md #13).
--------------------------------------------------------------------------

function M.zero_state()
    return { 0, 0, 0, 0, 0, 0, 0, 0 }
end

-- Bit positions below (state_in[1]/[2], stateless_out[5]) must match
-- SIGNAL_MAP.md exactly.

-- Returns: position_counter, phase1_latch, phase2_latch, regen_latch,
-- traction_advance_counter, field_current_excess_counter,
-- regen_delay_level, phase1_cap_counter, phase2_cap_counter,
-- current_below_limit_cap_counter, OLD_I, OLD_IF_A, OLD_PHI,
-- regen_bc_smooth, bc_target_smooth.
function M.decode_state(state_in)
    local latches = to_u32(state_in[1])
    local timers = to_u32(state_in[2])
    return get_bits(latches, 0, 5), get_bit(latches, 5), get_bit(latches, 6), get_bit(latches, 7),
        get_bits(latches, 8, 4), get_bits(latches, 12, 5),
        get_bits(timers, 0, 10), get_bits(timers, 10, 3), get_bits(timers, 13, 3), get_bits(timers, 16, 3),
        state_in[3], state_in[4], state_in[5], state_in[6], state_in[7]
end

-- Params in the same order as M.decode_state's returns.
function M.encode_state(position_counter, phase1_latch, phase2_latch, regen_latch,
    traction_advance_counter, field_current_excess_counter,
    regen_delay_level, phase1_cap_counter, phase2_cap_counter, current_below_limit_cap_counter,
    OLD_I, OLD_IF_A, OLD_PHI, regen_bc_smooth, bc_target_smooth)
    local slot1 = put_bits(position_counter, 0, 5)
        | put_bit(phase1_latch, 5)
        | put_bit(phase2_latch, 6)
        | put_bit(regen_latch, 7)
        | put_bits(traction_advance_counter, 8, 4)
        | put_bits(field_current_excess_counter, 12, 5)
    local slot2 = put_bits(regen_delay_level, 0, 10)
        | put_bits(phase1_cap_counter, 10, 3)
        | put_bits(phase2_cap_counter, 13, 3)
        | put_bits(current_below_limit_cap_counter, 16, 3)
    return {
        slot1, slot2,
        OLD_I or 0, OLD_IF_A or 0, OLD_PHI or 0,
        regen_bc_smooth or 0, bc_target_smooth or 0,
        0, -- spare
    }
end

-- Params: speed, catenary_voltage_sw, brake_pressure_sw, sap_pressure_sw,
-- direction, notch_pos, controller_stop, regen_flag.
function M.encode_stateless_in(speed, catenary_voltage_sw, brake_pressure_sw, sap_pressure_sw,
    direction, notch_pos, controller_stop, regen_flag)
    return {
        speed or 0, catenary_voltage_sw or 0, brake_pressure_sw or 0, sap_pressure_sw or 0,
        direction or 0, notch_pos or 0,
        (controller_stop and 1) or 0,
        (regen_flag and 1) or 0,
    }
end

-- Returns: motor_current, W, bc_target_smooth, bcT, cam_pulse,
-- phase1_latch, phase2_latch, regen_latch, notch_ge1,
-- low_bc_with_regen_flag, field_current_excess_cond, power_cut.
function M.decode_stateless_out(stateless_out)
    local status = to_u32(stateless_out[5])
    return stateless_out[1], stateless_out[2], stateless_out[3], stateless_out[4],
        get_bit(status, 0), get_bit(status, 1), get_bit(status, 2), get_bit(status, 3),
        get_bit(status, 4), get_bit(status, 5), get_bit(status, 6), get_bit(status, 7)
end

--------------------------------------------------------------------------
-- Tick sub-steps, each roughly one SPEC.md §3.x section. Positional
-- parameters/multi-return instead of named tables (see DESIGN_LOG.md #13):
-- storm-lua-minify can't rename table keys the way it renames identifiers,
-- so named intermediate tables cost real bytes against Stormworks' 8192-
-- character LUA node limit. This trades readability at these call
-- boundaries for that. M.decode_state/M.encode_state/M.decode_stateless_out
-- keep their named-table shape unchanged -- they're the public contract
-- every test scenario calls directly by field name.
--------------------------------------------------------------------------

local function decode_inputs(stateless_in)
    -- Returns: speed, catenary_voltage_sw, brake_pressure_sw (pre-resolved
    -- by gates -- SAP passthrough or ECB-offset conversion already
    -- applied, so this module no longer needs to know SAP vs ECB),
    -- sap_pressure_sw (same), direction (pre-resolved -1/0/+1, gates
    -- already combined forward/backward), notch_pos, controller_stop,
    -- regen_flag.
    return stateless_in[1], stateless_in[2], stateless_in[3], stateless_in[4], stateless_in[5],
        clamp(math.floor(stateless_in[6] or 0), 0, 7),
        (stateless_in[7] or 0) ~= 0,
        (stateless_in[8] or 0) ~= 0
end

-- SPEC §3.5 (EB / power-cut condition). `power_cut` itself is provably
-- dead (see README "Simplifications") and folded out entirely.
local function eb_and_brake_pressure(speed, brake_pressure_sw, direction, controller_stop)
    local overspeed = math.abs(speed) > OVERSPEED_THRESHOLD
    local brake_below_min = brake_pressure_sw < BRAKE_MIN_PRESSURE
    return controller_stop or (direction == 0) or overspeed or brake_below_min
end

-- SPEC §3.3 (notch processing) + §3.2's cam-position echo ("notch_fb").
-- Returns: notch_eff, notch_ge1, notch_ge2, notch_ge3, notch_fb_ge1,
-- notch_fb_range_low, notch_fb_range_high, notch_fb_eq14, notch_fb_ne14.
local function notch_and_cam_feedback(notch_pos, position_counter, eb_condition)
    local notch_eff = notch_pos * (eb_condition and 0 or 1)
    -- Cam-position echo zeroed under EB, matching the original
    -- current_src_mux substitution (only ch7 survives EB).
    local notch_fb = eb_condition and 0 or position_counter
    return notch_eff,
        notch_eff >= 1 and notch_eff <= 7,
        notch_eff >= 2 and notch_eff <= 7,
        notch_eff >= 3 and notch_eff <= 7,
        notch_fb >= 0 and notch_fb <= 1,
        notch_fb >= 0 and notch_fb <= 13,
        notch_fb >= 14 and notch_fb <= 20,
        notch_fb == 14,
        notch_fb ~= 14
end

-- SPEC §3.8 (regen-BC target chain, fresh every tick). sap_pressure_sw
-- arrives pre-resolved from gates (see decode_inputs). Returns:
-- regen_bc_target, low_bc_with_regen_flag, regen_current.
local function brake_demand(sap_pressure_sw, regen_flag)
    local regen_bc_target = -math.floor((sap_pressure_sw - 1) * 2) / 7.2
    return regen_bc_target, regen_bc_target < BC_TARGET_MIN and regen_flag, math.max(-regen_bc_target, 0)
end

-- current_src_mux EB substitution: under EB only ch7 (bcT, here holding
-- regen_current) survives; everything else reads 0. Params/returns both in
-- physics_tick's own order: motor_current, W, accel, iF_a, bcT.
local function eb_substitute(motor_current, W, accel, iF_a, bcT, eb_condition, regen_current)
    if eb_condition then
        return 0, 0, 0, 0, regen_current
    end
    return motor_current, W, accel, iF_a, bcT
end

-- SPEC §3.6/§3.7 debounce timers (current-limit and phase1/phase2's own
-- "has been on for 0.1s" gates). "*_charged" reflects the OLD counter (this
-- tick's decision input); "*_next" is what gets stored for next tick.
-- Returns: current_below_limit_cap_charged, current_below_limit_cap_counter_next,
-- phase1_cap_charged, phase1_cap_counter_next, phase2_cap_charged,
-- phase2_cap_counter_next.
local function debounce_block(phase1_latch, phase2_latch, current_below_limit_cap_counter,
    phase1_cap_counter, phase2_cap_counter, motor_current)
    local current_limit_sw = phase2_latch and (POWER_LIMIT_CURRENT - 20) or POWER_LIMIT_CURRENT
    local current_below_limit = motor_current < current_limit_sw
    return debounce_charged(current_below_limit_cap_counter), debounce_step(current_below_limit_cap_counter, current_below_limit),
        debounce_charged(phase1_cap_counter), debounce_step(phase1_cap_counter, phase1_latch),
        debounce_charged(phase2_cap_counter), debounce_step(phase2_cap_counter, phase2_latch)
end

-- SPEC §3.6 field-current-excess detection chain (see SPEC.md §3.6 naming
-- note: this was mislabeled "regen_warning" in main.sw-net, but it isn't a
-- regen-brake warning at all -- iF_a here is the field current, read from
-- the same channel n409.lua calls "brake_current_fb"/channel=6. The
-- condition detects "notch went to 0 but iF_a is still above the 300/400A
-- threshold" and forces phase1/phase2 to fold early instead of waiting for
-- coasting_cond's natural current decay). Returns: brake_current_high_phase1,
-- field_current_excess_cond, field_current_excess_counter_next,
-- field_current_excess_pulse.
local function field_current_excess_block(phase1_latch, regen_bc_smooth, field_current_excess_counter,
    iF_a, notch_ge1, phase1_cap_charged)
    local phase1_low_bc = phase1_latch and regen_bc_smooth < REGEN_BC_MIN
    local brake_limit_sw = phase1_low_bc and BRAKE_LIMIT_400 or BRAKE_LIMIT_300
    local brake_current_above_300 = iF_a > BRAKE_LIMIT_300
    local field_current_excess_cond = (iF_a > brake_limit_sw) and (not notch_ge1)
    local counter_next, pulse = periodic_pulse_step(
        field_current_excess_counter, field_current_excess_cond, FIELD_CURRENT_EXCESS_PERIOD_TICKS)
    return brake_current_above_300 and phase1_cap_charged, field_current_excess_cond, counter_next, pulse
end

-- SPEC §3.6 core state machine: phase1/phase2/regen SR latches. Returns:
-- phase1_latch, phase2_latch, regen_latch, traction_any_active.
local function phase_state_machine(phase1_latch, phase2_latch, regen_latch,
    notch_ge1, notch_ge2, notch_ge3, notch_fb_ge1, notch_fb_range_low, notch_fb_range_high, notch_fb_eq14, notch_fb_ne14,
    motor_current, low_bc_with_regen_flag, field_current_excess_pulse, regen_flag,
    phase1_cap_charged, phase2_cap_charged, current_below_limit_cap_charged)
    local phase1_notch_active = phase1_latch and notch_ge1
    local phase1_regen_active = phase1_latch and notch_fb_ne14 and regen_latch
    local power_with_regen = notch_ge1 and notch_fb_ge1

    local current_near_zero = motor_current >= -50 and motor_current <= 50
    local neutral_cond = current_near_zero and not (notch_ge1 or low_bc_with_regen_flag)
    local coasting_cond = neutral_cond and (not regen_latch)
    local phase_reset_cond = coasting_cond or (field_current_excess_pulse and (not regen_flag))

    local phase1_set_cond = notch_ge2 and notch_fb_range_low
        and phase1_cap_charged and current_below_limit_cap_charged
    local phase1_set = (power_with_regen and (not phase2_latch))
        or (field_current_excess_pulse and phase2_latch)

    local phase2_blinker_cond = notch_ge3 and notch_fb_range_high
        and phase2_cap_charged and current_below_limit_cap_charged
    local phase2_set_cond = notch_ge3 and notch_fb_eq14 and current_below_limit_cap_charged
    local phase2_reset = phase_reset_cond or (phase1_latch and not (notch_ge3 and notch_fb_eq14))

    -- phase2_set_cond doubles as an extra phase1-reset trigger (Series ->
    -- Parallel transition resets phase1 the same tick phase2 sets).
    local phase1_reset = phase_reset_cond
        or (field_current_excess_pulse and phase1_cap_charged)
        or phase2_set_cond

    local traction_all_off = (not phase1_latch) and (not phase2_latch)
    local regen_off_all = (not notch_fb_ge1) and traction_all_off

    return sr_latch(phase1_latch, phase1_set, phase1_reset),
        sr_latch(phase2_latch, phase2_set_cond, phase2_reset),
        sr_latch(regen_latch, phase2_latch and notch_fb_ge1, phase1_notch_active or traction_all_off),
        phase1_set_cond or phase2_blinker_cond or regen_off_all or phase1_regen_active
end

-- SPEC §3.2 cam advance (periodic pulse while traction_any_active).
-- Returns: position_counter, cam_pulse, traction_advance_counter_next.
local function advance_cam(position_counter, traction_advance_counter, traction_any_active)
    local counter_next, pulse = periodic_pulse_step(
        traction_advance_counter, traction_any_active, CAM_ADVANCE_PERIOD_TICKS)
    local new_position = (position_counter + (pulse and 1 or 0)) % 21
    local delta = new_position - position_counter
    return new_position, not (delta >= 0 and delta <= 1), counter_next -- cam_pulse true only on the 20->0 ring wrap
end

-- SPEC §3.8 BC / regen-BC smoothing. Returns: bc_target_smooth,
-- regen_bc_smooth, regen_delay_level.
local function smooth_bc(bc_target_smooth, regen_bc_smooth, regen_delay_level,
    accel, regen_bc_target, regen_flag, brake_current_high_phase1)
    local regen_bc_enable = regen_delay_charged(regen_delay_level) or (not regen_flag)
    local regen_bc_sw = regen_bc_enable and 0 or regen_bc_target
    return accel * 0.2 + bc_target_smooth * 0.8,
        math.min(clamp(regen_bc_sw, regen_bc_smooth - 0.1, regen_bc_smooth + 0.02), 0),
        regen_delay_step(regen_delay_level, brake_current_high_phase1)
end

--------------------------------------------------------------------------
-- Main tick function
--------------------------------------------------------------------------

function M.calculateTick(stateless_in, state_in)
    local st_position_counter, st_phase1_latch, st_phase2_latch, st_regen_latch,
        st_traction_advance_counter, st_field_current_excess_counter,
        st_regen_delay_level, st_phase1_cap_counter, st_phase2_cap_counter, st_current_below_limit_cap_counter,
        st_OLD_I, st_OLD_IF_A, st_OLD_PHI, st_regen_bc_smooth, st_bc_target_smooth = M.decode_state(state_in)
    local speed, catenary_voltage_sw, brake_pressure_sw, sap_pressure_sw, direction,
        notch_pos, controller_stop, regen_flag = decode_inputs(stateless_in)

    local eb_condition = eb_and_brake_pressure(speed, brake_pressure_sw, direction, controller_stop)
    local notch_eff, notch_ge1, notch_ge2, notch_ge3, notch_fb_ge1,
        notch_fb_range_low, notch_fb_range_high, notch_fb_eq14, notch_fb_ne14 =
        notch_and_cam_feedback(notch_pos, st_position_counter, eb_condition)
    local regen_bc_target, low_bc_with_regen_flag, regen_current = brake_demand(sap_pressure_sw, regen_flag)

    -- Physics always uses OLD phase1/phase2/regen (breaks the physics <->
    -- state-machine cycle; see module header "Modeling rule"). physics_tick
    -- returns 9 values in this order: motor_current, back_emf (unused here
    -- -- only physics_regression_vs_n409.lua reads it, calling
    -- physics_tick directly), accel, W, iF_a, bcT, OLD_I, OLD_IF_A, OLD_PHI.
    local physics_motor_current, _back_emf, accel, physics_W, physics_iF_a, physics_bcT,
        phys_OLD_I, phys_OLD_IF_A, phys_OLD_PHI =
        M.physics_tick(speed, catenary_voltage_sw, st_position_counter, direction, notch_eff,
            st_phase1_latch, st_phase2_latch, st_regen_latch, notch_ge1, low_bc_with_regen_flag,
            st_regen_bc_smooth, regen_bc_target, st_OLD_I, st_OLD_IF_A, st_OLD_PHI)
    local motor_current, elec_W, elec_accel, iF_a, bcT = eb_substitute(
        physics_motor_current, physics_W, accel, physics_iF_a, physics_bcT, eb_condition, regen_current)

    local current_below_limit_cap_charged, current_below_limit_cap_counter_next,
        phase1_cap_charged, phase1_cap_counter_next, phase2_cap_charged, phase2_cap_counter_next =
        debounce_block(st_phase1_latch, st_phase2_latch, st_current_below_limit_cap_counter,
            st_phase1_cap_counter, st_phase2_cap_counter, motor_current)

    local brake_current_high_phase1, field_current_excess_cond,
        field_current_excess_counter_next, field_current_excess_pulse =
        field_current_excess_block(st_phase1_latch, st_regen_bc_smooth, st_field_current_excess_counter,
            iF_a, notch_ge1, phase1_cap_charged)

    local phase1_latch, phase2_latch, regen_latch, traction_any_active = phase_state_machine(
        st_phase1_latch, st_phase2_latch, st_regen_latch,
        notch_ge1, notch_ge2, notch_ge3, notch_fb_ge1, notch_fb_range_low, notch_fb_range_high, notch_fb_eq14, notch_fb_ne14,
        motor_current, low_bc_with_regen_flag, field_current_excess_pulse, regen_flag,
        phase1_cap_charged, phase2_cap_charged, current_below_limit_cap_charged)

    local position_counter, cam_pulse, traction_advance_counter_next =
        advance_cam(st_position_counter, st_traction_advance_counter, traction_any_active)
    local bc_target_smooth, regen_bc_smooth, regen_delay_level =
        smooth_bc(st_bc_target_smooth, st_regen_bc_smooth, st_regen_delay_level,
            elec_accel, regen_bc_target, regen_flag, brake_current_high_phase1)

    ----------------------------------------------------------------
    -- Assemble outputs
    ----------------------------------------------------------------

    local status_bits = put_bit(cam_pulse, 0)
        | put_bit(phase1_latch, 1)
        | put_bit(phase2_latch, 2)
        | put_bit(regen_latch, 3)
        | put_bit(notch_ge1, 4)
        | put_bit(low_bc_with_regen_flag, 5)
        | put_bit(field_current_excess_cond, 6)
        -- power_cut (bit 7) always 0, see README "Simplifications"

    local stateless_out = {
        motor_current,
        elec_W,
        bc_target_smooth,
        bcT,
        status_bits,
        0, 0, 0,
    }

    local state_out = M.encode_state(
        position_counter, phase1_latch, phase2_latch, regen_latch,
        traction_advance_counter_next, field_current_excess_counter_next,
        regen_delay_level, phase1_cap_counter_next, phase2_cap_counter_next, current_below_limit_cap_counter_next,
        phys_OLD_I, phys_OLD_IF_A, phys_OLD_PHI, regen_bc_smooth, bc_target_smooth)

    return stateless_out, state_out
end

-- Exposed for tests only (bitpack_selftest.lua, sr_latch_reset_priority_sanity.lua);
-- not used by calculateTick's own callers.
M.to_u32 = to_u32
M.get_bits = get_bits
M.get_bit = get_bit
M.put_bits = put_bits
M.put_bit = put_bit
M.sr_latch = sr_latch

return M
