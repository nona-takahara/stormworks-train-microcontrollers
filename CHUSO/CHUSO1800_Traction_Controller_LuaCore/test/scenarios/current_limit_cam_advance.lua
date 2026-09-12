-- SPEC.md §7.3: cam only advances once motor current has stayed below the
-- limit for the full debounce window (current_below_limit_cap, 0.1s = 6
-- ticks). While current is at/above the limit, the cam must stay put no
-- matter how long we wait.


return function(h)
    -- Sub-test A: current pinned above the limit (cam=10, speed=0 -> low
    -- resistance + no back-EMF => ~1250A, far above the 210A phase1 limit).
    -- The cam must never advance.
    local state_a = h.encode_state({
        position_counter = 10,
        phase1_latch = true,
        phase1_cap_counter = 6, -- already past its own debounce, isolating this test to the current-limit debounce
        current_below_limit_cap_counter = 0,
    })
    local above_limit_inputs = h.encode_stateless_in({
        speed = 0, catenary_voltage_sw = 1500, notch_pos = 2, direction = 1, brake_pressure_sw = 5,
    })
    for tick = 1, 30 do
        local _, ns = core_tick(above_limit_inputs, state_a)
        state_a = ns
        local st = h.decode_state(state_a)
        h.assert_eq(st.position_counter, 10, "cam never advances while current stays above the limit, tick " .. tick)
        h.assert_eq(st.current_below_limit_cap_counter, 0, "debounce counter never charges, tick " .. tick)
    end

    -- Sub-test B: current below the limit (cam=0, speed=20 -> ~29A, well
    -- under 210A). Cam must NOT advance before the debounce has had its full
    -- 6-tick charge window, but must eventually advance.
    local state_b = h.encode_state({
        position_counter = 0,
        phase1_latch = true,
        phase1_cap_counter = 6,
        current_below_limit_cap_counter = 0,
    })
    local below_limit_inputs = h.encode_stateless_in({
        speed = 20, catenary_voltage_sw = 1500, notch_pos = 2, direction = 1, brake_pressure_sw = 5,
    })
    local advanced_tick = nil
    for tick = 1, 30 do
        local _, ns = core_tick(below_limit_inputs, state_b)
        state_b = ns
        local st = h.decode_state(state_b)
        if tick <= 5 then
            h.assert_eq(st.position_counter, 0, "cam does not advance before the debounce window closes, tick " .. tick)
        end
        if st.position_counter ~= 0 and not advanced_tick then
            advanced_tick = tick
        end
    end
    h.assert_true(advanced_tick ~= nil, "cam eventually advances once current stays below the limit")
    h.assert_true(advanced_tick > 5, "advance happens only after the debounce window, got tick " .. tostring(advanced_tick))
end
