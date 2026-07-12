-- Stormworks deployment entry point for the CHUSO1800 traction controller.
--
-- NOT meant to be pasted into a Stormworks LUA node as-is: this file is the
-- storm-lua-minify build input (run `node build.js` from this directory --
-- see that file for why a plain `dofile`/`require` with relative paths
-- doesn't work directly).
--
-- ../../lib/state_sync.lua is a repo-wide reusable sync driver (not
-- specific to this module). It defines globals i2f/f2i/onTick, and calls a
-- bare global calculateTick(stateless_in, state_in) every tick, requiring
-- BOTH state_in and state_out to be 8 "integer" values (its own header
-- comment: "state入出力はinteger前提"). Loaded via require (not dofile):
-- storm-lua-minify's `-m` mode wraps every require()-referenced module in
-- exactly one place (its synthesized require() dispatcher); dofile(...)
-- targets get spliced in AGAIN wherever referenced, so using dofile here
-- would duplicate this file's content in the final output for no reason
-- (it defines globals directly, so nothing needs its return value --
-- confirmed the assignment still lands in _G even from inside the
-- dispatcher's IIFE wrapper, since Lua's global environment isn't
-- per-function-scoped).
require("state_sync")

-- ../src/chuso1800_core.lua returns its module table (see that file's own
-- M.calculateTick, which test/run_all.lua exercises directly via `require`
-- in full double precision, unaffected by anything below). This one is
-- loaded via require, not dofile: storm-lua-minify's `-m` (module-like-lua)
-- mode wraps every parsed module in an IIFE for its synthesized require()
-- dispatcher, so a module ending in `return M` works correctly in this
-- expression position (`local core = require(...)`). dofile(...) used the
-- same way does NOT get that IIFE wrapping and corrupts the output when
-- the target module has more than a single trailing expression -- verified
-- empirically against storm-lua-minify 0.1.3 while building this.
local core = require("chuso1800_core")

-- chuso1800_core.lua's state_in/state_out slots 1-2
-- (STATE_LATCHES_LAYOUT/STATE_TIMERS_LAYOUT) are already exact uint32
-- bitfields, so they pass through untouched. Slots 3-7 are raw Lua doubles
-- (OLD_I/OLD_IF_A/OLD_PHI/regen_bc_smooth/bc_target_smooth) -- these are
-- float32-bit-pattern-encoded at this boundary via state_sync.lua's own
-- i2f/f2i (reinterpreting a float32's raw bits as an unsigned 32-bit
-- integer and back), to fit its integer-only contract. This truncates them
-- from double to float32 precision once per tick -- not a new loss, since
-- Stormworks' composite `number` channels are float32-limited regardless.
-- Slot 8 is spare (always 0 either way, no conversion needed).
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
