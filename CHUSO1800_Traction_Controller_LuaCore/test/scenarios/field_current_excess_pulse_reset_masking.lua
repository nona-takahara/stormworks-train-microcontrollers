-- SPEC.md §7.5: a field-current-excess periodic pulse while Parallel is
-- latched is supposed to demote Parallel->Series (SET traction_phase1,
-- RESET traction_phase2). Cross-checked against tools/sw-net-sim running
-- the literal (原稿) gate network for CHUSO1800_Traction_Controller/main.sw-net:
-- when DB auto (regen_flag) is OFF, the literal gate net shows a brief
-- (1-2 tick) Series SET before phase_reset_cond also fires and resets BOTH
-- latches back to neutral -- Series is visibly, if fleetingly, engaged.
--
-- This module never shows that transient. `phase1_reset`'s `phase_reset_cond`
-- term already folds in `field_current_excess_pulse and (not regen_flag)`
-- (see `phase_state_machine`'s `phase_reset_cond`), and it is evaluated in
-- the SAME `calculateTick` as `phase1_set`'s `field_current_excess_pulse and
-- phase2_latch` term -- both read the identical pulse value this tick, so
-- `sr_latch`'s reset-priority (`if reset then return false`) masks the SET
-- before it is ever observable. In the literal gate net this collision does
-- NOT happen on the same tick: `traction_phase1_set`'s pulse input is one
-- gate-hop from the pulse, but `traction_phase1_reset`'s pulse-derived term
-- is two hops away (`field_current_excess_pulse -> regen_pulse_regen_flag_off
-- -> phase_reset_cond -> traction_phase1_reset`), so the 1-tick-per-gate
-- model lets the SET surface for one tick before the (now-current)
-- phase_reset_cond term catches up and resets both latches.
--
-- This is the same category of accepted "combinational compression"
-- shrinkage as H7 (see h7_cam_overshoot_homing.lua): SPEC.md §0.2 permits
-- shorter transients as long as the converged state matches, and it does
-- here -- both the literal gate net and this module land on
-- Series=false/Parallel=false (full neutral) a handful of ticks later.
--
-- The masking is DB-auto-dependent: with regen_flag ON, `phase_reset_cond`
-- drops its pulse-derived term entirely, so nothing masks the SET and
-- Series visibly engages (and stays engaged) exactly as the gate net does.
-- This test locks down both branches so a future refactor of
-- `phase_state_machine` cannot silently reorder these terms and change
-- which one wins.

return function(h)
    local function make_state()
        return h.encode_state({
            position_counter = 17,
            phase1_latch = false,
            phase2_latch = true,
            phase2_cap_counter = 6,
            current_below_limit_cap_counter = 6,
            OLD_I = 0,
            OLD_IF_A = 350, -- field current above the 300A threshold
            OLD_PHI = 0.05,
        })
    end

    -- notch dropped to 0 (field_current_excess_cond needs notch_ge1 false);
    -- speed/direction/brake are just "not tripping EB" filler values.
    local function make_inputs(regen_flag)
        return h.encode_stateless_in({
            speed = 5, catenary_voltage_sw = 1500, notch_pos = 0,
            direction = 1, brake_pressure_sw = 5, regen_flag = regen_flag,
        })
    end

    -- --- DB auto OFF: SET is masked by the same-tick reset, never observable ---
    do
        local state = make_state()
        local inputs = make_inputs(false)
        local saw_phase1_on = false
        for tick = 1, 40 do
            local stateless_out, new_state = core_tick(inputs, state)
            state = new_state
            local st = h.decode_state(state)
            if st.phase1_latch then saw_phase1_on = true end
        end
        h.assert_false(saw_phase1_on, "regen_flag=false: Series SET is masked, never visibly latches")
        local st = h.decode_state(state)
        h.assert_false(st.phase1_latch, "converges to neutral (phase1)")
        h.assert_false(st.phase2_latch, "converges to neutral (phase2)")
    end

    -- --- DB auto ON: phase_reset_cond drops the pulse term, SET holds ---
    do
        local state = make_state()
        local inputs = make_inputs(true)
        local set_tick = nil
        for tick = 1, 35 do
            local stateless_out, new_state = core_tick(inputs, state)
            state = new_state
            local st = h.decode_state(state)
            if st.phase1_latch and not set_tick then set_tick = tick end
        end
        h.assert_true(set_tick ~= nil, "regen_flag=true: Series SET becomes visible")
        local st = h.decode_state(state)
        h.assert_true(st.phase1_latch, "Series stays latched (not masked) once set")
        h.assert_false(st.phase2_latch, "Parallel has been reset by the demotion")
    end
end
