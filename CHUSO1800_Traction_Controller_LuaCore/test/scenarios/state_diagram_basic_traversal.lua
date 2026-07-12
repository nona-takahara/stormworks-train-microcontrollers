-- Traversal of SPEC.md §3.6's core state diagram: Idle -> Series -> Parallel
-- -> Regen, driven purely by holding notch=3 forward continuously.
--
-- Derivation of the Parallel->Regen transition (not obvious from the
-- mermaid diagram alone -- confirmed here by simulation, not by assumption):
-- phase2 only ever SETS with cam exactly == 14 (traction_phase2_set_cond),
-- so at the instant Parallel begins, cam is far from <=1. Continuing to hold
-- notch>=3 keeps phase2_blinker_cond driving the cam upward through the
-- weak-field range 15..20 (phase2 stays latched throughout, since nothing
-- resets it while current stays non-zero and notch stays >=3). When the cam
-- RING WRAPS from 20 back to 0 (position_counter's `%21`), notch_fb becomes
-- 0 <= 1 while phase2 is still latched -- regen_set_cond fires at exactly
-- that wrap tick.

local core = require("chuso1800_core")

return function(h)
    local state = core.zero_state()
    local st = h.decode_state(core, state)
    h.assert_false(st.phase1_latch, "starts in Idle: phase1 off")
    h.assert_false(st.phase2_latch, "starts in Idle: phase2 off")
    h.assert_false(st.regen_latch, "starts in Idle: regen off")

    local seen_phase1 = false
    local phase2_set_tick, phase2_set_cam = nil, nil
    local regen_set_tick = nil

    for tick = 1, 3000 do
        -- A fixed speed leaves the controller stuck forever at cam=14: with
        -- phase1/srsmtr=8, SR[15]=0 (zero resistance), so motor current is
        -- enormous and current_below_limit_cap never charges, freezing the
        -- blinker (traction_any_active goes permanently false). A slow speed
        -- ramp stands in for vehicle acceleration (rising back-EMF reduces
        -- current as the real controller would experience), letting the
        -- state machine actually clear the zero-resistance transition point.
        local speed = 1 + tick * 0.03
        local stateless_in = h.encode_stateless_in(core, {
            speed = speed,
            catenary_voltage_sw = 1500,
            notch_pos = 3,
            direction = 1,
            brake_pressure_sw = 5,
        })
        local stateless_out, new_state = core.calculateTick(stateless_in, state)
        state = new_state
        st = h.decode_state(core, state)

        if st.phase1_latch and not seen_phase1 then
            seen_phase1 = true
        end
        if st.phase2_latch and not phase2_set_tick then
            phase2_set_tick = tick
            phase2_set_cam = st.position_counter
        end
        if st.regen_latch and not regen_set_tick then
            regen_set_tick = tick
            break
        end
    end

    h.assert_true(seen_phase1, "phase1 (Series) latches at some point")
    h.assert_true(phase2_set_tick ~= nil, "phase2 (Parallel) latches at some point")
    h.assert_true(phase2_set_tick > 1, "phase2 latches strictly after tick 1 (after Series first)")
    h.assert_eq(phase2_set_cam, 14, "phase2 only sets with cam exactly at 14")
    h.assert_true(regen_set_tick ~= nil, "regen latches at some point")
    h.assert_true(regen_set_tick > phase2_set_tick, "regen latches after phase2")
    h.assert_true(st.phase2_latch, "phase2 still latched when regen sets")
    h.assert_true(st.position_counter <= 1, "cam has wrapped to <=1 when regen sets")
end
