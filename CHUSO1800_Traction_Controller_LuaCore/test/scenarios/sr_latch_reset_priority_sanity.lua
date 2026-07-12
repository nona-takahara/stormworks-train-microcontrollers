-- SPEC.md §0.1/H6: every SR latch is reset-priority (simultaneous set+reset
-- -> Off) and must not oscillate when re-evaluated with unchanged inputs.
-- Exercised directly against the global sr_latch (exposed for testing only)
-- rather than through a specific latch in core_tick: phase1/phase2/regen are
-- all driven by multi-condition derived set/reset expressions, not simple
-- direct inputs, so unit-testing the shared sr_latch helper in isolation is
-- both simpler and a more precise test of the reset-priority mechanics
-- itself (all three latches share this exact same implementation).


return function(h)
    -- set only, from Off -> latches true
    h.assert_true(sr_latch(false, true, false), "set-only latches true")

    -- hold: neither set nor reset -> keeps the old value
    h.assert_true(sr_latch(true, false, false), "holds true with neither set nor reset")
    h.assert_false(sr_latch(false, false, false), "holds false with neither set nor reset")

    -- simultaneous set+reset -> reset wins (Off), regardless of old value
    h.assert_false(sr_latch(true, true, true), "reset wins on simultaneous set+reset, from On")
    h.assert_false(sr_latch(false, true, true), "reset wins on simultaneous set+reset, from Off")

    -- repeated simultaneous set+reset -> stays Off, no oscillation
    local q = true
    for tick = 1, 10 do
        q = sr_latch(q, true, true)
        h.assert_false(q, "stays off under sustained set+reset, tick " .. tick)
    end

    -- reset only, from Off -> stays Off
    h.assert_false(sr_latch(false, false, true), "reset-only from Off stays Off")

    -- set only, from On -> stays On (idempotent)
    h.assert_true(sr_latch(true, true, false), "set-only from On stays On")
end
