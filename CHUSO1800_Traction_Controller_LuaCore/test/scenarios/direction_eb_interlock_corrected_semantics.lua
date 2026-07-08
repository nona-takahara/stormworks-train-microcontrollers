-- SPEC.md §4.2/H1: the sw-net TEXT shows direction_nonzero as THRESHOLD(0,1)
-- (which would falsely trip EB on forward/+1 as well as neutral/0), but
-- SPEC.md identifies this as a storm-mcl serialization bug -- the real
-- machine value is THRESHOLD(0,0), i.e. EB only on direction==0 (neutral/no
-- reverser selected). This module implements the REAL semantics
-- (direction == 0 only). This test is a regression guard against the literal
-- (0,1) bug reappearing.
--
-- direction now arrives as a pre-resolved -1/0/+1 number (gates compute it
-- from forward/backward reverser signals); brake_pressure_sw is set to a
-- safe non-EB-triggering value (>=4) so only the direction interlock is
-- exercised.

local core = require("chuso1800_core")

local function notch_ge1_after_one_tick(direction)
    local state = core.zero_state()
    local stateless_in = core.encode_stateless_in({
        notch_pos = 1,
        direction = direction,
        brake_pressure_sw = 5,
    })
    local stateless_out = core.calculateTick(stateless_in, state)
    return core.decode_stateless_out(stateless_out).notch_ge1
end

return function(h)
    h.assert_true(notch_ge1_after_one_tick(1), "forward (+1): power available, no EB")
    h.assert_true(notch_ge1_after_one_tick(-1), "backward (-1): power available, no EB")
    h.assert_false(notch_ge1_after_one_tick(0), "neutral (direction==0): EB trips, power cut")
end
