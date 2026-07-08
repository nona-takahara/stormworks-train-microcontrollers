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
-- path (SR latches, capacitors/debounces, blinkers, the physics quasi-state,
-- BC smoothing) reads its OLD value (state_in) when computing this tick's
-- decisions, and writes a NEW value to state_out for next tick. Purely
-- combinational logic (derived only from fresh external inputs, or from other
-- freshly-computed combinational values) is evaluated fully within the same
-- tick -- unlike the literal gate-net model (SPEC.md §0.2, "every gate output
-- is 1-tick delayed"), this module lets combinational chains settle
-- instantly, which SPEC.md's own closing note anticipates and accepts
-- ("transient corner-case tick-counts may shrink, steady-state conclusions
-- are unchanged"). This collapsing is required to fit the whole control
-- surface in 8 state slots.
--
-- Physics (Newton-solve) is ported verbatim from
-- CHUSO1800_Traction_Controller/scripts/n409.lua -- that file is NOT modified;
-- test/scenarios/physics_regression_vs_n409.lua checks numeric parity.
--
-- This file is entirely self-contained (no `require`): Stormworks' Lua
-- sandbox has no module loader, so this whole file must be pastable
-- directly into a single Stormworks LUA node as-is. The bit-packing helpers
-- below (pack_bits/unpack_bits) are a plain string.pack("I4",...)/
-- string.unpack("I4",...) implementation inlined here for that reason --
-- there used to be a separate src/bitpack.lua required from here, which
-- cannot work once deployed; it has been folded in directly instead.

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
        ["M type"] = false,     -- off = 1800 (main.sw-net's mtype_toggle default)
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
local IS_1800_TYPE = not property.getBool("M type")
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
local CAP_DEBOUNCE_TICKS = 6              -- 0.1s charge, instant (0s) discharge
local TRACTION_BLINKER_ON_TICKS = 6       -- 0.1s
local TRACTION_BLINKER_OFF_TICKS = 6      -- 0.1s
local REGEN_WARNING_BLINKER_ON_TICKS = 6  -- 0.1s
local REGEN_WARNING_BLINKER_OFF_TICKS = 24 -- 0.4s
local REGEN_DELAY_CAP_FULL = 600          -- 0.5s charge / 10s discharge, scaled
local REGEN_DELAY_CAP_CHARGE_STEP = 20    -- 600/30 ticks
local REGEN_DELAY_CAP_DISCHARGE_STEP = 1  -- 600/600 ticks

--------------------------------------------------------------------------
-- Bit layouts (must match SIGNAL_MAP.md exactly)
--------------------------------------------------------------------------

M.STATE_LATCHES_LAYOUT = {
    { name = "position_counter",              bits = 5 }, -- 0-20
    { name = "phase1_latch",                  bits = 1 },
    { name = "phase2_latch",                  bits = 1 },
    { name = "regen_latch",                   bits = 1 },
    { name = "panta1_latch",                  bits = 1 },
    { name = "panta2_latch",                  bits = 1 },
    { name = "panta1_en_latch",               bits = 1 },
    { name = "panta2_en_latch",               bits = 1 },
    { name = "traction_blinker_phase",        bits = 1 },
    { name = "traction_blinker_counter",      bits = 3 }, -- 0-6
    { name = "regen_warning_blinker_phase",   bits = 1 },
    { name = "regen_warning_blinker_counter", bits = 5 }, -- 0-23
}

M.STATE_TIMERS_LAYOUT = {
    { name = "regen_delay_cap_level",             bits = 10 }, -- 0-600
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
    { name = "panta_enable_signal",    bits = 1 },
    { name = "panta_all_down_signal",  bits = 1 },
    { name = "panta1_up_signal",       bits = 1 },
    { name = "panta1_down_signal",     bits = 1 },
    { name = "panta2_up_signal",       bits = 1 },
    { name = "panta2_down_signal",     bits = 1 },
}

M.STATUS_BITS_LAYOUT = {
    { name = "cam_pulse",               bits = 1 },
    { name = "panta1_1800_active",      bits = 1 },
    { name = "panta2_1800_active",      bits = 1 },
    { name = "panta1_1800_latched",     bits = 1 },
    { name = "panta2_1800_latched",     bits = 1 },
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

-- CAPACITOR(charge_time=0.1s, discharge_time=0): instant reset when disabled.
local function debounce_cap_step(old_counter, enable)
    local new_counter
    if enable then
        new_counter = math.min(old_counter + 1, CAP_DEBOUNCE_TICKS)
    else
        new_counter = 0
    end
    return new_counter
end

-- CAPACITOR(charge_time=0.5s, discharge_time=10s), scaled to a 0-600 level.
local function regen_delay_cap_step(old_level, enable)
    local new_level
    if enable then
        new_level = math.min(old_level + REGEN_DELAY_CAP_CHARGE_STEP, REGEN_DELAY_CAP_FULL)
    else
        new_level = math.max(old_level - REGEN_DELAY_CAP_DISCHARGE_STEP, 0)
    end
    return new_level
end

-- BLINKER(on_ticks, off_ticks): while disabled, output is false (matching a
-- real disabled blinker). Re-enabling always starts a fresh off_ticks-long
-- "off" sub-phase before the first "on" -- this costs up to off_ticks of
-- extra latency versus a hypothetical "instant on when enabled" blinker, but
-- keeps the state bit an honest reflection of "current output", which is
-- what the rising-edge (PULSE) detection below relies on: edge =
-- (not old_phase_on) and new_phase_on, comparing state_in's value against
-- this tick's freshly computed one, with no extra "previous output" bit.
local function blinker_step(old_phase_on, old_counter, enable, on_ticks, off_ticks)
    if not enable then
        return false, 0
    end
    local counter = old_counter + 1
    local limit = old_phase_on and on_ticks or off_ticks
    local new_phase_on = old_phase_on
    if counter >= limit then
        new_phase_on = not old_phase_on
        counter = 0
    end
    return new_phase_on, counter
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
        panta1_latch = bool(latches.panta1_latch),
        panta2_latch = bool(latches.panta2_latch),
        panta1_en_latch = bool(latches.panta1_en_latch),
        panta2_en_latch = bool(latches.panta2_en_latch),
        traction_blinker_phase = bool(latches.traction_blinker_phase),
        traction_blinker_counter = latches.traction_blinker_counter,
        regen_warning_blinker_phase = bool(latches.regen_warning_blinker_phase),
        regen_warning_blinker_counter = latches.regen_warning_blinker_counter,
        regen_delay_cap_level = timers.regen_delay_cap_level,
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
        panta1_latch = f.panta1_latch,
        panta2_latch = f.panta2_latch,
        panta1_en_latch = f.panta1_en_latch,
        panta2_en_latch = f.panta2_en_latch,
        traction_blinker_phase = f.traction_blinker_phase,
        traction_blinker_counter = f.traction_blinker_counter,
        regen_warning_blinker_phase = f.regen_warning_blinker_phase,
        regen_warning_blinker_counter = f.regen_warning_blinker_counter,
    })
    local slot2 = pack_bits(M.STATE_TIMERS_LAYOUT, {
        regen_delay_cap_level = f.regen_delay_cap_level,
        phase1_cap_counter = f.phase1_cap_counter,
        phase2_cap_counter = f.phase2_cap_counter,
        current_below_limit_cap_counter = f.current_below_limit_cap_counter,
    })
    return {
        slot1, slot2,
        f.OLD_I or 0, f.OLD_IF_A or 0, f.OLD_PHI or 0,
        f.regen_bc_smooth or 0, f.bc_target_smooth or 0,
        0,
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
        panta_enable_signal = f.panta_enable_signal,
        panta_all_down_signal = f.panta_all_down_signal,
        panta1_up_signal = f.panta1_up_signal,
        panta1_down_signal = f.panta1_down_signal,
        panta2_up_signal = f.panta2_up_signal,
        panta2_down_signal = f.panta2_down_signal,
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
        panta1_1800_active = bool(status.panta1_1800_active),
        panta2_1800_active = bool(status.panta2_1800_active),
        panta1_1800_latched = bool(status.panta1_1800_latched),
        panta2_1800_latched = bool(status.panta2_1800_latched),
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
-- Main tick function
--------------------------------------------------------------------------

function M.calculateTick(stateless_in, state_in)
    local st = M.decode_state(state_in)
    local inbits = unpack_bits(M.INPUT_BITS_LAYOUT, stateless_in[4])

    local speed = stateless_in[1]
    local catenary_voltage_sw = stateless_in[2]
    local sap_raw = stateless_in[3]
    local bp_atm = stateless_in[5]  -- only read when SAP_ECB_IS_SAP (live property)
    local sap_atm = stateless_in[6] -- only read when SAP_ECB_IS_SAP (live property)

    local notch_pos = inbits.notch_pos
    local controller_stop = bool(inbits.controller_stop)
    local regen_flag = bool(inbits.regen_flag)
    local forward_signal = bool(inbits.forward_signal)
    local backward_signal = bool(inbits.backward_signal)
    local eb_signal = bool(inbits.eb_signal)
    local panta_enable_signal = bool(inbits.panta_enable_signal)
    local panta_all_down_signal = bool(inbits.panta_all_down_signal)
    local panta1_up_signal = bool(inbits.panta1_up_signal)
    local panta1_down_signal = bool(inbits.panta1_down_signal)
    local panta2_up_signal = bool(inbits.panta2_up_signal)
    local panta2_down_signal = bool(inbits.panta2_down_signal)

    ----------------------------------------------------------------
    -- Direction, EB condition (bucket c, fresh every tick)
    ----------------------------------------------------------------

    local direction = (forward_signal and 1 or 0) - (backward_signal and 1 or 0)
    local overspeed = math.abs(speed) > OVERSPEED_THRESHOLD
    -- Brake pressure: SAP_ECB_IS_SAP (live "SAP or ECB" property) selects
    -- between the physical SAP sensor pressure and the ECB offset chain,
    -- matching main.sw-net's brake_pressure_sw NUM_SWITCHBOX.
    local ecb_pressure_sw = eb_signal and ECB_OFFSET_EB_ACTIVE or ECB_OFFSET_EB_INACTIVE
    local brake_pressure_sw = SAP_ECB_IS_SAP and bp_atm or ecb_pressure_sw
    local brake_below_min = brake_pressure_sw < BRAKE_MIN_PRESSURE
    local power_cut = false -- provably dead, see README "Simplifications"

    local eb_condition = controller_stop or power_cut or (direction == 0) or overspeed or brake_below_min

    ----------------------------------------------------------------
    -- Notch processing
    ----------------------------------------------------------------

    local notch_enable_sw = eb_condition and 0 or 1
    local notch_eff = clamp(notch_pos, 0, 7) * notch_enable_sw
    local notch_ge1 = notch_eff >= 1 and notch_eff <= 7
    local notch_ge2 = notch_eff >= 2 and notch_eff <= 7
    local notch_ge3 = notch_eff >= 3 and notch_eff <= 7

    -- Cam-position echo ("notch_fb" in SPEC.md); zeroed under EB just like
    -- the original current_src_mux substitution (only ch7 survives EB).
    local notch_fb = eb_condition and 0 or st.position_counter
    local notch_fb_ge1 = notch_fb >= 0 and notch_fb <= 1
    local notch_fb_range_low = notch_fb >= 0 and notch_fb <= 13
    local notch_fb_range_high = notch_fb >= 14 and notch_fb <= 20
    local notch_fb_eq14 = notch_fb == 14
    local notch_fb_ne14 = not notch_fb_eq14
    local regen_available = notch_fb_ge1 -- duplicate of notch_fb_ge1, SPEC §5 dead-code note

    ----------------------------------------------------------------
    -- SAP/regen-BC pressure chain (fresh; feeds physics ch8 and low_bc flag)
    ----------------------------------------------------------------

    local ecb_sap_pressure = clamp(sap_raw + (5 - ecb_pressure_sw) * 7, 0, 36) / 8 + 1
    local sap_pressure_sw = SAP_ECB_IS_SAP and sap_atm or ecb_sap_pressure
    local regen_bc_target = -math.floor((sap_pressure_sw - 1) * 2) / 7.2
    local bc_target_below_min = regen_bc_target < BC_TARGET_MIN
    local low_bc_with_regen_flag = bc_target_below_min and regen_flag
    local regen_current = math.max(-regen_bc_target, 0)

    ----------------------------------------------------------------
    -- Physics (uses OLD phase1/phase2/regen -- see module header "Modeling rule")
    ----------------------------------------------------------------

    local phys = M.physics_tick({
        speed = speed,
        vl = catenary_voltage_sw,
        position_counter = st.position_counter,
        direction = direction,
        notch_eff = notch_eff,
        phase1 = st.phase1_latch,
        phase2 = st.phase2_latch,
        regen = st.regen_latch,
        notch_ge1 = notch_ge1,
        low_bc_with_regen_flag = low_bc_with_regen_flag,
        regen_bc_smooth_seed = st.regen_bc_smooth,
        regen_bc_target = regen_bc_target,
        OLD_I = st.OLD_I,
        OLD_IF_A = st.OLD_IF_A,
        OLD_PHI = st.OLD_PHI,
    })

    -- current_src_mux EB substitution: under EB only ch7 (bcT, here holding
    -- regen_current) survives; everything else reads 0.
    local motor_current = eb_condition and 0 or phys.motor_current
    local W = eb_condition and 0 or phys.W
    local accel = eb_condition and 0 or phys.accel
    local iF_a = eb_condition and 0 or phys.iF_a
    local bcT = eb_condition and regen_current or phys.bcT

    ----------------------------------------------------------------
    -- Current-limit debounce (feeds phase1/phase2 advance conditions)
    ----------------------------------------------------------------

    local current_limit_sw = st.phase2_latch and (POWER_LIMIT_CURRENT - 20) or POWER_LIMIT_CURRENT
    local current_below_limit = motor_current < current_limit_sw
    local current_below_limit_cap_counter = debounce_cap_step(st.current_below_limit_cap_counter, current_below_limit)
    local current_below_limit_cap_charged = st.current_below_limit_cap_counter >= CAP_DEBOUNCE_TICKS

    ----------------------------------------------------------------
    -- Phase1/phase2 debounce capacitors (enable = OWN old latch value)
    ----------------------------------------------------------------

    local phase1_cap_counter = debounce_cap_step(st.phase1_cap_counter, st.phase1_latch)
    local phase1_cap_charged = st.phase1_cap_counter >= CAP_DEBOUNCE_TICKS
    local phase2_cap_counter = debounce_cap_step(st.phase2_cap_counter, st.phase2_latch)
    local phase2_cap_charged = st.phase2_cap_counter >= CAP_DEBOUNCE_TICKS

    ----------------------------------------------------------------
    -- Brake-current / regen-warning chain
    ----------------------------------------------------------------

    local regen_bc_below_min = st.regen_bc_smooth < REGEN_BC_MIN
    local phase1_low_bc = st.phase1_latch and regen_bc_below_min
    local brake_limit_sw = phase1_low_bc and BRAKE_LIMIT_400 or BRAKE_LIMIT_300
    local brake_current_fb = iF_a
    local brake_current_high = brake_current_fb > brake_limit_sw
    local brake_current_above_300 = brake_current_fb > BRAKE_LIMIT_300
    local brake_current_high_phase1 = brake_current_above_300 and phase1_cap_charged
    local no_power_notch = not notch_ge1
    local regen_warning_cond = brake_current_high and no_power_notch

    local regen_warning_blinker_phase, regen_warning_blinker_counter = blinker_step(
        st.regen_warning_blinker_phase, st.regen_warning_blinker_counter, regen_warning_cond,
        REGEN_WARNING_BLINKER_ON_TICKS, REGEN_WARNING_BLINKER_OFF_TICKS)
    local regen_warning_pulse = (not st.regen_warning_blinker_phase) and regen_warning_blinker_phase
    local regen_pulse_regen_flag_off = regen_warning_pulse and (not regen_flag)

    ----------------------------------------------------------------
    -- Coasting / phase-reset condition
    ----------------------------------------------------------------

    local current_near_zero = motor_current >= -50 and motor_current <= 50
    local no_notch_no_regen_brake_demand = not (notch_ge1 or low_bc_with_regen_flag)
    local neutral_cond = current_near_zero and no_notch_no_regen_brake_demand
    local coasting_cond = neutral_cond and (not st.regen_latch)
    local phase_reset_cond = coasting_cond or regen_pulse_regen_flag_off

    ----------------------------------------------------------------
    -- Phase1 / phase2 / regen set-reset conditions (main.sw-net §3.6)
    ----------------------------------------------------------------

    local phase1_notch_active = st.phase1_latch and notch_ge1
    local phase1_not_high_notch = st.phase1_latch and notch_fb_ne14
    local phase1_regen_active = phase1_not_high_notch and st.regen_latch
    local power_with_regen = notch_ge1 and notch_fb_ge1

    local phase1_set_cond = notch_ge2 and notch_fb_range_low and phase1_cap_charged and current_below_limit_cap_charged
    local phase1_set = (power_with_regen and (not st.phase2_latch)) or (regen_warning_pulse and st.phase2_latch)

    local phase2_blinker_cond = notch_ge3 and notch_fb_range_high and phase2_cap_charged and current_below_limit_cap_charged
    local phase2_set_cond = notch_ge3 and notch_fb_eq14 and current_below_limit_cap_charged
    local phase2_reset = phase_reset_cond or (st.phase1_latch and not (notch_ge3 and notch_fb_eq14))

    local phase1_reset = phase_reset_cond or (regen_warning_pulse and phase1_cap_charged) or phase2_set_cond

    local traction_all_off = (not st.phase1_latch) and (not st.phase2_latch)
    local regen_not_available = not notch_fb_ge1
    local regen_off_all = regen_not_available and traction_all_off
    local regen_set_cond = st.phase2_latch and regen_available
    local regen_reset = phase1_notch_active or traction_all_off

    local new_phase1_latch = sr_latch(st.phase1_latch, phase1_set, phase1_reset)
    local new_phase2_latch = sr_latch(st.phase2_latch, phase2_set_cond, phase2_reset)
    local new_regen_latch = sr_latch(st.regen_latch, regen_set_cond, regen_reset)

    ----------------------------------------------------------------
    -- Cam advance (traction_blinker -> rising-edge pulse -> position_counter)
    ----------------------------------------------------------------

    local traction_any_active = phase1_set_cond or phase2_blinker_cond or regen_off_all or phase1_regen_active
    local traction_blinker_phase, traction_blinker_counter = blinker_step(
        st.traction_blinker_phase, st.traction_blinker_counter, traction_any_active,
        TRACTION_BLINKER_ON_TICKS, TRACTION_BLINKER_OFF_TICKS)
    local position_tick_pulse = (not st.traction_blinker_phase) and traction_blinker_phase
    local new_position_counter = (st.position_counter + (position_tick_pulse and 1 or 0)) % 21
    local position_delta = new_position_counter - st.position_counter
    local cam_pulse = not (position_delta >= 0 and position_delta <= 1)

    ----------------------------------------------------------------
    -- Regen BC ramp / delay capacitor
    ----------------------------------------------------------------

    local regen_delay_cap_charged = st.regen_delay_cap_level >= REGEN_DELAY_CAP_FULL
    local regen_bc_enable = regen_delay_cap_charged or (not regen_flag)
    local regen_bc_sw = regen_bc_enable and 0 or regen_bc_target
    local new_regen_bc_smooth = math.min(
        clamp(regen_bc_sw, st.regen_bc_smooth - 0.1, st.regen_bc_smooth + 0.02), 0)
    local new_regen_delay_cap_level = regen_delay_cap_step(st.regen_delay_cap_level, brake_current_high_phase1)

    ----------------------------------------------------------------
    -- BC target smoothing (EMA); accel already EB-zeroed above.
    ----------------------------------------------------------------

    local new_bc_target_smooth = accel * 0.2 + st.bc_target_smooth * 0.8

    ----------------------------------------------------------------
    -- Pantograph latches
    ----------------------------------------------------------------

    local new_panta1_latch = sr_latch(st.panta1_latch, panta1_up_signal, panta1_down_signal)
    local new_panta2_latch = sr_latch(st.panta2_latch, panta2_up_signal, panta2_down_signal)
    local panta1_set_cond = (not st.panta1_latch) and panta_enable_signal
    local panta2_set_cond = (not st.panta2_latch) and panta_enable_signal
    local new_panta1_en_latch = sr_latch(st.panta1_en_latch, panta1_set_cond, panta_all_down_signal)
    local new_panta2_en_latch = sr_latch(st.panta2_en_latch, panta2_set_cond, panta_all_down_signal)

    local panta1_1800_active = new_panta1_en_latch and IS_1800_TYPE
    local panta2_1800_active = new_panta2_en_latch and IS_1800_TYPE
    local panta1_1800_latched = new_panta1_latch and IS_1800_TYPE
    local panta2_1800_latched = new_panta2_latch and IS_1800_TYPE

    ----------------------------------------------------------------
    -- Assemble outputs
    ----------------------------------------------------------------

    local status_bits = pack_bits(M.STATUS_BITS_LAYOUT, {
        cam_pulse = cam_pulse,
        panta1_1800_active = panta1_1800_active,
        panta2_1800_active = panta2_1800_active,
        panta1_1800_latched = panta1_1800_latched,
        panta2_1800_latched = panta2_1800_latched,
        phase1_latch = new_phase1_latch,
        phase2_latch = new_phase2_latch,
        regen_latch = new_regen_latch,
        notch_ge1 = notch_ge1,
        low_bc_with_regen_flag = low_bc_with_regen_flag,
        regen_warning_cond = regen_warning_cond,
        power_cut = power_cut,
    })

    local stateless_out = {
        motor_current,
        W,
        new_bc_target_smooth,
        bcT,
        status_bits,
        0, 0, 0,
    }

    local state_out = M.encode_state({
        position_counter = new_position_counter,
        phase1_latch = new_phase1_latch,
        phase2_latch = new_phase2_latch,
        regen_latch = new_regen_latch,
        panta1_latch = new_panta1_latch,
        panta2_latch = new_panta2_latch,
        panta1_en_latch = new_panta1_en_latch,
        panta2_en_latch = new_panta2_en_latch,
        traction_blinker_phase = traction_blinker_phase,
        traction_blinker_counter = traction_blinker_counter,
        regen_warning_blinker_phase = regen_warning_blinker_phase,
        regen_warning_blinker_counter = regen_warning_blinker_counter,
        regen_delay_cap_level = new_regen_delay_cap_level,
        phase1_cap_counter = phase1_cap_counter,
        phase2_cap_counter = phase2_cap_counter,
        current_below_limit_cap_counter = current_below_limit_cap_counter,
        OLD_I = phys.OLD_I,
        OLD_IF_A = phys.OLD_IF_A,
        OLD_PHI = phys.OLD_PHI,
        regen_bc_smooth = new_regen_bc_smooth,
        bc_target_smooth = new_bc_target_smooth,
    })

    return stateless_out, state_out
end

-- Exposed for test/scenarios/bitpack_selftest.lua only; not used by
-- calculateTick's own callers.
M.pack_bits = pack_bits
M.unpack_bits = unpack_bits
M.bool = bool

return M
