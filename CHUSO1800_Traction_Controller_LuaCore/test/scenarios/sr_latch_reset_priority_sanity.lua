-- SPEC.md §0.1/H6: every SR latch is reset-priority (simultaneous set+reset
-- -> Off) and must not oscillate when re-evaluated with unchanged inputs.
-- Exercised via panta1_latch (set=panta1_up_signal, reset=panta1_down_signal)
-- since it is the simplest latch with directly-driven set/reset inputs (no
-- derived conditions to control for).

local core = require("chuso1800_core")

return function(h)
    local state = core.zero_state()

    -- set only -> latches true
    local set_only = core.encode_stateless_in({ panta1_up_signal = true })
    local _, s1 = core.calculateTick(set_only, state)
    state = s1
    h.assert_true(core.decode_state(state).panta1_latch, "set-only latches true")

    -- hold: neither set nor reset -> stays true
    local hold = core.encode_stateless_in({})
    local _, s2 = core.calculateTick(hold, state)
    state = s2
    h.assert_true(core.decode_state(state).panta1_latch, "holds true with neither set nor reset")

    -- simultaneous set+reset -> reset wins (Off)
    local both = core.encode_stateless_in({ panta1_up_signal = true, panta1_down_signal = true })
    local _, s3 = core.calculateTick(both, state)
    state = s3
    h.assert_false(core.decode_state(state).panta1_latch, "reset wins on simultaneous set+reset")

    -- repeated simultaneous set+reset -> stays Off, no oscillation
    for tick = 1, 10 do
        local _, s = core.calculateTick(both, state)
        state = s
        h.assert_false(core.decode_state(state).panta1_latch, "stays off under sustained set+reset, tick " .. tick)
    end

    -- reset only, from Off -> stays Off
    local reset_only = core.encode_stateless_in({ panta1_down_signal = true })
    local _, s4 = core.calculateTick(reset_only, state)
    state = s4
    h.assert_false(core.decode_state(state).panta1_latch, "reset-only from Off stays Off")
end
