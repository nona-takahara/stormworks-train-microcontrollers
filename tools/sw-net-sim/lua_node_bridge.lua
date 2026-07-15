-- Wraps a Stormworks-style Lua microcontroller script (global
-- input.getNumber/getBool, output.setNumber/setBool, onTick()) so it can be
-- driven tick-by-tick as a sim.lua LUA-type node. Each wrapped script gets
-- its own isolated global environment (falling back to the real _G for
-- reads of stdlib things like math/string), matching how each Stormworks
-- LUA node has independent globals -- this is what lets a script's
-- top-level persistent state (e.g. n409.lua's OLD_I/OLD_IF_A/OLD_PHI) work
-- unmodified, exactly as it does on the real microcontroller.

local M = {}

function M.wrap(scriptPath)
    local current_in, current_out
    local env = setmetatable({
        input = {
            getNumber = function(ch) return (current_in and current_in.n[ch]) or 0 end,
            getBool = function(ch) return (current_in and current_in.b[ch]) or false end,
        },
        output = {
            setNumber = function(ch, v) current_out.n[ch] = v end,
            setBool = function(ch, v) current_out.b[ch] = v end,
        },
    }, { __index = _G })

    local chunk = assert(loadfile(scriptPath, "t", env))
    chunk() -- runs the script body once, matching Stormworks running a LUA node's script on load

    return function(compositeIn)
        current_in = compositeIn or { n = {}, b = {} }
        current_out = { n = {}, b = {} }
        env.onTick()
        return current_out
    end
end

return M
