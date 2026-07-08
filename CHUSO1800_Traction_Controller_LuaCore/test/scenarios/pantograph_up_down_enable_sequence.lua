-- SPEC.md §3.9: panta1_latch/panta2_latch (up/down display latches) are
-- driven by per-pantograph up/down signals and are fully independent of each
-- other. panta_enable_signal, however, is a SINGLE SHARED input in the
-- original design (main.sw-net: both panta1_set_cond and panta2_set_cond
-- read the same Extended IF ch6) -- enabling affects whichever en_latch
-- isn't already up, regardless of which pantograph's up_signal was used.
-- This test exercises the per-pantograph display latches independently and
-- confirms the shared-enable behavior is preserved faithfully (not "fixed"
-- into a per-pantograph enable, which would be a behavior change).

local core = require("chuso1800_core")

return function(h)
    local state = core.zero_state()

    -- up (panta1 only) + shared enable -> panta1_latch sets from its own
    -- up_signal; BOTH en_latches set from the shared enable_signal (neither
    -- display latch was up yet).
    local up_enable = core.encode_stateless_in({ panta1_up_signal = true, panta_enable_signal = true })
    local out1, s1 = core.calculateTick(up_enable, state)
    state = s1
    local st1 = core.decode_state(state)
    local o1 = core.decode_stateless_out(out1)
    h.assert_true(st1.panta1_latch, "panta1_latch sets on its own up_signal")
    h.assert_true(st1.panta1_en_latch, "panta1_en_latch sets on shared enable_signal")
    h.assert_true(o1.panta1_1800_active, "panta1_1800_active true")
    h.assert_true(o1.panta1_1800_latched, "panta1_1800_latched true")
    h.assert_false(st1.panta2_latch, "panta2_latch (display) untouched -- no panta2 up_signal")
    h.assert_true(st1.panta2_en_latch, "panta2_en_latch ALSO sets -- shared enable_signal, faithful to sw-net wiring")

    -- release the transient signals -> both latches hold.
    local hold = core.encode_stateless_in({})
    for tick = 1, 5 do
        local out, ns = core.calculateTick(hold, state)
        state = ns
        local st = core.decode_state(state)
        h.assert_true(st.panta1_latch, "panta1_latch holds tick " .. tick)
        h.assert_true(st.panta1_en_latch, "panta1_en_latch holds tick " .. tick)
    end

    -- down_signal resets only panta1_latch (display), not panta1_en_latch.
    local down = core.encode_stateless_in({ panta1_down_signal = true })
    local out2, s2 = core.calculateTick(down, state)
    state = s2
    local st2 = core.decode_state(state)
    local o2 = core.decode_stateless_out(out2)
    h.assert_false(st2.panta1_latch, "panta1_latch resets on down_signal")
    h.assert_true(st2.panta1_en_latch, "panta1_en_latch survives down_signal (needs all_down)")
    h.assert_false(o2.panta1_1800_latched, "panta1_1800_latched follows panta1_latch")
    h.assert_true(o2.panta1_1800_active, "panta1_1800_active still on (en_latch untouched)")

    -- all_down_signal resets panta1_en_latch.
    local all_down = core.encode_stateless_in({ panta_all_down_signal = true })
    local out3, s3 = core.calculateTick(all_down, state)
    state = s3
    local st3 = core.decode_state(state)
    local o3 = core.decode_stateless_out(out3)
    h.assert_false(st3.panta1_en_latch, "panta1_en_latch resets on all_down_signal")
    h.assert_false(o3.panta1_1800_active, "panta1_1800_active follows panta1_en_latch off")

    -- panta2 independently exercised from a fresh zero state.
    local state2 = core.zero_state()
    local up_enable2 = core.encode_stateless_in({ panta2_up_signal = true, panta_enable_signal = true })
    local out4, s4 = core.calculateTick(up_enable2, state2)
    local st4 = core.decode_state(s4)
    local o4 = core.decode_stateless_out(out4)
    h.assert_true(st4.panta2_latch, "panta2_latch sets on up_signal")
    h.assert_true(st4.panta2_en_latch, "panta2_en_latch sets on enable_signal")
    h.assert_true(o4.panta2_1800_active, "panta2_1800_active true")
    h.assert_false(st4.panta1_latch, "panta1_latch untouched by panta2 sequence")
end
