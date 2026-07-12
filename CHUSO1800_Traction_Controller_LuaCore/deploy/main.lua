-- Stormworks deployment entry point for the CHUSO1800 traction controller.
--
-- NOT meant to be pasted into a Stormworks LUA node as-is: this file is the
-- storm-lua-minify build input (run `node build.js` from this directory --
-- see that file for why a plain `dofile` with relative paths doesn't work
-- directly).
--
-- Neither ../../lib/state_sync.lua nor ../src/chuso1800_core.lua is a Lua
-- module: both define plain top-level functions/globals with no
-- `local M = {}` table and no `return`. Both are loaded via dofile, in
-- statement position, never require() -- storm-lua-minify's `-m`
-- (module-like-lua) mode is NOT used for this build at all (see
-- DESIGN_LOG.md #15). dofile(...) always gets spliced in as raw statements
-- by storm-lua-minify, in both modes, so this works regardless -- but
-- dropping require()/-m entirely also removes the `-m` mode's require()
-- dispatcher, which is what caused state_sync.lua's content to be
-- duplicated when it coexisted with a require()'d module (DESIGN_LOG.md
-- #14): with nothing require()'d, there is no dispatcher, so there is
-- nothing left to duplicate.
--
-- ../../lib/state_sync.lua is a repo-wide reusable sync driver (not
-- specific to this module). It defines globals i2f/f2i/onTick, and calls a
-- bare global calculateTick(stateless_in, state_in) every tick, requiring
-- BOTH state_in and state_out to be 8 "integer" values (its own header
-- comment: "state入出力はinteger前提").
dofile("state_sync")

-- ../src/chuso1800_core.lua defines core_tick/decode_state/encode_state/
-- physics_tick/etc. as plain globals (see that file's own header comment
-- and DESIGN_LOG.md #15). Its own tick orchestrator is named core_tick,
-- not calculateTick, specifically to avoid colliding with the
-- state_sync-facing `calculateTick` global defined below -- both would
-- otherwise be real top-level globals in the same merged script.
dofile("chuso1800_core")

-- chuso1800_core.lua's state_in/state_out slots 1-2 are already exact
-- uint32 bitfields, so they pass through untouched. Slots 3-7 are raw Lua
-- doubles (OLD_I/OLD_IF_A/OLD_PHI/regen_bc_smooth/bc_target_smooth) --
-- these are float32-bit-pattern-encoded at this boundary via
-- state_sync.lua's own i2f/f2i (reinterpreting a float32's raw bits as an
-- unsigned 32-bit integer and back), to fit its integer-only contract.
-- This truncates them from double to float32 precision once per tick --
-- not a new loss, since Stormworks' composite `number` channels are
-- float32-limited regardless. Slot 8 is spare (always 0 either way, no
-- conversion needed).
function calculateTick(stateless_in, state_in)
    local decoded_state_in = {
        state_in[1], state_in[2],
        i2f(state_in[3]), i2f(state_in[4]), i2f(state_in[5]),
        i2f(state_in[6]), i2f(state_in[7]),
        state_in[8],
    }
    local stateless_out, state_out = core_tick(stateless_in, decoded_state_in)
    local encoded_state_out = {
        state_out[1], state_out[2],
        f2i(state_out[3]), f2i(state_out[4]), f2i(state_out[5]),
        f2i(state_out[6]), f2i(state_out[7]),
        state_out[8],
    }
    return stateless_out, encoded_state_out
end
