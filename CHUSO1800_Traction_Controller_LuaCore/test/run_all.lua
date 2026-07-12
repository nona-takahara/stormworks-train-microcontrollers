-- Entry point: `lua test/run_all.lua` (path-independent -- works whether run
-- from the repo root or from this directory).

local this_file = debug.getinfo(1, "S").source:sub(2)
local this_dir = this_file:match("(.*/)") or "./"

package.path = this_dir .. "?.lua;" ..
    this_dir .. "scenarios/?.lua;" ..
    this_dir .. "../src/?.lua;" ..
    package.path

local harness = require("harness")

local scenario_names = {
    "bitpack_selftest",
    "physics_regression_vs_n409",
    "state_diagram_basic_traversal",
    "eb_trip_converges_idle",
    "h5_phase1_phase2_coon_corner",
    "h7_cam_overshoot_homing",
    "sr_latch_reset_priority_sanity",
    "current_limit_cam_advance",
    "regen_delay_cap_timing",
    "bc_smoothing_ramp_rates",
    "direction_eb_interlock_corrected_semantics",
    "power_cut_dead_logic_constant",
    "state_sync_bridge",
}

local total, failed = 0, 0
for _, name in ipairs(scenario_names) do
    total = total + 1
    local ok, err = pcall(function()
        local scenario = require(name)
        scenario(harness)
    end)
    if ok then
        print(string.format("PASS  %s", name))
    else
        failed = failed + 1
        print(string.format("FAIL  %s\n      %s", name, tostring(err)))
    end
end

print(string.format("\n%d/%d scenarios passed", total - failed, total))
if failed > 0 then
    os.exit(1)
end
