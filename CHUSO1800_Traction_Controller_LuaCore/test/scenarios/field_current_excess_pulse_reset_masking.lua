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
-- shrinkage as the old SPEC.md's H7 corner (see h7_cam_overshoot_homing.lua):
-- SPEC.md permits shorter transients as long as the converged state matches,
-- and it does here -- both the literal gate net and this module land on
-- Series=false/Parallel=false (full neutral) a handful of ticks later.
--
-- The masking is DB-auto-dependent: with regen_flag ON, `phase_reset_cond`
-- drops its pulse-derived term entirely, so nothing masks the SET and Series
-- visibly engages (and stays engaged) exactly as the gate net does.
--
-- **DESIGN_LOG.md #28 update (superseded by #29, see below)**: #28 initially
-- gated the regen_flag=false masking behind a `near_stop` speed check, on the
-- theory that iF_a's unbounded upward drift during coasting made it fire too
-- readily and that a clean Parallel->Series demotion (matching the
-- regen_flag=true behavior) was the correct response at speed regardless of
-- regen_flag.
--
-- **DESIGN_LOG.md #29 correction**: that theory was wrong. Per SPEC.md §7.5
-- ("このパルスは並列から直列への切替、直列の解除、またはDB自動OFF時の接続
-- 解除に使用される" -- this pulse is used to switch Parallel->Series, release
-- Series, or disconnect entirely when DB-auto is OFF) and explicit correction
-- from the PR author, the masking-to-neutral behavior for regen_flag=false is
-- the *intended* one regardless of speed -- entering or remaining in series
-- field control while DB-auto (dynamic-brake-auto) is OFF risks an
-- unintended-acceleration surprise for the driver, so the controller must
-- disconnect from the catenary instead of quietly demoting to Series. The fix
-- reverts #28's `near_stop` gate on `phase_reset_cond`'s pulse term (masking
-- is unconditional again, matching the original gate-net-derived behavior)
-- and instead gates `phase1_set`'s pulse-driven Parallel->Series term with
-- `regen_flag` directly, so the demotion path structurally cannot fire at all
-- while DB-auto is OFF -- masking is therefore the only possible outcome,
-- not a race resolved by reset-priority.
--
-- This test locks down all three branches so a future refactor of
-- `phase_state_machine` cannot silently reorder these terms and change which
-- one wins.

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
    -- direction/brake are just "not tripping EB" filler values.
    local function make_inputs(regen_flag, speed)
        return h.encode_stateless_in({
            speed = speed, catenary_voltage_sw = 1500, notch_pos = 0,
            direction = 1, brake_pressure_sw = 5, regen_flag = regen_flag,
        })
    end

    -- --- DB auto OFF, genuinely near a stop (speed < STUCK_RELEASE_SPEED_
    -- THRESHOLD): SET is still masked by the same-tick reset, never
    -- observable -- this is the near-stop case #23's original bug report was
    -- actually about, and the #28 speed gate deliberately preserves it. ---
    do
        local state = make_state()
        local inputs = make_inputs(false, 1)
        local saw_phase1_on = false
        for tick = 1, 40 do
            local stateless_out, new_state = core_tick(inputs, state)
            state = new_state
            local st = h.decode_state(state)
            if st.phase1_latch then saw_phase1_on = true end
        end
        h.assert_false(saw_phase1_on, "regen_flag=false, near stop: Series SET is masked, never visibly latches")
        local st = h.decode_state(state)
        h.assert_false(st.phase1_latch, "converges to neutral (phase1)")
        h.assert_false(st.phase2_latch, "converges to neutral (phase2)")
    end

    -- --- DESIGN_LOG.md #29: DB auto OFF, coasting at ordinary speed (above
    -- STUCK_RELEASE_SPEED_THRESHOLD) -- must ALSO mask to full neutral, same
    -- as the near-stop case. `phase1_set`'s pulse term now requires
    -- `regen_flag`, so there is structurally no path to a Series SET while
    -- DB-auto is OFF, at any speed. ---
    do
        local state = make_state()
        local inputs = make_inputs(false, 5)
        local saw_phase1_on = false
        for tick = 1, 40 do
            local stateless_out, new_state = core_tick(inputs, state)
            state = new_state
            local st = h.decode_state(state)
            if st.phase1_latch then saw_phase1_on = true end
        end
        h.assert_false(saw_phase1_on,
            "DESIGN_LOG.md #29: regen_flag=false at speed must also mask to neutral, not demote to Series")
        local st = h.decode_state(state)
        h.assert_false(st.phase1_latch, "converges to neutral (phase1)")
        h.assert_false(st.phase2_latch, "converges to neutral (phase2)")
    end

    -- --- DB auto ON: phase_reset_cond drops the pulse term regardless of
    -- speed, SET holds ---
    do
        local state = make_state()
        local inputs = make_inputs(true, 5)
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
