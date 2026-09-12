-- SPEC.md §6.2/§7.4 (originally analyzed under the old SPEC.md's now-removed
-- H7): while idle with cam != 0, `regen_off_all` drives the blinker to home
-- the cam back down to exactly 0 (cam only ever increments, so "down" means
-- riding the %21 ring all the way around). Note this is a corrected
-- narrowing from the original H7 write-up: that analysis treated cam
-- positions {0, 1} as *both* counting as "home" (`notch_fb_ge1` read as
-- THRESHOLD(0,1)), so it worried about at most a 1-tick overshoot from 1 to
-- 2. LEGACY_SPEC_CORRECTIONS.md §3 established the real threshold is
-- THRESHOLD(0,0) -- position 1 does NOT stop homing (verified directly:
-- starting `position_counter=1` idle keeps incrementing every debounce
-- window instead of holding), so the home target is strictly {0}, not {0,1}.
--
-- Separately, the old SPEC.md's gate-level analysis noted a possible 1-tick
-- overshoot in the literal gate net because the signal that disables the
-- blinker (`notch_fb` <- `position_counter`) is itself a composite-read hop
-- behind the counter's own self-loop, one extra tick of delay versus the
-- counter reaching its target. This module's "Modeling rule" (see
-- chuso1800_core.lua header) collapses that combinational hop to zero
-- ticks: `regen_off_all` reads state_in.position_counter directly, in the
-- same evaluation that decides whether to advance it. So homing here always
-- lands exactly on cam==0 with no overshoot -- SPEC.md's own closing note in
-- §2 (this compression is an accepted simplification, not a claim that
-- individual gates lack their 1-tick delay) anticipates this kind of
-- transient-corner-case shrinkage. This test asserts what DOES hold in this
-- design (clean homing to exactly 0, no overshoot, no stable rest at 1),
-- rather than silently omitting the corner.


return function(h)
    local state = h.encode_state({
        position_counter = 2,
        phase1_latch = false,
        phase2_latch = false,
        regen_latch = false,
    })

    local idle_inputs = h.encode_stateless_in({
        speed = 0,
        catenary_voltage_sw = 1500,
        notch_pos = 0,
        direction = 1,
        brake_pressure_sw = 5,
    })

    local reached_zero_tick = nil
    for tick = 1, 400 do
        local stateless_out, new_state = core_tick(idle_inputs, state)
        state = new_state
        local st = h.decode_state(state)
        h.assert_false(st.phase1_latch, "stays idle (phase1) tick " .. tick)
        h.assert_false(st.phase2_latch, "stays idle (phase2) tick " .. tick)
        h.assert_false(st.regen_latch, "stays idle (regen) tick " .. tick)
        if st.position_counter == 0 and not reached_zero_tick then
            reached_zero_tick = tick
        end
    end

    h.assert_true(reached_zero_tick ~= nil, "homing reaches cam==0 within 400 ticks")

    -- No overshoot: run further ticks from the already-homed state and
    -- confirm cam stays pinned at exactly 0 (it must not free-run around the
    -- ring again, since regen_off_all is false only once cam==0 -- cam==1 is
    -- NOT a stable rest position under the corrected THRESHOLD(0,0)
    -- semantics, see header comment).
    for tick = 1, 50 do
        local stateless_out, new_state = core_tick(idle_inputs, state)
        state = new_state
        local st = h.decode_state(state)
        h.assert_eq(st.position_counter, 0,
            "cam stays homed at exactly 0 (no overshoot) tick " .. tick)
    end
end
