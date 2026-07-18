-- Field-current-excess transition policy (SPEC.md §7.5, DESIGN_LOG.md #22/#28/#29).
-- DB-auto OFF must disconnect to neutral at every speed without a visible Series SET.
-- DB-auto ON must demote Parallel to Series. The test locks down both branches.

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
