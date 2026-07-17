-- SPEC.md §2/§11 (originally analyzed under the old SPEC.md's now-removed
-- H1): the sw-net TEXT shows direction_nonzero as THRESHOLD(0,1) (which
-- would falsely trip traction_inhibit on forward/+1 as well as neutral/0),
-- but SPEC.md §2 identifies this as one of six nodes hit by a sw-net
-- generation bug -- the real machine value is THRESHOLD(0,0) (renamed
-- `direction_neutral` in current SPEC.md/main.sw-net), i.e. traction_inhibit
-- only on direction==0 (neutral/no reverser selected). This module
-- implements the REAL semantics (direction == 0 only). This test is a
-- regression guard against the literal (0,1) bug reappearing.
--
-- direction now arrives as a pre-resolved -1/0/+1 number (gates compute it
-- from forward/backward reverser signals); brake_pressure_sw is set to a
-- safe non-EB-triggering value (>=4) so only the direction interlock is
-- exercised.


local function notch_ge1_after_one_tick(h, direction)
    local state = zero_state()
    local stateless_in = h.encode_stateless_in({
        notch_pos = 1,
        direction = direction,
        brake_pressure_sw = 5,
    })
    local stateless_out = core_tick(stateless_in, state)
    return h.decode_stateless_out(stateless_out).notch_ge1
end

return function(h)
    h.assert_true(notch_ge1_after_one_tick(h, 1), "forward (+1): power available, no EB")
    h.assert_true(notch_ge1_after_one_tick(h, -1), "backward (-1): power available, no EB")
    h.assert_false(notch_ge1_after_one_tick(h, 0), "neutral (direction==0): EB trips, power cut")
end
