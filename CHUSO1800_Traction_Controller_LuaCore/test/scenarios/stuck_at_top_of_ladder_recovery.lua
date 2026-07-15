-- Real-machine bug (confirmed by the user against actual Stormworks play,
-- and independently reproduced bit-for-bit against tools/sw-net-sim running
-- the literal 原稿 main.sw-net + n409.lua -- see DESIGN_LOG.md #23):
--
-- After a full-power run wraps the cam all the way to position 0 with
-- Parallel(phase2_latch) + field-control(regen_latch) engaged, letting off
-- power (notch->0) never resets those two latches. `coasting_cond`'s reset
-- path requires `not regen_latch`, which can never be true while regen_latch
-- is exactly what's stuck on -- and `field_current_excess_pulse`'s reset
-- path requires field current above 300/400A, which a genuinely idle,
-- fully-decayed vehicle never reaches either. Both latches are permanently
-- parked with the cam sitting on position 0 (`PR[1] == 0`, i.e. Parallel's
-- fully-shorted resistance step).
--
-- Re-applying power from there skips the normal Series restart (which would
-- engage `SR[1] == 7.428` ohms of current-limiting resistance) because
-- `phase1_set`'s `power_with_regen and (not phase2_latch)` term is blocked
-- by phase2_latch still being on. Depending on the residual field current at
-- the moment of restart this produces either of two confirmed-in-game
-- symptoms: a several-thousand-amp current spike at near-zero speed
-- (bypassing the 210A power limit entirely, since there is no resistance
-- left to limit it), or -- at a more moderate starting speed -- current
-- settles to a plausible-looking ~200A that never advances the cam, so the
-- vehicle creeps forward indefinitely on the wrong (weak-field/cruise, not
-- Series/starting) torque curve and never climbs the resistance ladder.
--
-- The fix (src/chuso1800_core.lua's `field_current_excess_block`) folds a
-- new "stuck_at_top_idle" condition into the *existing*
-- `field_current_excess_cond` -> `field_current_excess_pulse` chain (the
-- same debounced pulse `phase_state_machine` already uses for the Parallel
-- -> Series demotion and for the neutral-side reset), rather than adding a
-- parallel mechanism: cam at 0, Parallel+field-control latched but Series
-- not, no notch/brake demand, and current settled near zero. After the same
-- 0.5s debounce this reuses to demote Parallel on genuine field-current
-- excess, both latches release back to neutral, so the next power
-- application goes through the normal Series-with-resistance restart path.

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

    -- --- idle (no notch, no brake demand): both latches release within ~0.5s ---
    do
        local state = stuck_state()
        local idle_inputs = h.encode_stateless_in({
            speed = 15, catenary_voltage_sw = 1500, notch_pos = 0,
            direction = 1, brake_pressure_sw = 5, sap_pressure_sw = 5,
        })
        local released_tick = nil
        for tick = 1, 150 do
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
            speed = 15, catenary_voltage_sw = 1500, notch_pos = 0,
            direction = 1, brake_pressure_sw = 5, sap_pressure_sw = 5,
        })
        for tick = 1, 150 do
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
