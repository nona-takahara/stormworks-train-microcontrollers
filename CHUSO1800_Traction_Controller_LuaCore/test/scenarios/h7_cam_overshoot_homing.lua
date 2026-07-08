-- SPEC.md §4.3/H7: while idle with cam > 1, `regen_off_all` drives the
-- blinker to home the cam back down to <=1 (cam only ever increments, so
-- "down" means riding the %21 ring all the way around to 0). SPEC.md's
-- gate-level analysis notes a possible 1-tick overshoot (cam briefly reaches
-- 2 before homing re-triggers) because in the literal gate net, the signal
-- that disables the blinker (`notch_fb` <- `position_counter`) is itself a
-- composite-read hop behind the counter's own self-loop, i.e. one extra tick
-- of delay versus the counter reaching 0.
--
-- This module's "Modeling rule" (see chuso1800_core.lua header) collapses
-- that combinational hop to zero ticks: `regen_off_all` reads
-- state_in.position_counter directly, in the same evaluation that decides
-- whether to advance it. So homing here always lands exactly on cam==0 with
-- no overshoot -- SPEC.md's own closing note in §0.2 anticipates this kind
-- of transient-corner-case shrinkage from collapsing same-tick propagation.
-- This test asserts what DOES hold in this design (clean homing, no
-- overshoot), and documents why H7's specific overshoot artifact does not
-- reproduce here rather than silently omitting the corner.

local core = require("chuso1800_core")

return function(h)
    local state = core.encode_state({
        position_counter = 2,
        phase1_latch = false,
        phase2_latch = false,
        regen_latch = false,
    })

    local idle_inputs = core.encode_stateless_in({
        speed = 0,
        catenary_voltage_sw = 1500,
        notch_pos = 0,
        direction = 1,
        brake_pressure_sw = 5,
    })

    local reached_zero_tick = nil
    for tick = 1, 400 do
        local stateless_out, new_state = core.calculateTick(idle_inputs, state)
        state = new_state
        local st = core.decode_state(state)
        h.assert_false(st.phase1_latch, "stays idle (phase1) tick " .. tick)
        h.assert_false(st.phase2_latch, "stays idle (phase2) tick " .. tick)
        h.assert_false(st.regen_latch, "stays idle (regen) tick " .. tick)
        if st.position_counter == 0 and not reached_zero_tick then
            reached_zero_tick = tick
        end
    end

    h.assert_true(reached_zero_tick ~= nil, "homing reaches cam==0 within 400 ticks")

    -- No overshoot: run further ticks from the already-homed state and
    -- confirm cam never leaves {0, 1} once homed (it must not free-run
    -- around the ring again, since regen_off_all is false once cam<=1).
    for tick = 1, 50 do
        local stateless_out, new_state = core.calculateTick(idle_inputs, state)
        state = new_state
        local st = core.decode_state(state)
        h.assert_true(st.position_counter == 0 or st.position_counter == 1,
            "cam stays homed (no overshoot) tick " .. tick .. ", got " .. tostring(st.position_counter))
    end
end
