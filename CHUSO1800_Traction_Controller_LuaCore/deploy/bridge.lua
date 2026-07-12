-- Bridge between ../../lib/state_sync.lua's synchronization driver and
-- ../src/chuso1800_core.lua's calculateTick.
--
-- lib/state_sync.lua calls a bare global `calculateTick(input, state)` and
-- requires BOTH state_in and state_out to be 8 "integer" values (its own
-- header comment: "state入出力はinteger前提"). `i2f`/`f2i` (defined above
-- by state_sync.lua in the concatenated deploy script) reinterpret a
-- 32-bit float's raw bits as an unsigned 32-bit integer and back -- used
-- here purely as a lossless-per-tick transport encoding, the same
-- `string.pack`/`string.unpack` trick chuso1800_core.lua's own
-- pack_bits/unpack_bits use for its packed bitfields.
--
-- chuso1800_core.lua's state_in/state_out slots 1-2
-- (STATE_LATCHES_LAYOUT/STATE_TIMERS_LAYOUT) are ALREADY exact uint32
-- bitfields, so they pass through untouched. Slots 3-7 are raw Lua doubles
-- (OLD_I/OLD_IF_A/OLD_PHI/regen_bc_smooth/bc_target_smooth) -- these must
-- be float32-bit-pattern-encoded at this boundary to fit state_sync.lua's
-- integer-only contract. This truncates them from double to float32
-- precision once per tick (see i2f_test sanity check in
-- test/scenarios/state_sync_bridge.lua) -- not a new loss introduced here,
-- just made explicit at the boundary instead of happening invisibly
-- in-engine, since Stormworks' own composite `number` channels are
-- float32-limited regardless. Slot 8 is spare (always 0 either way, no
-- conversion needed).
--
-- chuso1800_core.lua itself is untouched by this bridge: its own
-- M.calculateTick keeps operating in full double precision internally, and
-- the standalone test suite (test/run_all.lua) exercises it directly with
-- no float32 rounding anywhere. Only this bridge's boundary is lossy, and
-- only because real Stormworks wiring would be too.

function calculateTick(stateless_in, state_in)
    local decoded_state_in = {
        state_in[1], state_in[2],
        i2f(state_in[3]), i2f(state_in[4]), i2f(state_in[5]),
        i2f(state_in[6]), i2f(state_in[7]),
        state_in[8],
    }
    local stateless_out, state_out = core.calculateTick(stateless_in, decoded_state_in)
    local encoded_state_out = {
        state_out[1], state_out[2],
        f2i(state_out[3]), f2i(state_out[4]), f2i(state_out[5]),
        f2i(state_out[6]), f2i(state_out[7]),
        state_out[8],
    }
    return stateless_out, encoded_state_out
end
