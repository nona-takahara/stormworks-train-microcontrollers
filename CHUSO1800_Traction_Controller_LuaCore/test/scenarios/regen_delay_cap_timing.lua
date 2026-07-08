-- SPEC.md §3.8: regen_delay_cap is CAPACITOR(charge_time=0.5s, discharge_time=10s),
-- modeled here as a 0-600 level with +20/tick while enabled (600/30 ticks =
-- 0.5s to full) and -1/tick while disabled (600/600 ticks = 10s to empty).
-- "Charged" (regen_bc_enable-relevant) means level >= 600.

local core = require("chuso1800_core")

return function(h)
    -- Charge rate: phase1 latched + sustained brake demand (regen_flag +
    -- bc_target_below_min) reliably drives brake_current_high_phase1 true
    -- for the first several ticks (until the field-current control law
    -- settles below the 300A threshold on its own -- verified empirically,
    -- so this test only asserts the +20/tick behavior over a window where
    -- it demonstrably holds, not indefinitely).
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
        h.assert_eq(st.regen_delay_cap_level, tick * 20, "charges at +20/tick, tick " .. tick)
    end

    -- Charge boundary: caps at 600, never overshoots.
    local near_full = core.encode_state({
        position_counter = 5, phase1_latch = true, phase1_cap_counter = 6,
        OLD_IF_A = 300, OLD_I = 1000, regen_delay_cap_level = 590,
    })
    local _, ns_full = core.calculateTick(charge_inputs, near_full)
    h.assert_eq(core.decode_state(ns_full).regen_delay_cap_level, 600, "charge clamps at 600")

    -- Discharge rate: phase1 never latched -> brake_current_high_phase1 is
    -- always false (needs phase1_cap_charged), guaranteeing disabled.
    local discharge_state = core.encode_state({
        position_counter = 5, phase1_latch = false, regen_delay_cap_level = 100,
    })
    local idle_inputs = core.encode_stateless_in({
        speed = 5, catenary_voltage_sw = 1500, notch_pos = 0, forward_signal = true,
    })
    for tick = 1, 10 do
        local _, ns = core.calculateTick(idle_inputs, discharge_state)
        discharge_state = ns
        local st = core.decode_state(discharge_state)
        h.assert_eq(st.regen_delay_cap_level, 100 - tick, "discharges at -1/tick, tick " .. tick)
    end

    -- Discharge boundary: floors at 0, never goes negative.
    local near_empty = core.encode_state({
        position_counter = 5, phase1_latch = false, regen_delay_cap_level = 0,
    })
    local _, ns_empty = core.calculateTick(idle_inputs, near_empty)
    h.assert_eq(core.decode_state(ns_empty).regen_delay_cap_level, 0, "discharge floors at 0")
end
