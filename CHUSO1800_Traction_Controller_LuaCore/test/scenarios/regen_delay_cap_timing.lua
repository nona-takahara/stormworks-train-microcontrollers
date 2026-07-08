-- SPEC.md §3.8: regen_delay was CAPACITOR(charge_time=0.5s, discharge_time=10s)
-- in main.sw-net. This module models it directly in seconds (a raw double
-- state slot): +1/60 s per enabled tick, capped at 0.5s; -1/1200 s per
-- disabled tick (10s to empty is 20x slower than 0.5s to charge), floored
-- at 0. "Charged" (regen_bc_enable-relevant) means >= 0.5s (with a small
-- epsilon guard for float-accumulation drift -- see regen_delay_charged in
-- src/chuso1800_core.lua).

local core = require("chuso1800_core")

local TICK_SECONDS = 1 / 60
local CHARGE_FULL = 0.5
local DISCHARGE_RATE = TICK_SECONDS * (0.5 / 10)

return function(h)
    -- Charge rate: phase1 latched + sustained brake demand (regen_flag +
    -- bc_target_below_min) reliably drives brake_current_high_phase1 true
    -- for the first several ticks (until the field-current control law
    -- settles below the 300A threshold on its own -- verified empirically,
    -- so this test only asserts the +1/60s/tick behavior over a window
    -- where it demonstrably holds, not indefinitely).
    local charge_state = core.encode_state({
        position_counter = 5, phase1_latch = true, phase1_cap_counter = 6,
        OLD_IF_A = 300, OLD_I = 1000,
    })
    local charge_inputs = core.encode_stateless_in({
        speed = 5, catenary_voltage_sw = 1500, notch_pos = 0, forward_signal = true,
        regen_flag = true, sap_raw = 10,
    })
    for tick = 1, 10 do
        local _, ns = core.calculateTick(charge_inputs, charge_state)
        charge_state = ns
        local st = core.decode_state(charge_state)
        h.assert_near(st.regen_delay_seconds, math.min(tick * TICK_SECONDS, CHARGE_FULL), 1e-9,
            "charges at +1/60s per tick, tick " .. tick)
    end

    -- Charge boundary: caps at 0.5s, never overshoots.
    local near_full = core.encode_state({
        position_counter = 5, phase1_latch = true, phase1_cap_counter = 6,
        OLD_IF_A = 300, OLD_I = 1000, regen_delay_seconds = 0.499,
    })
    local _, ns_full = core.calculateTick(charge_inputs, near_full)
    h.assert_near(core.decode_state(ns_full).regen_delay_seconds, CHARGE_FULL, 1e-9, "charge clamps at 0.5s")

    -- Discharge rate: phase1 never latched -> brake_current_high_phase1 is
    -- always false (needs phase1_cap_charged), guaranteeing disabled.
    local discharge_state = core.encode_state({
        position_counter = 5, phase1_latch = false, regen_delay_seconds = 0.3,
    })
    local idle_inputs = core.encode_stateless_in({
        speed = 5, catenary_voltage_sw = 1500, notch_pos = 0, forward_signal = true,
    })
    local expected = 0.3
    for tick = 1, 10 do
        local _, ns = core.calculateTick(idle_inputs, discharge_state)
        discharge_state = ns
        local st = core.decode_state(discharge_state)
        expected = math.max(expected - DISCHARGE_RATE, 0)
        h.assert_near(st.regen_delay_seconds, expected, 1e-9, "discharges at -1/1200s per tick, tick " .. tick)
    end

    -- Discharge boundary: floors at 0, never goes negative.
    local near_empty = core.encode_state({
        position_counter = 5, phase1_latch = false, regen_delay_seconds = 0,
    })
    local _, ns_empty = core.calculateTick(idle_inputs, near_empty)
    h.assert_near(core.decode_state(ns_empty).regen_delay_seconds, 0, 1e-9, "discharge floors at 0")

    -- Charged threshold epsilon guard: 30 additions of 1/60 land at
    -- 0.49999999999999994 (float drift), one tick short of a bare ">=0.5".
    -- regen_delay_charged (src/chuso1800_core.lua) must still treat this as
    -- charged, or the charge would take 31 ticks instead of the intended 30
    -- (0.5s at 60 ticks/sec). Constructed directly via encode_state rather
    -- than by ticking calculateTick 30 times, since brake_current_high_phase1
    -- (the actual charge-enable signal) stops holding true well before tick
    -- 30 in this entangled-physics setup (see the +1/60s/tick loop above,
    -- which only asserts over the first 10 ticks for that reason).
    local float_drift_seconds = 0
    for _ = 1, 30 do
        float_drift_seconds = math.min(float_drift_seconds + TICK_SECONDS, CHARGE_FULL)
    end
    h.assert_true(float_drift_seconds < CHARGE_FULL, "sanity: float drift really does land short of 0.5")

    -- Observable effect of "charged": regen_bc_enable (-> regen_bc_smooth
    -- ramping toward 0 at +0.02/tick) vs. not-charged (-> ramping toward a
    -- very negative regen_bc_target at -0.1/tick, forced via sap_raw=36).
    -- regen_flag=true makes regen_bc_enable depend entirely on
    -- regen_delay_charged's epsilon guard.
    local near_boundary = core.encode_state({
        position_counter = 5, phase1_latch = false, regen_delay_seconds = float_drift_seconds,
        regen_bc_smooth = -0.5,
    })
    local drift_inputs = core.encode_stateless_in({
        speed = 5, catenary_voltage_sw = 1500, notch_pos = 0, forward_signal = true,
        regen_flag = true, sap_raw = 36,
    })
    local _, ns_drift = core.calculateTick(drift_inputs, near_boundary)
    h.assert_near(core.decode_state(ns_drift).regen_bc_smooth, -0.5 + 0.02, 1e-9,
        "epsilon guard treats the float-drifted value as charged (regen_bc_smooth ramps toward 0, not toward regen_bc_target)")
end
