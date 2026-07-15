-- Standalone sanity run of the original (原稿) CHUSO1800_Traction_Controller
-- gate network through the sw-net-sim engine: no chuso1800_core.lua
-- involved yet, just checking the simulator itself behaves sensibly
-- (traction engages, cam advances periodically, current builds up) under a
-- sustained full-notch power scenario.
--
-- Run: lua smoke_scenario.lua

local this_file = debug.getinfo(1, "S").source:sub(2)
local this_dir = this_file:match("(.*/)") or "./"
package.path = this_dir .. "?.lua;" .. package.path

local sim_mod = require("sim")
local bridge_mod = require("lua_node_bridge")

local graph = dofile(this_dir .. "chuso1800_original.graph.lua")
local lua_node_id
for _, n in ipairs(graph.nodes) do
    if n.type == "LUA" then lua_node_id = n.id end
end

local n409_tick = bridge_mod.wrap(this_dir .. "../../CHUSO1800_Traction_Controller/scripts/n409.lua")
local sim = sim_mod.new(graph, { lua_bridges = { [lua_node_id] = n409_tick } })

local function empty_composite() return { n = {}, b = {} } end

-- Simple IF: n1=brake cmd(atm), n2=notch(0-7); b1=EB, b16=fwd, b17=rev, b18=DB auto
local function simple_if(notch, fwd, rev, eb, db_auto)
    local c = empty_composite()
    c.n[1] = 0
    c.n[2] = notch
    c.b[1] = eb or false
    c.b[16] = fwd or false
    c.b[17] = rev or false
    c.b[18] = db_auto or false
    return c
end

-- Extended IF: b4=panta1 up, b5=panta1 down, b6=panta enable, b7=all panta down
local function extended_if(panta1_up, panta_enable)
    local c = empty_composite()
    c.b[4] = panta1_up or false
    c.b[6] = panta_enable or false
    return c
end

local function inputs(notch, fwd, tick)
    return {
        ["Phyics Sensor [+Z is front]"] = empty_composite(),
        ["Catenary Line Voltage [V]"] = 1500,
        ["SAP [atm]"] = 5,
        ["Controller Stop"] = false,
        ["BP [atm]"] = 5,
        ["Simple IF"] = simple_if(notch, fwd, false, false, false),
        -- raise panta1 with a brief "up" pulse, keep panta enable held true throughout
        ["Extended IF"] = extended_if(tick >= 2 and tick <= 3, true),
        ["BC [atm abs]"] = 1,
        ["Momelink inner unit"] = empty_composite(),
        ["MR [atm abs]"] = 9,
    }
end

print(string.format("%5s %6s %6s %6s %6s %6s %10s %10s",
    "tick", "pos", "ph1", "ph2", "regen", "cam", "motor_I", "W"))

local cam_count = 0
for tick = 1, 400 do
    local out = sim:step(inputs(4, true, tick))
    if out["cam"] then cam_count = cam_count + 1 end
    if tick % 20 == 0 or tick <= 5 then
        print(string.format("%5d %6d %6s %6s %6s %6s %10.3f %10.3f",
            tick,
            sim:signal("position_counter_out") or -1,
            tostring(sim:signal("traction_phase1_latch_q")),
            tostring(sim:signal("traction_phase2_latch_q")),
            tostring(sim:signal("regen_latch_q")),
            tostring(out["cam"]),
            sim:signal("motor_current_out") or 0,
            out["W"] or 0))
    end
end
print("total cam pulses over 400 ticks:", cam_count)
