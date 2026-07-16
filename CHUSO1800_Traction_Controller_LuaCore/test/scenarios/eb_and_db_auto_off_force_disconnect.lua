-- DESIGN_LOG.md #29 (PR #7 review comment from the repo owner, two safety
-- requirements):
--
-- 1. Receiving emergency braking (EB, `eb_condition`) must unconditionally
--    force ALL THREE latches (series/phase1, parallel/phase2, field-control/
--    regen) off, regardless of speed or how the state was reached. A literal
--    reading that only drops the field-control flag would leave Parallel
--    latched; re-notching after EB clears would then reconnect straight to
--    Parallel's current (low-resistance-to-zero) cam step instead of
--    restarting through Series -- the same "reconnect at zero resistance,
--    current spikes" danger #23 was originally about. `eb_trip_converges_
--    idle.lua` already covers the ordinary EB case, but starts from a state
--    where `regen_latch` is already false (so `coasting_cond` alone already
--    resolves it); this test specifically starts from the Parallel+field-
--    control "stuck" configuration (`stuck_at_top_of_ladder_recovery.lua`'s
--    `stuck_state()`) at a cruising speed, where nothing but the new
--    unconditional EB override can release it.
--
-- 2. Whenever "DB automatic" (`regen_flag`) is OFF, the vehicle must never
--    remain in series field control (series/phase1 latch AND field-control/
--    regen latch both on) -- entering it is already prevented structurally
--    (the field-current-excess pulse's Parallel->Series SET now requires
--    `regen_flag`, see field_current_excess_pulse_reset_masking.lua), but
--    this test covers the case where DB-auto is switched OFF *while already
--    in* series field control (e.g. entered while DB-auto was ON, then the
--    driver turns it off mid-brake) -- the controller must disconnect from
--    the catenary on the very next tick, not wait for some other condition.
--
-- **Follow-up (still #29)**: a PR reviewer follow-up pointed out that
-- "released on the state-machine tick" is not the same as "output zero on
-- that same tick" -- `physics_tick` always computes the current tick's
-- electrical output from the *previous* tick's latch state (see the file's
-- own "tickモデル" header note), so a naive reading of these two
-- requirements could still leave one tick where the real physical output
-- (`motor_current` / the `elec_W` that feeds the `W` output port directly)
-- reflects the old, still-connected state even though the latches already
-- read as released. Measured directly: without the fix, this showed up as
-- ~49A / a raw (pre-smoothing) acceleration of ~0.24 m/s^2 for exactly one
-- tick during a field-current-excess-triggered disconnect -- over twice the
-- 0.1 m/s^2 bound the reviewer asked for. The fix has `phase_state_machine`
-- also return `output_zero_this_tick` (true exactly when at least one of
-- phase1/phase2 was connected coming in and both are released this same
-- tick), which `core_tick` uses to retroactively zero `motor_current`/
-- `elec_W` for that tick's output -- so every sub-test below also asserts
-- `stateless_out[1]` (motor_current) and `stateless_out[2]` (W) are exactly
-- zero on the disconnect tick itself, not just the latch state.

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
        h.assert_near(stateless_out[2], 0, 1e-9, "EB: W (real physical drive) output is exactly zero on the EB tick itself")

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
        h.assert_near(stateless_out[2], 0, 1e-9, "DB-auto OFF mid series-field-control: W (real physical drive) output is exactly zero immediately")
    end

    -- --- follow-up regression: field-current-excess-triggered disconnect
    -- (DB-auto OFF, Parallel+field-control, cruising, current still
    -- meaningfully nonzero the tick the disconnect is decided) must ALSO
    -- output exactly zero on that same tick, not just release the latches.
    -- This reproduces the ~49A / ~0.24 m/s^2 raw-accel leak found via direct
    -- measurement before the `output_zero_this_tick` fix. ---
    do
        local state = h.encode_state({
            position_counter = 0,
            phase1_latch = false,
            phase2_latch = true,
            regen_latch = true,
            OLD_I = 60,
            OLD_IF_A = 299, -- just under threshold; will cross it and trip the pulse shortly
            OLD_PHI = 0.03,
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
            "field-current-excess disconnect: W (real physical drive) output is exactly zero on the disconnect tick itself, tick " .. tostring(disconnect_tick))
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
