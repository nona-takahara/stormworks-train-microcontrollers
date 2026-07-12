-- SPEC.md §4.6/H5: at cam==14, notch>=3, if motor current is at/above the
-- limit (current_below_limit_cap not charged), phase2_set_cond is false, so
-- the phase1_reset term that depends on it is inactive; phase2_reset's
-- "phase1 AND NOT(notch>=3 AND cam==14)" term is also inactive since cam==14
-- AND notch>=3 both hold. Neither latch has a live reset path, so if both
-- happen to be On simultaneously, they stay On together until the current
-- drops back below the limit. SPEC.md marks this itself as an unresolved
-- "要確認" corner (not a proven-intentional design) -- this test verifies
-- the mechanical sustaining behavior as ported, not that it is desirable.


return function(h)
    local state = h.encode_state({
        position_counter = 14,
        phase1_latch = true,
        phase2_latch = true,
        phase1_cap_counter = 6,
        phase2_cap_counter = 6,
        current_below_limit_cap_counter = 0,
        OLD_I = 100,
        OLD_IF_A = 150,
        OLD_PHI = 0.05,
    })

    -- Low speed at cam==14 (srsmtr=8, SR[15]=0 -- zero resistance) drives
    -- motor current well above the 190A phase2-reduced limit.
    local high_current_inputs = h.encode_stateless_in({
        speed = 1,
        catenary_voltage_sw = 1500,
        notch_pos = 3,
        direction = 1,
        brake_pressure_sw = 5,
    })

    for tick = 1, 10 do
        local stateless_out, new_state = core_tick(high_current_inputs, state)
        state = new_state
        local st = h.decode_state(state)
        h.assert_true(st.phase1_latch, "phase1 held co-on tick " .. tick)
        h.assert_true(st.phase2_latch, "phase2 held co-on tick " .. tick)
        h.assert_eq(st.position_counter, 14, "cam pinned at 14 tick " .. tick)
        h.assert_eq(st.current_below_limit_cap_counter, 0, "debounce never charges while current is high, tick " .. tick)
    end

    -- Release: raise speed so back-EMF drops current below the limit, then
    -- give the debounce capacitor its 6-tick charge window.
    local low_current_inputs = h.encode_stateless_in({
        speed = 20,
        catenary_voltage_sw = 1500,
        notch_pos = 3,
        direction = 1,
        brake_pressure_sw = 5,
    })

    local resolved = false
    for tick = 1, 20 do
        local stateless_out, new_state = core_tick(low_current_inputs, state)
        state = new_state
        local st = h.decode_state(state)
        if not st.phase1_latch then
            resolved = true
            h.assert_true(st.phase2_latch, "phase2 remains latched after resolution")
            h.assert_eq(st.position_counter, 14, "cam still at 14 at resolution")
            break
        end
    end
    h.assert_true(resolved, "co-on resolves to Parallel-only once current drops below the limit")
end
