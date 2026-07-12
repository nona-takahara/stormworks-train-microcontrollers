-- SPEC.md §4.5/H4: EB (eb_condition) must drive the state machine cleanly to
-- Idle (phase1=phase2=regen=false), zero the electrical outputs except bcT
-- (which takes over regen_current), and freeze the cam.


return function(h)
    -- Start mid-Series with some plausible physics quasi-state already warmed up.
    local state = h.encode_state({
        position_counter = 5,
        phase1_latch = true,
        phase2_latch = false,
        regen_latch = false,
        OLD_I = 150,
        OLD_IF_A = 150,
        OLD_PHI = 0.02,
    })

    -- controller_stop=true triggers eb_condition; sap_pressure_sw=2.25
    -- (equivalent to the former sap_raw=10, ECB, eb_signal=false) gives a
    -- nonzero regen_bc_target so bcT's EB substitution is actually
    -- distinguishable from a coincidental zero. direction=1/brake_pressure_sw=5
    -- keep the OTHER two EB triggers inactive, isolating this test to
    -- controller_stop specifically.
    local ebstateless = h.encode_stateless_in({
        speed = 5,
        catenary_voltage_sw = 1500,
        sap_pressure_sw = 2.25,
        brake_pressure_sw = 5,
        notch_pos = 3,
        direction = 1,
        controller_stop = true,
    })

    local stateless_out, new_state = core_tick(ebstateless, state)
    local st = h.decode_state(new_state)
    local out = h.decode_stateless_out(stateless_out)

    h.assert_false(st.phase1_latch, "phase1 resets on the EB tick itself")
    h.assert_false(st.phase2_latch, "phase2 resets on the EB tick itself")
    h.assert_false(st.regen_latch, "regen resets on the EB tick itself")
    h.assert_eq(st.position_counter, 5, "cam frozen during EB")
    h.assert_near(out.motor_current, 0, 1e-9, "motor_current zeroed under EB")
    h.assert_near(out.W, 0, 1e-9, "W zeroed under EB")
    h.assert_near(out.bcT, 0.2777777778, 1e-6, "bcT takes over regen_current under EB")

    -- Hold EB for several more ticks: must stay converged (no oscillation),
    -- cam must stay frozen.
    state = new_state
    for tick = 1, 50 do
        local stateless_out2, new_state2 = core_tick(ebstateless, state)
        state = new_state2
        local st2 = h.decode_state(state)
        h.assert_false(st2.phase1_latch, "phase1 stays off tick " .. tick)
        h.assert_false(st2.phase2_latch, "phase2 stays off tick " .. tick)
        h.assert_false(st2.regen_latch, "regen stays off tick " .. tick)
        h.assert_eq(st2.position_counter, 5, "cam stays frozen tick " .. tick)
    end
end
