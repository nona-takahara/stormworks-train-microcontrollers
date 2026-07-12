-- Tests chuso1800_core's own inlined bit-field helpers (global
-- to_u32/get_bits/put_bits, exposed for this purpose only -- see the
-- module header comment on why these are inlined rather than a separate
-- `dofile`d file: it must stay standalone-testable with no dependency on
-- state_sync.lua or anything else). Named-field layout tables
-- (STATE_LATCHES_LAYOUT etc.) were removed in favor of numeric shift/width
-- arguments baked directly into decode_state/encode_state/
-- decode_stateless_out -- see DESIGN_LOG.md #13 for why (Stormworks'
-- 8192-character LUA node limit; the field-name strings a generic
-- layout-table mechanism carries don't shrink under minification the way
-- identifiers do).


return function(h)
    -- to_u32: pass-through for small ints, floors a fractional double, and
    -- wraps like a real unsigned 32-bit value past 2^32 (string.pack("I4",...)
    -- semantics, not saturating/clamping).
    h.assert_eq(to_u32(12345), 12345, "to_u32 passes through a plain integer")
    h.assert_eq(to_u32(12345.7), 12345, "to_u32 floors a fractional double")
    h.assert_eq(to_u32(0), 0, "to_u32(0)")
    h.assert_eq(to_u32(2 ^ 32 + 5), 5, "to_u32 wraps past 2^32")

    -- get_bits/put_bits round trip at boundary values, and fields packed
    -- side by side via bitwise OR don't bleed into their neighbors.
    h.assert_eq(get_bits(put_bits(0, 0, 3), 0, 3), 0, "put/get round trip: min value")
    h.assert_eq(get_bits(put_bits(7, 0, 3), 0, 3), 7, "put/get round trip: max 3-bit value")
    h.assert_eq(get_bits(put_bits(1023, 5, 10), 5, 10), 1023, "put/get round trip: max 10-bit value at a nonzero shift")

    local combined = put_bits(5, 0, 3) | put_bits(1, 3, 1) | put_bits(600, 4, 10) | put_bits(1, 14, 1)
    h.assert_eq(get_bits(combined, 0, 3), 5, "combined field a unaffected by neighbors")
    h.assert_eq(get_bits(combined, 3, 1), 1, "combined field b unaffected by neighbors")
    h.assert_eq(get_bits(combined, 4, 10), 600, "combined field c unaffected by neighbors")
    h.assert_eq(get_bits(combined, 14, 1), 1, "combined field d unaffected by neighbors")

    -- put_bits masks (wraps) rather than clamps an over-width value -- an
    -- intentional behavior change from the old generic pack_bits (which
    -- clamped to the field's max representable value). Every real call
    -- site's inputs are already internally bounded to fit their field
    -- width (debounce counters capped by CAP_DEBOUNCE_TICKS,
    -- periodic_pulse_step resetting before period_ticks, regen_delay_level
    -- clamped to [0,600]), so this is never exercised in practice; this
    -- assertion documents the actual behavior rather than an assumed one.
    h.assert_eq(get_bits(put_bits(99, 0, 3), 0, 3), 99 & 7, "put_bits wraps (not clamps) an over-width value")

    -- Full round trip through the real production encode/decode functions
    -- (a regression guard on the actual bit positions used by
    -- calculateTick, not just the generic helpers in isolation): every
    -- packed field set to its max representable value simultaneously,
    -- checking none of the 6 STATE_LATCHES_LAYOUT-equivalent fields (state
    -- slot 1) or 4 STATE_TIMERS_LAYOUT-equivalent fields (state slot 2)
    -- bleed into each other.
    local state = h.encode_state({
        position_counter = 31, phase1_latch = true, phase2_latch = true, regen_latch = true,
        traction_advance_counter = 15, field_current_excess_counter = 31,
        regen_delay_level = 1023, phase1_cap_counter = 7, phase2_cap_counter = 7,
        current_below_limit_cap_counter = 7,
        OLD_I = 137.5, OLD_IF_A = 162.5, OLD_PHI = 0.028125,
        regen_bc_smooth = -0.0625, bc_target_smooth = -0.015625,
    })
    local decoded = h.decode_state(state)
    h.assert_eq(decoded.position_counter, 31, "decode_state: position_counter at max width")
    h.assert_true(decoded.phase1_latch, "decode_state: phase1_latch")
    h.assert_true(decoded.phase2_latch, "decode_state: phase2_latch")
    h.assert_true(decoded.regen_latch, "decode_state: regen_latch")
    h.assert_eq(decoded.traction_advance_counter, 15, "decode_state: traction_advance_counter at max width")
    h.assert_eq(decoded.field_current_excess_counter, 31, "decode_state: field_current_excess_counter at max width")
    h.assert_eq(decoded.regen_delay_level, 1023, "decode_state: regen_delay_level at max width")
    h.assert_eq(decoded.phase1_cap_counter, 7, "decode_state: phase1_cap_counter at max width")
    h.assert_eq(decoded.phase2_cap_counter, 7, "decode_state: phase2_cap_counter at max width")
    h.assert_eq(decoded.current_below_limit_cap_counter, 7, "decode_state: current_below_limit_cap_counter at max width")
    h.assert_near(decoded.OLD_I, 137.5, 1e-9, "decode_state: OLD_I (raw double, unaffected by neighboring bitfields)")
    h.assert_near(decoded.bc_target_smooth, -0.015625, 1e-9, "decode_state: bc_target_smooth")

    -- STATUS_BITS_LAYOUT-equivalent (stateless_out[5]) round trip via
    -- decode_stateless_out, all 8 single-bit fields set simultaneously.
    local all_status_bits = put_bits(1, 0, 1) | put_bits(1, 1, 1) | put_bits(1, 2, 1)
        | put_bits(1, 3, 1) | put_bits(1, 4, 1) | put_bits(1, 5, 1)
        | put_bits(1, 6, 1) | put_bits(1, 7, 1)
    local status = h.decode_stateless_out({ 0, 0, 0, 0, all_status_bits, 0, 0, 0 })
    h.assert_true(status.cam_pulse, "decode_stateless_out: cam_pulse")
    h.assert_true(status.phase1_latch, "decode_stateless_out: phase1_latch")
    h.assert_true(status.phase2_latch, "decode_stateless_out: phase2_latch")
    h.assert_true(status.regen_latch, "decode_stateless_out: regen_latch")
    h.assert_true(status.notch_ge1, "decode_stateless_out: notch_ge1")
    h.assert_true(status.low_bc_with_regen_flag, "decode_stateless_out: low_bc_with_regen_flag")
    h.assert_true(status.field_current_excess_cond, "decode_stateless_out: field_current_excess_cond")
    h.assert_true(status.power_cut, "decode_stateless_out: power_cut")

    local no_status_bits = h.decode_stateless_out({ 0, 0, 0, 0, 0, 0, 0, 0 })
    h.assert_false(no_status_bits.cam_pulse, "decode_stateless_out: all-zero cam_pulse")
    h.assert_false(no_status_bits.power_cut, "decode_stateless_out: all-zero power_cut")
end
