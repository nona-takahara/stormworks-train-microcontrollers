-- SPEC.md §3.8: regen_delay was CAPACITOR(charge_time=0.5s, discharge_time=10s)
-- in main.sw-net. This module models it as a packed integer level 0-600:
-- +20/tick while enabled (600/30 ticks = 0.5s to full), -1/tick while
-- disabled (600/600 ticks = 10s to empty). Both rates are exact integers by
-- construction (see the REGEN_DELAY_* constants in src/chuso1800_core.lua),
-- so unlike a seconds-based float accumulator, no epsilon guard is needed
-- anywhere -- "charged" is a plain `level >= 600`.


return function(h)
    -- Charge rate: phase1 latched + sustained brake demand (regen_flag +
    -- bc_target_below_min) reliably drives brake_current_high_phase1 true
    -- for the first several ticks (until the field-current control law
    -- settles below the 300A threshold on its own -- verified empirically,
    -- so this test only asserts the +20/tick behavior over a window where
    -- it demonstrably holds, not indefinitely).
    local charge_state = h.encode_state({
        position_counter = 5, phase1_latch = true, phase1_cap_counter = 6,
        OLD_IF_A = 300, OLD_I = 1000,
    })
    local charge_inputs = h.encode_stateless_in({
        speed = 5, catenary_voltage_sw = 1500, notch_pos = 0, direction = 1, brake_pressure_sw = 5,
        regen_flag = true, sap_pressure_sw = 2.25, -- equivalent to the former sap_raw=10 (ECB, eb_signal=false)
    })
    for tick = 1, 10 do
        local _, ns = core_tick(charge_inputs, charge_state)
        charge_state = ns
        local st = h.decode_state(charge_state)
        h.assert_eq(st.regen_delay_level, tick * 20, "charges at +20/tick, tick " .. tick)
    end

    -- Charge boundary: caps at 600, never overshoots. 30 ticks of continuous
    -- charging (0.5s at 60 ticks/sec) must land exactly on 600 -- integer
    -- arithmetic, so no epsilon needed here (unlike the float-seconds
    -- design this replaced, where 30 additions of 1/60 land one float-ULP
    -- short of 0.5).
    local near_full = h.encode_state({
        position_counter = 5, phase1_latch = true, phase1_cap_counter = 6,
        OLD_IF_A = 300, OLD_I = 1000, regen_delay_level = 580,
    })
    local _, ns_full = core_tick(charge_inputs, near_full)
    h.assert_eq(h.decode_state(ns_full).regen_delay_level, 600, "charge clamps at 600")

    -- Discharge rate: phase1 never latched -> brake_current_high_phase1 is
    -- always false (needs phase1_cap_charged), guaranteeing disabled.
    local discharge_state = h.encode_state({
        position_counter = 5, phase1_latch = false, regen_delay_level = 100,
    })
    local idle_inputs = h.encode_stateless_in({
        speed = 5, catenary_voltage_sw = 1500, notch_pos = 0, direction = 1, brake_pressure_sw = 5,
    })
    for tick = 1, 10 do
        local _, ns = core_tick(idle_inputs, discharge_state)
        discharge_state = ns
        local st = h.decode_state(discharge_state)
        h.assert_eq(st.regen_delay_level, 100 - tick, "discharges at -1/tick, tick " .. tick)
    end

    -- Discharge boundary: floors at 0, never goes negative.
    local near_empty = h.encode_state({
        position_counter = 5, phase1_latch = false, regen_delay_level = 0,
    })
    local _, ns_empty = core_tick(idle_inputs, near_empty)
    h.assert_eq(h.decode_state(ns_empty).regen_delay_level, 0, "discharge floors at 0")

    -- Charged/"active" is hysteretic, matching a real Stormworks CAPACITOR:
    -- once it reaches full charge and switches ON, it stays ON for the whole
    -- discharge ramp, only switching OFF once it reaches fully empty ("Off
    -- で dt 秒かけて Off" -- see e.g. NITS_Simple_Bridge/SPEC.md's use of
    -- CAPACITOR(0, 0.1) as a pulse stretcher, which only works this way).
    -- `regen_delay_active` is the extra state bit that tracks this ON/OFF
    -- latch; `regen_delay_level` alone is ambiguous (599 could be "still
    -- charging up, not yet ON" or "discharging from full, still ON").
    -- Observable via regen_bc_enable's effect on regen_bc_smooth (enabled ->
    -- ramps toward 0 at +0.02/tick; disabled, with regen_flag=true and a very
    -- negative regen_bc_target via sap_pressure_sw=5.5 (equivalent to the
    -- former sap_raw=36) -> ramps toward it at -0.1/tick).
    local drift_inputs = h.encode_stateless_in({
        speed = 5, catenary_voltage_sw = 1500, notch_pos = 0, direction = 1, brake_pressure_sw = 5,
        regen_flag = true, sap_pressure_sw = 5.5,
    })

    local charged_state = h.encode_state({
        position_counter = 5, phase1_latch = false, regen_delay_level = 600, regen_delay_active = true, regen_bc_smooth = -0.5,
    })
    local _, ns_charged = core_tick(drift_inputs, charged_state)
    h.assert_near(h.decode_state(ns_charged).regen_bc_smooth, -0.5 + 0.02, 1e-9,
        "level 600, active=true: enabled (regen_bc_smooth ramps toward 0)")
    h.assert_true(h.decode_state(ns_charged).regen_delay_active, "level 600, active=true stays active as it starts discharging")

    -- The bug this guards against: previously "charged" was computed as a
    -- pure function of level (level >= 600), so the very first discharge
    -- tick (600 -> 599) would immediately read as "not charged" and drop the
    -- regen inhibit -- instead of holding it for the full 10s discharge.
    local still_active_state = h.encode_state({
        position_counter = 5, phase1_latch = false, regen_delay_level = 599, regen_delay_active = true, regen_bc_smooth = -0.5,
    })
    local _, ns_still_active = core_tick(drift_inputs, still_active_state)
    h.assert_near(h.decode_state(ns_still_active).regen_bc_smooth, -0.5 + 0.02, 1e-9,
        "level 599 but still active=true (mid-discharge): still enabled, hysteresis holds")
    h.assert_true(h.decode_state(ns_still_active).regen_delay_active, "active stays true while level > 0")

    -- Never having reached full charge (active=false) at the same level 599
    -- must NOT be enabled -- charging up requires reaching the full 600.
    local never_charged_state = h.encode_state({
        position_counter = 5, phase1_latch = false, regen_delay_level = 599, regen_delay_active = false, regen_bc_smooth = -0.5,
    })
    local _, ns_never_charged = core_tick(drift_inputs, never_charged_state)
    h.assert_near(h.decode_state(ns_never_charged).regen_bc_smooth, -0.5 - 0.1, 1e-9,
        "level 599, active=false (never reached full charge): disabled (regen_bc_smooth ramps toward regen_bc_target)")

    -- Active only switches back off once the level actually reaches 0.
    local about_to_empty_state = h.encode_state({
        position_counter = 5, phase1_latch = false, regen_delay_level = 1, regen_delay_active = true, regen_bc_smooth = -0.5,
    })
    local _, ns_about_to_empty = core_tick(drift_inputs, about_to_empty_state)
    h.assert_eq(h.decode_state(ns_about_to_empty).regen_delay_level, 0, "level reaches exactly 0 this tick")
    h.assert_false(h.decode_state(ns_about_to_empty).regen_delay_active, "active switches off only once level reaches 0")
end
