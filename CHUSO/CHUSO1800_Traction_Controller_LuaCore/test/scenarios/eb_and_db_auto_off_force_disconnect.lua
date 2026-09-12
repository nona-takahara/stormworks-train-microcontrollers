-- Safety regressions for forced disconnect (SPEC.md §7.7, DESIGN_LOG.md #29).
-- EB and DB-auto OFF during Series+field-control must release all three latches immediately.
-- On that same tick, motor_current, W, and the Momelink-A acceleration output must be zero;
-- this verifies outputs, not merely the resulting latch state.

return function(h)
    -- --- requirement 1: EB forces full disconnect from a stuck Parallel+
    -- field-control state, even well above the near-stop threshold ---
    do
        local state = h.encode_state({
            position_counter = 0,
            phase1_latch = false,
            phase2_latch = true,
            regen_latch = true,
            OLD_I = 0,
            OLD_IF_A = 20,
            OLD_PHI = 0,
            -- nonzero seed so the bc_target_smooth (Momelink-A N2) EMA has
            -- real pre-EB history to (fail to) decay from, matching a
            -- vehicle that was genuinely accelerating right up to the EB trip
            bc_target_smooth = 0.5,
        })
        local eb_inputs = h.encode_stateless_in({
            speed = 20, catenary_voltage_sw = 1500, notch_pos = 0,
            direction = 1, brake_pressure_sw = 2, sap_pressure_sw = 5, -- brake_pressure_sw<4 trips EB
        })
        local stateless_out, new_state = core_tick(eb_inputs, state)
        local st = h.decode_state(new_state)
        h.assert_false(st.phase1_latch, "EB: series/phase1 forced off on the EB tick itself")
        h.assert_false(st.phase2_latch, "EB: parallel/phase2 forced off on the EB tick itself")
        h.assert_false(st.regen_latch, "EB: field-control/regen forced off on the EB tick itself")
        h.assert_near(stateless_out[1], 0, 1e-9, "EB: motor_current output is exactly zero on the EB tick itself")
        h.assert_near(stateless_out[2], 0, 1e-9, "EB: W output is exactly zero on the EB tick itself")
        h.assert_near(stateless_out[3], 0, 1e-9, "EB: bc_target_smooth (Momelink-A N2, real drive signal) is exactly zero on the EB tick itself")

        -- stays released for as long as EB holds, regardless of speed
        state = new_state
        for tick = 1, 60 do
            local so2, ns2 = core_tick(eb_inputs, state)
            state = ns2
            local st2 = h.decode_state(state)
            h.assert_true((not st2.phase1_latch) and (not st2.phase2_latch) and (not st2.regen_latch),
                "EB: stays fully disconnected while EB holds, tick " .. tick)
        end
    end

    -- --- requirement 2: DB-auto turning OFF while already in series field
    -- control forces disconnect on the very next tick, regardless of speed ---
    do
        local state = h.encode_state({
            position_counter = 10,
            phase1_latch = true,
            phase2_latch = false,
            regen_latch = true,
            OLD_I = 5,
            OLD_IF_A = 50,
            OLD_PHI = 0.02,
            bc_target_smooth = 0.5, -- pre-transition accel history, see requirement-1 sub-test
        })
        local db_auto_off_inputs = h.encode_stateless_in({
            speed = 15, catenary_voltage_sw = 1500, notch_pos = 0,
            direction = 1, brake_pressure_sw = 5, sap_pressure_sw = 1.0, -- no brake demand, not EB
            regen_flag = false, -- DB-auto OFF while still in series field control
        })
        local stateless_out, new_state = core_tick(db_auto_off_inputs, state)
        local st = h.decode_state(new_state)
        h.assert_false(st.phase1_latch, "DB-auto OFF mid series-field-control: series/phase1 forced off immediately")
        h.assert_false(st.phase2_latch, "DB-auto OFF mid series-field-control: parallel/phase2 forced off immediately")
        h.assert_false(st.regen_latch, "DB-auto OFF mid series-field-control: field-control/regen forced off immediately")
        h.assert_near(stateless_out[1], 0, 1e-9, "DB-auto OFF mid series-field-control: motor_current output is exactly zero immediately")
        h.assert_near(stateless_out[2], 0, 1e-9, "DB-auto OFF mid series-field-control: W output is exactly zero immediately")
        h.assert_near(stateless_out[3], 0, 1e-9, "DB-auto OFF mid series-field-control: bc_target_smooth (Momelink-A N2, real drive signal) is exactly zero immediately")
    end

    -- --- follow-up regression: field-current-excess-triggered disconnect
    -- (DB-auto OFF, Parallel+field-control, cruising, current still
    -- meaningfully nonzero the tick the disconnect is decided) must ALSO
    -- output exactly zero on that same tick, not just release the latches.
    -- This reproduces the ~49A motor_current / ~0.34 m/s^2 bc_target_smooth
    -- leak found via direct measurement before the fix. ---
    do
        local state = h.encode_state({
            position_counter = 0,
            phase1_latch = false,
            phase2_latch = true,
            regen_latch = true,
            OLD_I = 60,
            OLD_IF_A = 299, -- just under threshold; will cross it and trip the pulse shortly
            OLD_PHI = 0.03,
            bc_target_smooth = 0.4,
        })
        local inputs = h.encode_stateless_in({
            speed = 30 / 3.6, catenary_voltage_sw = 1500, notch_pos = 0,
            direction = 1, brake_pressure_sw = 5, sap_pressure_sw = 1.0,
            regen_flag = false,
        })
        local disconnect_tick, output_at_disconnect = nil, nil
        for tick = 1, 60 do
            local stateless_out, new_state = core_tick(inputs, state)
            state = new_state
            local st = h.decode_state(state)
            if (not st.phase1_latch) and (not st.phase2_latch) and (not st.regen_latch) and not disconnect_tick then
                disconnect_tick = tick
                output_at_disconnect = stateless_out
            end
        end
        h.assert_true(disconnect_tick ~= nil, "the field-current-excess-triggered disconnect does eventually fire")
        h.assert_near(output_at_disconnect[1], 0, 1e-9,
            "field-current-excess disconnect: motor_current output is exactly zero on the disconnect tick itself, tick " .. tostring(disconnect_tick))
        h.assert_near(output_at_disconnect[2], 0, 1e-9,
            "field-current-excess disconnect: W output is exactly zero on the disconnect tick itself, tick " .. tostring(disconnect_tick))
        h.assert_near(output_at_disconnect[3], 0, 1e-9,
            "field-current-excess disconnect: bc_target_smooth (Momelink-A N2, real drive signal) is exactly zero on the disconnect tick itself, tick " .. tostring(disconnect_tick))
    end

    -- --- negative case: DB-auto ON, in series field control -- must NOT
    -- be disconnected (this is the normal regen-braking-in-progress state) ---
    do
        local state = h.encode_state({
            position_counter = 10,
            phase1_latch = true,
            phase2_latch = false,
            regen_latch = true,
            OLD_I = 5,
            OLD_IF_A = 50,
            OLD_PHI = 0.02,
        })
        local db_auto_on_inputs = h.encode_stateless_in({
            speed = 15, catenary_voltage_sw = 1500, notch_pos = 0,
            direction = 1, brake_pressure_sw = 5, sap_pressure_sw = 5,
            regen_flag = true,
        })
        local stateless_out, new_state = core_tick(db_auto_on_inputs, state)
        local st = h.decode_state(new_state)
        h.assert_true(st.phase1_latch, "DB-auto ON: series field control is not disturbed by the #29 fix")
        h.assert_true(st.regen_latch, "DB-auto ON: field-control latch is not disturbed by the #29 fix")
    end
end
