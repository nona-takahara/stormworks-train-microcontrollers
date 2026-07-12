-- SPEC.md §3.6/§3.8: bc_target_smooth is a 0.2/0.8 EMA of physics `accel`;
-- regen_bc_smooth is an asymmetric ramp (+0.02/tick rising, -0.1/tick
-- falling), clamped <= 0.


return function(h)
    -- bc_target_smooth EMA: cross-check against physics_tick called with the
    -- exact same parameters calculateTick uses internally.
    local state = h.encode_state({
        position_counter = 3, phase1_latch = true, phase1_cap_counter = 6,
        OLD_I = 50, OLD_IF_A = 150, OLD_PHI = 0.03, bc_target_smooth = -1,
    })
    -- sap_pressure_sw=1 makes regen_bc_target=0 (matching the manual
    -- physics_tick cross-check call below), equivalent to the former
    -- default sap_raw=0/eb_signal=false.
    local stateless_in = h.encode_stateless_in({
        speed = 5, catenary_voltage_sw = 1500, notch_pos = 4, direction = 1,
        brake_pressure_sw = 5, sap_pressure_sw = 1,
    })

    for tick = 1, 5 do
        local before = h.decode_state(state)
        local phys = h.physics_tick({
            speed = 5, vl = 1500, position_counter = before.position_counter,
            direction = 1, notch_eff = 4,
            phase1 = before.phase1_latch, phase2 = before.phase2_latch, regen = before.regen_latch,
            notch_ge1 = true, low_bc_with_regen_flag = false,
            regen_bc_smooth_seed = before.regen_bc_smooth, regen_bc_target = 0,
            OLD_I = before.OLD_I, OLD_IF_A = before.OLD_IF_A, OLD_PHI = before.OLD_PHI,
        })
        local expected = phys.accel * 0.2 + before.bc_target_smooth * 0.8

        local stateless_out, new_state = core_tick(stateless_in, state)
        state = new_state
        local after = h.decode_state(state)

        h.assert_near(after.bc_target_smooth, expected, 1e-9, "bc_target_smooth EMA tick " .. tick)
        h.assert_near(stateless_out[3], expected, 1e-9, "bc_target_smooth exposed as stateless_out[3] tick " .. tick)
    end

    -- regen_bc_smooth rising ramp (+0.02/tick): regen_flag=false forces
    -- regen_bc_enable=true, i.e. regen_bc_sw=0, so the smoother climbs
    -- toward 0 from below at the +0.02 rate.
    local rise_state = zero_state()
    local rise_inputs = h.encode_stateless_in({ direction = 1, brake_pressure_sw = 5 })
    local prev = 0
    for tick = 1, 5 do
        local _, ns = core_tick(rise_inputs, rise_state)
        rise_state = ns
        local st = h.decode_state(rise_state)
        h.assert_near(st.regen_bc_smooth, math.min(prev + 0.02, 0), 1e-9, "regen_bc_smooth rises at +0.02/tick, tick " .. tick)
        prev = st.regen_bc_smooth
    end

    -- regen_bc_smooth falling ramp (-0.1/tick): regen_flag=true and a very
    -- negative regen_bc_target (sap_pressure_sw=5.5, equivalent to the
    -- former sap_raw=36 max) forces regen_bc_sw to sit far below old-0.1,
    -- pinning the fall rate at exactly -0.1/tick.
    local fall_state = zero_state()
    local fall_inputs = h.encode_stateless_in({
        direction = 1, brake_pressure_sw = 5, regen_flag = true, sap_pressure_sw = 5.5,
    })
    local prev_fall = 0
    for tick = 1, 5 do
        local _, ns = core_tick(fall_inputs, fall_state)
        fall_state = ns
        local st = h.decode_state(fall_state)
        h.assert_near(st.regen_bc_smooth, prev_fall - 0.1, 1e-9, "regen_bc_smooth falls at -0.1/tick, tick " .. tick)
        prev_fall = st.regen_bc_smooth
    end
end
