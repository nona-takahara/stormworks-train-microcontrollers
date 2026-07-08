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
-- This file is entirely self-contained (no `require`): Stormworks' Lua
-- sandbox has no module loader, so this whole file must be pastable
-- directly into a single Stormworks LUA node as-is. The bit-packing helpers
-- below (pack_bits/unpack_bits) are a plain string.pack("I4",...)/
-- string.unpack("I4",...) implementation inlined here for that reason.

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
-- every tick). This is the mechanism that keeps SAP/ECB mode, M-type, and
-- the two numeric limits genuinely tunable per-vehicle in Stormworks'
-- property panel -- matching the original main.sw-net PROPERTY_TOGGLE/
-- PROPERTY_NUMBER node names exactly -- instead of baking them into source.
-- property.get*() sits entirely outside the 8+8 composite-channel budget,
-- so this costs no input slots.
--
-- Outside Stormworks (this repo's plain-`lua` test suite), the `property`
-- global does not exist; fall back to the same defaults the original
-- main.sw-net PROPERTY_* nodes ship with (PROPERTY_NUMBER value=..., and
-- PROPERTY_TOGGLE with no v= override, which Stormworks treats as off).
--------------------------------------------------------------------------

local property = property
if type(property) ~= "table" then
    local DEFAULT_BOOL_PROPERTIES = {
        ["SAP or ECB"] = false, -- off = ECB (main.sw-net's sap_ecb_toggle default)
    }
    local DEFAULT_NUMBER_PROPERTIES = {
        ["Over Speed Th. [m/s]"] = 32,       -- main.sw-net's overspeed_threshold
        ["Power Limit Current [A]"] = 210,   -- main.sw-net's power_limit_current
    }
    property = {
        getBool = function(name) return DEFAULT_BOOL_PROPERTIES[name] end,
        getNumber = function(name) return DEFAULT_NUMBER_PROPERTIES[name] end,
    }
end

local SAP_ECB_IS_SAP = property.getBool("SAP or ECB")
local OVERSPEED_THRESHOLD = property.getNumber("Over Speed Th. [m/s]")     -- m/s
local POWER_LIMIT_CURRENT = property.getNumber("Power Limit Current [A]") -- A

-- Plain CONST nodes in main.sw-net (not PROPERTY_* -- never exposed as
-- in-game-tunable in the original design either), so these stay source
-- constants.
local BRAKE_MIN_PRESSURE = 4         -- atm
local BRAKE_LIMIT_300 = 300
local BRAKE_LIMIT_400 = 400
local ECB_OFFSET_EB_ACTIVE = 0
local ECB_OFFSET_EB_INACTIVE = 5
local REGEN_BC_MIN = -0.1
local BC_TARGET_MIN = -0.05

-- Tick-rate-derived timer constants (Stormworks assumed 60 ticks/sec, SPEC §0.2).
local CAP_DEBOUNCE_TICKS = 6              -- 0.1s debounce, instant reset when disabled
local CAM_ADVANCE_PERIOD_TICKS = 12       -- 0.1s+0.1s traction_blinker period
local REGEN_WARNING_PERIOD_TICKS = 30     -- 0.1s+0.4s regen_warning_blinker period

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
-- Bit layouts (must match SIGNAL_MAP.md exactly)
--------------------------------------------------------------------------

M.STATE_LATCHES_LAYOUT = {
    { name = "position_counter",              bits = 5 }, -- 0-20
    { name = "phase1_latch",                  bits = 1 },
    { name = "phase2_latch",                  bits = 1 },
    { name = "regen_latch",                   bits = 1 },
    { name = "traction_advance_counter",      bits = 4 }, -- 0-12, periodic_pulse_step
    { name = "regen_warning_counter",         bits = 5 }, -- 0-30, periodic_pulse_step
}

M.STATE_TIMERS_LAYOUT = {
    { name = "regen_delay_level",                 bits = 10 }, -- 0-600, see REGEN_DELAY_* constants
    { name = "phase1_cap_counter",                bits = 3 },  -- 0-6
    { name = "phase2_cap_counter",                bits = 3 },  -- 0-6
    { name = "current_below_limit_cap_counter",   bits = 3 },  -- 0-6
}

M.INPUT_BITS_LAYOUT = {
    { name = "notch_pos",              bits = 3 }, -- 0-7
    { name = "controller_stop",        bits = 1 },
    { name = "regen_flag",             bits = 1 },
    { name = "forward_signal",         bits = 1 },
    { name = "backward_signal",        bits = 1 },
    { name = "eb_signal",              bits = 1 },
}

M.STATUS_BITS_LAYOUT = {
    { name = "cam_pulse",               bits = 1 },
    { name = "phase1_latch",            bits = 1 },
    { name = "phase2_latch",            bits = 1 },
    { name = "regen_latch",             bits = 1 },
    { name = "notch_ge1",               bits = 1 },
    { name = "low_bc_with_regen_flag",  bits = 1 },
    { name = "regen_warning_cond",      bits = 1 },
    { name = "power_cut",               bits = 1 }, -- always 0, see README "Simplifications"
}

--------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------

local function clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

-- Bit packing: several small integer/boolean fields into one 32-bit slot
-- value. `layout` is an ordered list of { name = string, bits = 1..32 };
-- layout[1] occupies the lowest bits. The 32-bit boundary is enforced by
-- round-tripping through string.pack("I4",...)/string.unpack("I4",...) so
-- overflow wraps like a real 32-bit unsigned value instead of silently
-- growing past what a single slot can hold.
local function pack_bits(layout, fields)
    local acc = 0
    local shift = 0
    for _, field in ipairs(layout) do
        local width = field.bits
        local max = (1 << width) - 1
        local raw = fields[field.name] or 0
        if type(raw) == "boolean" then
            raw = raw and 1 or 0
        end
        raw = math.floor(raw)
        if raw < 0 then raw = 0 end
        if raw > max then raw = max end
        acc = acc | (raw << shift)
        shift = shift + width
    end
    return string.unpack("I4", string.pack("I4", acc))
end

local function unpack_bits(layout, value)
    local acc = string.unpack("I4", string.pack("I4", math.floor(value or 0)))
    local fields = {}
    local shift = 0
    for _, field in ipairs(layout) do
        local width = field.bits
        local mask = (1 << width) - 1
        fields[field.name] = (acc >> shift) & mask
        shift = shift + width
    end
    return fields
end

local function bool(intval)
    return intval ~= 0
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

-- physics_tick: byte-for-byte port of n409.lua's onTick body. `p` fields
-- mirror the original sim_input composite channels / traction_status_bool:
--   p.speed, p.vl (=catenary_voltage_sw), p.position_counter (OLD cam),
--   p.direction, p.notch_eff, p.regen_bc_smooth_seed (OLD, ch7),
--   p.regen_bc_target (fresh, ch8), p.phase1/p.phase2/p.regen (OLD latches),
--   p.notch_ge1, p.low_bc_with_regen_flag (fresh bools),
--   p.OLD_I, p.OLD_IF_A, p.OLD_PHI (OLD physics quasi-state).
function M.physics_tick(p)
    local rpm = p.speed * 9.55 * GEAR_RATIO / WHEEL_R
    local vl = p.vl
    local notch = p.position_counter + 1 -- n409.lua's "notch" var is actually cam-position+1
    local direction = p.direction
    local res = 100000
    local srsmtr = 4
    local iF_a = 150
    local target_i = NEWTON_SEED

    if (not p.phase1) and (not p.phase2) then vl = 0 end
    if p.phase1 then srsmtr = 8 end
    if p.phase2 and notch == 1 then srsmtr = 4 end

    local OLD_I, OLD_IF_A, OLD_PHI = p.OLD_I, p.OLD_IF_A, p.OLD_PHI

    if p.regen then
        if p.low_bc_with_regen_flag then
            local oldtrq = direction * (MOT_CTRL * 9.55 * K * OLD_PHI * OLD_I * GEAR_RATIO * 0.99 / WHEEL_R / WEIGHT)
            iF_a = OLD_IF_A + (oldtrq - p.regen_bc_smooth_seed) * 20
            iF_a = iF_a * math.min(1, (470 / (K * math.abs(rpm))) / calc_phi(iF_a + OLD_I * 0.15))
        else
            if p.notch_ge1 and p.notch_eff <= 3 then target_i = OLD_IF_A end
            if not p.notch_ge1 then target_i = 0 end
            if target_i == 0 then target_i = math.max(math.min(0, OLD_I + 20), OLD_I - 20) end
            iF_a = OLD_IF_A + (OLD_I - target_i) * 0.1
        end
    else
        target_i = OLD_IF_A
        if p.notch_eff == 0 then target_i = 0 end
        iF_a = OLD_IF_A + (OLD_I - target_i) * 0.1
        if p.notch_eff ~= 0 and iF_a > 180 then iF_a = 180 end
    end

    if srsmtr == 8 then res = SR[notch] end
    if srsmtr == 4 then res = PR[notch] end

    if iF_a < 20 then iF_a = 20 elseif iF_a > 500 then iF_a = 500 end

    local i, phi = calc_current_phi(vl / srsmtr, rpm, res / srsmtr, direction * 0.2, iF_a * direction, NEWTON_SEED)
    if vl == 0 then i = 0; phi = 0 end

    local trqN = 9.55 * K * phi * i
    local bcT = math.min(direction * MOT_CTRL * trqN * GEAR_RATIO / WHEEL_R / WEIGHT, 0) - p.regen_bc_target
    if bcT < 0.01 and i < 0 then bcT = 0 end

    return {
        motor_current = i,
        back_emf = K * phi * rpm,
        accel = MOT_CTRL * trqN * GEAR_RATIO * 0.99 / WHEEL_R / WEIGHT,
        W = vl * i * (MOT_CTRL / srsmtr) * 2,
        iF_a = iF_a,
        bcT = bcT,
        OLD_I = i,
        OLD_IF_A = iF_a,
        OLD_PHI = phi,
    }
end

--------------------------------------------------------------------------
-- State (de)serialization helpers (used by the test scenarios and by
-- calculateTick itself)
--------------------------------------------------------------------------

function M.zero_state()
    return { 0, 0, 0, 0, 0, 0, 0, 0 }
end

function M.decode_state(state_in)
    local latches = unpack_bits(M.STATE_LATCHES_LAYOUT, state_in[1])
    local timers = unpack_bits(M.STATE_TIMERS_LAYOUT, state_in[2])
    return {
        position_counter = latches.position_counter,
        phase1_latch = bool(latches.phase1_latch),
        phase2_latch = bool(latches.phase2_latch),
        regen_latch = bool(latches.regen_latch),
        traction_advance_counter = latches.traction_advance_counter,
        regen_warning_counter = latches.regen_warning_counter,
        regen_delay_level = timers.regen_delay_level,
        phase1_cap_counter = timers.phase1_cap_counter,
        phase2_cap_counter = timers.phase2_cap_counter,
        current_below_limit_cap_counter = timers.current_below_limit_cap_counter,
        OLD_I = state_in[3],
        OLD_IF_A = state_in[4],
        OLD_PHI = state_in[5],
        regen_bc_smooth = state_in[6],
        bc_target_smooth = state_in[7],
    }
end

function M.encode_state(f)
    local slot1 = pack_bits(M.STATE_LATCHES_LAYOUT, {
        position_counter = f.position_counter,
        phase1_latch = f.phase1_latch,
        phase2_latch = f.phase2_latch,
        regen_latch = f.regen_latch,
        traction_advance_counter = f.traction_advance_counter,
        regen_warning_counter = f.regen_warning_counter,
    })
    local slot2 = pack_bits(M.STATE_TIMERS_LAYOUT, {
        regen_delay_level = f.regen_delay_level,
        phase1_cap_counter = f.phase1_cap_counter,
        phase2_cap_counter = f.phase2_cap_counter,
        current_below_limit_cap_counter = f.current_below_limit_cap_counter,
    })
    return {
        slot1, slot2,
        f.OLD_I or 0, f.OLD_IF_A or 0, f.OLD_PHI or 0,
        f.regen_bc_smooth or 0, f.bc_target_smooth or 0,
        0, -- spare
    }
end

function M.encode_stateless_in(f)
    local bits = pack_bits(M.INPUT_BITS_LAYOUT, {
        notch_pos = f.notch_pos,
        controller_stop = f.controller_stop,
        regen_flag = f.regen_flag,
        forward_signal = f.forward_signal,
        backward_signal = f.backward_signal,
        eb_signal = f.eb_signal,
    })
    return {
        f.speed or 0,
        f.catenary_voltage_sw or 0,
        f.sap_raw or 0,
        bits,
        f.bp_atm or 0,
        f.sap_atm or 0,
        0, 0,
    }
end

function M.decode_stateless_out(stateless_out)
    local status = unpack_bits(M.STATUS_BITS_LAYOUT, stateless_out[5])
    return {
        motor_current = stateless_out[1],
        W = stateless_out[2],
        bc_target_smooth = stateless_out[3],
        bcT = stateless_out[4],
        cam_pulse = bool(status.cam_pulse),
        phase1_latch = bool(status.phase1_latch),
        phase2_latch = bool(status.phase2_latch),
        regen_latch = bool(status.regen_latch),
        notch_ge1 = bool(status.notch_ge1),
        low_bc_with_regen_flag = bool(status.low_bc_with_regen_flag),
        regen_warning_cond = bool(status.regen_warning_cond),
        power_cut = bool(status.power_cut),
    }
end

--------------------------------------------------------------------------
-- Tick sub-steps, each roughly one SPEC.md §3.x section. `st` throughout is
-- always the OLD decoded state (this tick's input); functions return plain
-- values/tables, calculateTick threads them together and does all state_out
-- assembly at the end.
--------------------------------------------------------------------------

local function decode_inputs(stateless_in)
    local bits = unpack_bits(M.INPUT_BITS_LAYOUT, stateless_in[4])
    return {
        speed = stateless_in[1],
        catenary_voltage_sw = stateless_in[2],
        sap_raw = stateless_in[3],
        bp_atm = stateless_in[5],  -- only used when SAP_ECB_IS_SAP (live property)
        sap_atm = stateless_in[6], -- only used when SAP_ECB_IS_SAP (live property)
        notch_pos = bits.notch_pos,
        controller_stop = bool(bits.controller_stop),
        regen_flag = bool(bits.regen_flag),
        forward_signal = bool(bits.forward_signal),
        backward_signal = bool(bits.backward_signal),
        eb_signal = bool(bits.eb_signal),
    }
end

-- SPEC §3.5 (EB / power-cut condition) + the brake-pressure half of §3.8.
local function eb_and_brake_pressure(inp)
    local direction = (inp.forward_signal and 1 or 0) - (inp.backward_signal and 1 or 0)
    local overspeed = math.abs(inp.speed) > OVERSPEED_THRESHOLD
    local ecb_pressure_sw = inp.eb_signal and ECB_OFFSET_EB_ACTIVE or ECB_OFFSET_EB_INACTIVE
    -- SAP_ECB_IS_SAP (live "SAP or ECB" property) selects between the
    -- physical SAP sensor pressure and the ECB offset chain, matching
    -- main.sw-net's brake_pressure_sw NUM_SWITCHBOX.
    local brake_pressure_sw = SAP_ECB_IS_SAP and inp.bp_atm or ecb_pressure_sw
    local brake_below_min = brake_pressure_sw < BRAKE_MIN_PRESSURE
    local power_cut = false -- provably dead, see README "Simplifications"
    local eb_condition = inp.controller_stop or power_cut or (direction == 0) or overspeed or brake_below_min
    return direction, eb_condition, ecb_pressure_sw, power_cut
end

-- SPEC §3.3 (notch processing) + §3.2's cam-position echo ("notch_fb").
local function notch_and_cam_feedback(inp, st, eb_condition)
    local notch_enable_sw = eb_condition and 0 or 1
    local notch_eff = clamp(inp.notch_pos, 0, 7) * notch_enable_sw
    -- Cam-position echo zeroed under EB, matching the original
    -- current_src_mux substitution (only ch7 survives EB).
    local notch_fb = eb_condition and 0 or st.position_counter
    return {
        notch_eff = notch_eff,
        notch_ge1 = notch_eff >= 1 and notch_eff <= 7,
        notch_ge2 = notch_eff >= 2 and notch_eff <= 7,
        notch_ge3 = notch_eff >= 3 and notch_eff <= 7,
        notch_fb_ge1 = notch_fb >= 0 and notch_fb <= 1,
        notch_fb_range_low = notch_fb >= 0 and notch_fb <= 13,
        notch_fb_range_high = notch_fb >= 14 and notch_fb <= 20,
        notch_fb_eq14 = notch_fb == 14,
        notch_fb_ne14 = notch_fb ~= 14,
    }
end

-- SPEC §3.8 (regen-BC target chain, fresh every tick).
local function brake_demand(inp, ecb_pressure_sw)
    local ecb_sap_pressure = clamp(inp.sap_raw + (5 - ecb_pressure_sw) * 7, 0, 36) / 8 + 1
    local sap_pressure_sw = SAP_ECB_IS_SAP and inp.sap_atm or ecb_sap_pressure
    local regen_bc_target = -math.floor((sap_pressure_sw - 1) * 2) / 7.2
    local bc_target_below_min = regen_bc_target < BC_TARGET_MIN
    return {
        regen_bc_target = regen_bc_target,
        low_bc_with_regen_flag = bc_target_below_min and inp.regen_flag,
        regen_current = math.max(-regen_bc_target, 0),
    }
end

-- current_src_mux EB substitution: under EB only ch7 (bcT, here holding
-- regen_current) survives; everything else reads 0.
local function eb_substitute(phys, eb_condition, regen_current)
    return {
        motor_current = eb_condition and 0 or phys.motor_current,
        W = eb_condition and 0 or phys.W,
        accel = eb_condition and 0 or phys.accel,
        iF_a = eb_condition and 0 or phys.iF_a,
        bcT = eb_condition and regen_current or phys.bcT,
    }
end

-- SPEC §3.6/§3.7 debounce timers (current-limit and phase1/phase2's own
-- "has been on for 0.1s" gates). "*_charged" reflects the OLD counter (this
-- tick's decision input); "*_next" is what gets stored for next tick.
local function debounce_block(st, motor_current)
    local current_limit_sw = st.phase2_latch and (POWER_LIMIT_CURRENT - 20) or POWER_LIMIT_CURRENT
    local current_below_limit = motor_current < current_limit_sw
    return {
        current_limit_sw = current_limit_sw,
        current_below_limit_cap_charged = debounce_charged(st.current_below_limit_cap_counter),
        current_below_limit_cap_counter_next = debounce_step(st.current_below_limit_cap_counter, current_below_limit),
        phase1_cap_charged = debounce_charged(st.phase1_cap_counter),
        phase1_cap_counter_next = debounce_step(st.phase1_cap_counter, st.phase1_latch),
        phase2_cap_charged = debounce_charged(st.phase2_cap_counter),
        phase2_cap_counter_next = debounce_step(st.phase2_cap_counter, st.phase2_latch),
    }
end

-- SPEC §3.6 brake-current / regen-warning-pulse chain.
local function regen_warning_block(st, iF_a, notch_ge1, phase1_cap_charged)
    local regen_bc_below_min = st.regen_bc_smooth < REGEN_BC_MIN
    local phase1_low_bc = st.phase1_latch and regen_bc_below_min
    local brake_limit_sw = phase1_low_bc and BRAKE_LIMIT_400 or BRAKE_LIMIT_300
    local brake_current_above_300 = iF_a > BRAKE_LIMIT_300
    local regen_warning_cond = (iF_a > brake_limit_sw) and (not notch_ge1)
    local counter_next, pulse = periodic_pulse_step(
        st.regen_warning_counter, regen_warning_cond, REGEN_WARNING_PERIOD_TICKS)
    return {
        brake_current_high_phase1 = brake_current_above_300 and phase1_cap_charged,
        regen_warning_cond = regen_warning_cond,
        regen_warning_counter_next = counter_next,
        regen_warning_pulse = pulse,
    }
end

-- SPEC §3.6 core state machine: phase1/phase2/regen SR latches. `notch`
-- (from notch_and_cam_feedback) already carries both the notch_ge* fields
-- and the cam-position-echo notch_fb_* fields in one table.
local function phase_state_machine(st, notch, cond)
    local phase1_notch_active = st.phase1_latch and notch.notch_ge1
    local phase1_regen_active = st.phase1_latch and notch.notch_fb_ne14 and st.regen_latch
    local power_with_regen = notch.notch_ge1 and notch.notch_fb_ge1

    local current_near_zero = cond.motor_current >= -50 and cond.motor_current <= 50
    local no_notch_no_regen_brake_demand = not (notch.notch_ge1 or cond.low_bc_with_regen_flag)
    local neutral_cond = current_near_zero and no_notch_no_regen_brake_demand
    local coasting_cond = neutral_cond and (not st.regen_latch)
    local regen_pulse_regen_flag_off = cond.regen_warning_pulse and (not cond.regen_flag)
    local phase_reset_cond = coasting_cond or regen_pulse_regen_flag_off

    local phase1_set_cond = notch.notch_ge2 and notch.notch_fb_range_low
        and cond.phase1_cap_charged and cond.current_below_limit_cap_charged
    local phase1_set = (power_with_regen and (not st.phase2_latch))
        or (cond.regen_warning_pulse and st.phase2_latch)
    local phase1_reset = phase_reset_cond
        or (cond.regen_warning_pulse and cond.phase1_cap_charged)

    local phase2_blinker_cond = notch.notch_ge3 and notch.notch_fb_range_high
        and cond.phase2_cap_charged and cond.current_below_limit_cap_charged
    local phase2_set_cond = notch.notch_ge3 and notch.notch_fb_eq14 and cond.current_below_limit_cap_charged
    local phase2_reset = phase_reset_cond or (st.phase1_latch and not (notch.notch_ge3 and notch.notch_fb_eq14))

    -- phase2_set_cond doubles as an extra phase1-reset trigger (Series ->
    -- Parallel transition resets phase1 the same tick phase2 sets).
    phase1_reset = phase1_reset or phase2_set_cond

    local traction_all_off = (not st.phase1_latch) and (not st.phase2_latch)
    local regen_set_cond = st.phase2_latch and notch.notch_fb_ge1
    local regen_reset = phase1_notch_active or traction_all_off
    local regen_off_all = (not notch.notch_fb_ge1) and traction_all_off

    return {
        phase1_latch = sr_latch(st.phase1_latch, phase1_set, phase1_reset),
        phase2_latch = sr_latch(st.phase2_latch, phase2_set_cond, phase2_reset),
        regen_latch = sr_latch(st.regen_latch, regen_set_cond, regen_reset),
        traction_any_active = phase1_set_cond or phase2_blinker_cond or regen_off_all or phase1_regen_active,
    }
end

-- SPEC §3.2 cam advance (periodic pulse while traction_any_active).
local function advance_cam(st, traction_any_active)
    local counter_next, pulse = periodic_pulse_step(
        st.traction_advance_counter, traction_any_active, CAM_ADVANCE_PERIOD_TICKS)
    local position_counter = (st.position_counter + (pulse and 1 or 0)) % 21
    local delta = position_counter - st.position_counter
    return {
        position_counter = position_counter,
        cam_pulse = not (delta >= 0 and delta <= 1), -- true only on the 20->0 ring wrap
        traction_advance_counter_next = counter_next,
    }
end

-- SPEC §3.8 BC / regen-BC smoothing.
local function smooth_bc(st, accel, regen_bc_target, regen_flag, brake_current_high_phase1)
    local regen_bc_enable = regen_delay_charged(st.regen_delay_level) or (not regen_flag)
    local regen_bc_sw = regen_bc_enable and 0 or regen_bc_target
    return {
        bc_target_smooth = accel * 0.2 + st.bc_target_smooth * 0.8,
        regen_bc_smooth = math.min(clamp(regen_bc_sw, st.regen_bc_smooth - 0.1, st.regen_bc_smooth + 0.02), 0),
        regen_delay_level = regen_delay_step(st.regen_delay_level, brake_current_high_phase1),
    }
end

--------------------------------------------------------------------------
-- Main tick function
--------------------------------------------------------------------------

function M.calculateTick(stateless_in, state_in)
    local st = M.decode_state(state_in)
    local inp = decode_inputs(stateless_in)

    local direction, eb_condition, ecb_pressure_sw = eb_and_brake_pressure(inp)
    local notch = notch_and_cam_feedback(inp, st, eb_condition)
    local demand = brake_demand(inp, ecb_pressure_sw)

    -- Physics always uses OLD phase1/phase2/regen (breaks the physics <->
    -- state-machine cycle; see module header "Modeling rule").
    local phys = M.physics_tick({
        speed = inp.speed,
        vl = inp.catenary_voltage_sw,
        position_counter = st.position_counter,
        direction = direction,
        notch_eff = notch.notch_eff,
        phase1 = st.phase1_latch,
        phase2 = st.phase2_latch,
        regen = st.regen_latch,
        notch_ge1 = notch.notch_ge1,
        low_bc_with_regen_flag = demand.low_bc_with_regen_flag,
        regen_bc_smooth_seed = st.regen_bc_smooth,
        regen_bc_target = demand.regen_bc_target,
        OLD_I = st.OLD_I,
        OLD_IF_A = st.OLD_IF_A,
        OLD_PHI = st.OLD_PHI,
    })
    local elec = eb_substitute(phys, eb_condition, demand.regen_current)

    local debounce = debounce_block(st, elec.motor_current)
    local warn = regen_warning_block(st, elec.iF_a, notch.notch_ge1, debounce.phase1_cap_charged)

    local phase = phase_state_machine(st, notch, {
        motor_current = elec.motor_current,
        low_bc_with_regen_flag = demand.low_bc_with_regen_flag,
        regen_warning_pulse = warn.regen_warning_pulse,
        regen_flag = inp.regen_flag,
        phase1_cap_charged = debounce.phase1_cap_charged,
        phase2_cap_charged = debounce.phase2_cap_charged,
        current_below_limit_cap_charged = debounce.current_below_limit_cap_charged,
    })
    local cam = advance_cam(st, phase.traction_any_active)
    local bc = smooth_bc(st, elec.accel, demand.regen_bc_target, inp.regen_flag, warn.brake_current_high_phase1)

    ----------------------------------------------------------------
    -- Assemble outputs
    ----------------------------------------------------------------

    local status_bits = pack_bits(M.STATUS_BITS_LAYOUT, {
        cam_pulse = cam.cam_pulse,
        phase1_latch = phase.phase1_latch,
        phase2_latch = phase.phase2_latch,
        regen_latch = phase.regen_latch,
        notch_ge1 = notch.notch_ge1,
        low_bc_with_regen_flag = demand.low_bc_with_regen_flag,
        regen_warning_cond = warn.regen_warning_cond,
        power_cut = false,
    })

    local stateless_out = {
        elec.motor_current,
        elec.W,
        bc.bc_target_smooth,
        elec.bcT,
        status_bits,
        0, 0, 0,
    }

    local state_out = M.encode_state({
        position_counter = cam.position_counter,
        phase1_latch = phase.phase1_latch,
        phase2_latch = phase.phase2_latch,
        regen_latch = phase.regen_latch,
        traction_advance_counter = cam.traction_advance_counter_next,
        regen_warning_counter = warn.regen_warning_counter_next,
        regen_delay_level = bc.regen_delay_level,
        phase1_cap_counter = debounce.phase1_cap_counter_next,
        phase2_cap_counter = debounce.phase2_cap_counter_next,
        current_below_limit_cap_counter = debounce.current_below_limit_cap_counter_next,
        OLD_I = phys.OLD_I,
        OLD_IF_A = phys.OLD_IF_A,
        OLD_PHI = phys.OLD_PHI,
        regen_bc_smooth = bc.regen_bc_smooth,
        bc_target_smooth = bc.bc_target_smooth,
    })

    return stateless_out, state_out
end

-- Exposed for tests only (bitpack_selftest.lua, sr_latch_reset_priority_sanity.lua);
-- not used by calculateTick's own callers.
M.pack_bits = pack_bits
M.unpack_bits = unpack_bits
M.bool = bool
M.sr_latch = sr_latch

return M
