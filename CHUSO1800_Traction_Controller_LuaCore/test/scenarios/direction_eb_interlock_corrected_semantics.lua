-- SPEC.md §4.2/H1: the sw-net TEXT shows direction_nonzero as THRESHOLD(0,1)
-- (which would falsely trip EB on forward/+1 as well as neutral/0), but
-- SPEC.md identifies this as a storm-mcl serialization bug -- the real
-- machine value is THRESHOLD(0,0), i.e. EB only on direction==0 (neutral/no
-- reverser selected). This module implements the REAL semantics
-- (direction == 0 only). This test is a regression guard against the literal
-- (0,1) bug reappearing.

local core = require("chuso1800_core")

local function notch_ge1_after_one_tick(forward, backward)
    local state = core.zero_state()
    local stateless_in = core.encode_stateless_in({
        notch_pos = 1,
        forward_signal = forward,
        backward_signal = backward,
    })
    local stateless_out = core.calculateTick(stateless_in, state)
    return core.decode_stateless_out(stateless_out).notch_ge1
end

return function(h)
    h.assert_true(notch_ge1_after_one_tick(true, false), "forward (+1): power available, no EB")
    h.assert_true(notch_ge1_after_one_tick(false, true), "backward (-1): power available, no EB")
    h.assert_false(notch_ge1_after_one_tick(false, false), "neutral (direction==0): EB trips, power cut")
end
