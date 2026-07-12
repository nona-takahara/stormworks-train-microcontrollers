-- Regression guard for two bugs found by cross-checking chuso1800_core.lua
-- against CHUSO1800_Traction_Controller/SPEC.md (2026-07-12 rewrite) and
-- CHUSO1800_Traction_Controller_main_renamed.sw-net, after the user's
-- ChatGPT-assisted re-verification corrected 6 THRESHOLD nodes from a
-- storm-mcl (0,1) serialization bug to their real (0,0) value. Both bugs
-- predate this PR's main.sw-net work -- chuso1800_core.lua was built
-- against the OLD (pre-correction) SPEC.md's misreading of these same two
-- nodes.
--
-- 1. `cam` output (SPEC.md §6.2): must fire on ANY cam position change
--    (delta ~= 0), not only on the 20->0 ring wraparound. The old code used
--    `not (delta >= 0 and delta <= 1)`, which stayed false for a normal +1
--    advance.
-- 2. `cam_at_zero` / `field_control_cam_ready` (SPEC.md §6.2/§7.1, formerly
--    `notch_fb_ge1`/`regen_available`): real threshold is cam position
--    EXACTLY 0, not the storm-mcl-serialized (0,1) range. This gates both
--    the series-start condition (§7.2 step 1) and field-control-latch entry
--    (§7.1/§7.2 step 5) -- at cam=1 neither must fire, only at cam=0.

return function(h)
    -- cam_pulse fires on a normal +1 advance, not just at wraparound.
    do
        local state = h.encode_state({
            position_counter = 5, phase1_latch = true, phase1_cap_counter = 6,
            current_below_limit_cap_counter = 6, -- already charged, so traction_any_active is true this tick
            traction_advance_counter = 11, -- one short of CAM_ADVANCE_PERIOD_TICKS(12) -> periodic_pulse_step fires this tick
        })
        local inputs = h.encode_stateless_in({
            speed = 20, catenary_voltage_sw = 1500, notch_pos = 2, direction = 1, brake_pressure_sw = 5,
        })
        local stateless_out, state_out = core_tick(inputs, state)
        local st = h.decode_state(state_out)
        local status = h.decode_stateless_out(stateless_out)
        h.assert_eq(st.position_counter, 6, "cam advances by a normal +1 step (5 -> 6)")
        h.assert_true(status.cam_pulse, "cam_pulse fires on a normal +1 advance, not only at wraparound")
    end

    -- cam_pulse stays false while the cam holds position (no advance this tick).
    do
        local state = h.encode_state({ position_counter = 5, current_below_limit_cap_counter = 0 })
        local inputs = h.encode_stateless_in({
            speed = 0, catenary_voltage_sw = 1500, notch_pos = 0, direction = 1, brake_pressure_sw = 5,
        })
        local stateless_out, state_out = core_tick(inputs, state)
        local st = h.decode_state(state_out)
        local status = h.decode_stateless_out(stateless_out)
        h.assert_eq(st.position_counter, 5, "cam holds position when nothing drives it forward")
        h.assert_false(status.cam_pulse, "cam_pulse stays false when the cam does not move")
    end

    -- field-control-latch entry (regen_latch) requires cam EXACTLY 0: at
    -- cam=1, parallel connection must NOT enter field control, even though
    -- the pre-fix code's (0,1) range would have allowed it.
    do
        local state_cam1 = h.encode_state({ position_counter = 1, phase2_latch = true })
        local inputs = h.encode_stateless_in({
            speed = 20, catenary_voltage_sw = 1500, notch_pos = 4, direction = 1, brake_pressure_sw = 5,
        })
        local _, state_out = core_tick(inputs, state_cam1)
        local st = h.decode_state(state_out)
        h.assert_false(st.regen_latch, "field-control latch must NOT enter at cam=1 (real threshold is cam==0 only)")
    end

    -- Same setup at cam=0 (exact) must enter field control.
    do
        local state_cam0 = h.encode_state({ position_counter = 0, phase2_latch = true })
        local inputs = h.encode_stateless_in({
            speed = 20, catenary_voltage_sw = 1500, notch_pos = 4, direction = 1, brake_pressure_sw = 5,
        })
        local _, state_out = core_tick(inputs, state_cam0)
        local st = h.decode_state(state_out)
        h.assert_true(st.regen_latch, "field-control latch enters at cam==0 while parallel is engaged")
    end
end
