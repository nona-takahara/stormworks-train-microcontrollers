-- Regression for the low-speed Parallel+field-control lockup (DESIGN_LOG.md #23/#26/#27).
-- At cam 0, a fully idle near-stop vehicle must release Parallel without setting Series;
-- after release, re-power must restart through Series resistance. Normal high-speed coasting,
-- active power, and active brake demand must preserve the accumulated state.

return function(h)
    local function stuck_state()
        return h.encode_state({
            position_counter = 0,
            phase1_latch = false,
            phase2_latch = true,
            regen_latch = true,
            OLD_I = 0,
            OLD_IF_A = 20, -- decayed, well under the 300A field_current_excess threshold
            OLD_PHI = 0,
        })
    end

    -- --- idle (no notch, no brake demand), genuinely near a stop (speed below
    -- STUCK_RELEASE_SPEED_THRESHOLD): both latches release once current decays
    -- near zero. At near-zero speed with Parallel fully shorted (PR[1]=0), the
    -- residual field current (OLD_IF_A=20 seed) initially drives several
    -- thousand amps (the same "confirmed-bad outcome" this test's own header
    -- describes) -- neutral_cond only becomes true, and release only fires,
    -- once that decays under the 50A near-zero threshold (~170 ticks / ~2.9s
    -- here), which is why this loop runs longer than the 150-tick budget used
    -- elsewhere in this file. ---
    do
        local state = stuck_state()
        local idle_inputs = h.encode_stateless_in({
            speed = 1, catenary_voltage_sw = 1500, notch_pos = 0,
            direction = 1, brake_pressure_sw = 5, sap_pressure_sw = 5,
        })
        local released_tick = nil
        for tick = 1, 300 do
            local stateless_out, new_state = core_tick(idle_inputs, state)
            state = new_state
            local st = h.decode_state(state)
            if (not st.phase2_latch) and (not st.regen_latch) and not released_tick then
                released_tick = tick
            end
        end
        h.assert_true(released_tick ~= nil, "stuck Parallel+field-control releases back to neutral while idle")
        local st = h.decode_state(state)
        h.assert_false(st.phase1_latch, "released state: Series stays off too (no bogus SET)")
        h.assert_eq(st.position_counter, 0, "cam untouched by the release itself")
    end

    -- --- re-applying power from the released state engages Series (resistance
    -- in circuit), not a bare reconnection at Parallel's fully-shorted step ---
    do
        local state = stuck_state()
        local idle_inputs = h.encode_stateless_in({
            speed = 1, catenary_voltage_sw = 1500, notch_pos = 0,
            direction = 1, brake_pressure_sw = 5, sap_pressure_sw = 5,
        })
        for tick = 1, 300 do
            local stateless_out, new_state = core_tick(idle_inputs, state)
            state = new_state
        end

        local power_inputs = h.encode_stateless_in({
            speed = 0.5, catenary_voltage_sw = 1500, notch_pos = 1,
            direction = 1, brake_pressure_sw = 5, sap_pressure_sw = 5,
        })
        local saw_bogus_parallel_reconnect = false
        for tick = 1, 10 do
            local stateless_out, new_state = core_tick(power_inputs, state)
            state = new_state
            local st = h.decode_state(state)
            -- The confirmed-bad outcome: still Parallel-only (no Series) while
            -- current spikes into the thousands of amps at near-zero speed.
            if (not st.phase1_latch) and st.phase2_latch and math.abs(stateless_out[1]) > 1000 then
                saw_bogus_parallel_reconnect = true
            end
        end
        h.assert_false(saw_bogus_parallel_reconnect,
            "restart engages Series (resistance-limited), not a bare Parallel reconnect at zero resistance")
        local st = h.decode_state(state)
        h.assert_true(st.phase1_latch, "Series is the one that (re)engages on restart")
    end

    -- --- negative case: must NOT release while notch is still applied (mid-power
    -- at the top of the ladder, e.g. spec_v2_corrections' cam==0 field-control
    -- steady state, is unaffected) ---
    do
        local state = stuck_state()
        local powering_inputs = h.encode_stateless_in({
            speed = 15, catenary_voltage_sw = 1500, notch_pos = 4,
            direction = 1, brake_pressure_sw = 5, sap_pressure_sw = 5,
        })
        for tick = 1, 150 do
            local stateless_out, new_state = core_tick(powering_inputs, state)
            state = new_state
            local st = h.decode_state(state)
            h.assert_true(st.phase2_latch, "stays latched while notch is actively applied, tick " .. tick)
            h.assert_true(st.regen_latch, "field-control stays latched while notch is actively applied, tick " .. tick)
        end
    end

    -- --- DESIGN_LOG.md #26 regression: coasting with DB-auto (regen_flag) ON,
    -- no actual brake demand, must NOT spuriously SET Series via
    -- `stuck_at_top_idle` leaking into `phase1_set` (the confirmed-in-game
    -- "cam creeps forward with notch off" bug). Deliberately run at a coasting
    -- speed (not near a stop): at near-stop speed this module's own
    -- fully-shorted-Parallel physics makes armature current genuinely run
    -- away (see DESIGN_LOG.md #28), which legitimately trips the *separate*,
    -- pre-existing `field_current_excess_pulse` -> `phase1_set` demotion path
    -- (SPEC.md §7.5) -- a real, wanted Series engagement, not the #26 bug.
    -- Testing at a coasting speed isolates the actual claim under test:
    -- `stuck_at_top_idle` itself (structurally decoupled from `phase1_set`
    -- since #26) must never be the thing that sets Series. ---
    do
        local state = stuck_state()
        local idle_db_auto_inputs = h.encode_stateless_in({
            speed = 15, catenary_voltage_sw = 1500, notch_pos = 0,
            direction = 1, brake_pressure_sw = 5, sap_pressure_sw = 1.0, -- no demand
            regen_flag = true, -- DB-auto left on, a common standing driving mode
        })
        local saw_bogus_series_set = false
        for tick = 1, 300 do
            local stateless_out, new_state = core_tick(idle_db_auto_inputs, state)
            state = new_state
            local st = h.decode_state(state)
            if st.phase1_latch then saw_bogus_series_set = true end
            h.assert_true(st.phase2_latch, "DESIGN_LOG.md #26/#27: stays latched while coasting at speed, tick " .. tick)
            h.assert_true(st.regen_latch, "DESIGN_LOG.md #26/#27: field-control stays latched while coasting at speed, tick " .. tick)
        end
        h.assert_false(saw_bogus_series_set,
            "DESIGN_LOG.md #26: coasting release path under DB-auto must never SET Series")
        local st = h.decode_state(state)
        h.assert_eq(st.position_counter, 0, "cam untouched (no creeping forward) under DB-auto coasting")
    end

    -- --- DESIGN_LOG.md #27 regression: coasting at highway speed (notch off,
    -- no brake demand, current settled to 0A by field-control -- the CORRECT
    -- behavior above ~40km/h) must NOT release Parallel+field-control. Only a
    -- genuine near-stop (speed < STUCK_RELEASE_SPEED_THRESHOLD) may release.
    -- Confirmed-in-game symptom this locks down: a brief coast at speed
    -- silently discards regen-braking readiness and forces a full ladder
    -- re-climb on the next re-power. ---
    do
        local state = stuck_state()
        local highway_coast_inputs = h.encode_stateless_in({
            speed = 60 / 3.6, catenary_voltage_sw = 1500, notch_pos = 0,
            direction = 1, brake_pressure_sw = 5, sap_pressure_sw = 1.0, -- no demand
        })
        for tick = 1, 150 do
            local stateless_out, new_state = core_tick(highway_coast_inputs, state)
            state = new_state
            local st = h.decode_state(state)
            h.assert_true(st.phase2_latch,
                "DESIGN_LOG.md #27: Parallel must stay latched while coasting at speed, tick " .. tick)
            h.assert_true(st.regen_latch,
                "DESIGN_LOG.md #27: field-control must stay latched while coasting at speed, tick " .. tick)
        end
    end

    -- --- negative case: must NOT release while there is an active brake demand.
    -- sap_pressure_sw=5, regen_flag=true -> regen_bc_target = -floor(4*2)/7.2
    -- ~= -1.11, well under BC_TARGET_MIN(-0.05), so low_bc_with_regen_flag
    -- is true throughout (brake_demand() in src/chuso1800_core.lua). ---
    do
        local state = stuck_state()
        local braking_inputs = h.encode_stateless_in({
            speed = 15, catenary_voltage_sw = 1500, notch_pos = 0,
            direction = 1, brake_pressure_sw = 5, sap_pressure_sw = 5, regen_flag = true,
        })
        for tick = 1, 150 do
            local stateless_out, new_state = core_tick(braking_inputs, state)
            state = new_state
            local st = h.decode_state(state)
            h.assert_true(st.regen_latch, "field-control stays latched under an active brake demand, tick " .. tick)
        end
    end
end
