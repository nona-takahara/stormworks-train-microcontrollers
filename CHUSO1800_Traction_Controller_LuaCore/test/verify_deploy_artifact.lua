-- Regression guard for DESIGN_LOG.md #18: storm-lua-minify (and luamin, the
-- npm package its own minifier is based on) can silently drop parentheses
-- that are semantically required to override Lua's default operator
-- precedence -- e.g. `(b and 1 or 0) << shift` re-serializes as
-- `b and 1 or 0<<shift`, which Lua parses as `b and 1 or (0<<shift)`,
-- discarding `shift` entirely. `test/run_all.lua`'s scenarios all dofile
-- the pristine `src/chuso1800_core.lua`, so they cannot catch a bug that
-- only exists in the post-minify `deploy/chuso1800_deploy.lua` artifact.
-- This script dofiles the actual deploy artifact instead (with a mock
-- Stormworks `input`/`output`/`property` environment, matching how
-- `lib/state_sync.lua`'s onTick() is really driven) and checks that a
-- known-good tick-by-tick trace (the one from PR #3's real-hardware
-- report) still reaches phase1 and produces real motor current, instead
-- of getting stuck in the "coasting" fixed point this bug produced.
--
-- Entry point: `lua test/verify_deploy_artifact.lua` (path-independent).

local this_file = debug.getinfo(1, "S").source:sub(2)
local this_dir = this_file:match("(.*/)") or "./"

property = {
    getNumber = function(name)
        local defaults = {
            ["Over Speed Th. [m/s]"] = 32,
            ["Power Limit Current [A]"] = 210,
        }
        return defaults[name]
    end,
}

local in_channels, out_channels = {}, {}
for i = 1, 32 do in_channels[i] = 0; out_channels[i] = 0 end
input = { getNumber = function(ch) return in_channels[ch] or 0 end }
output = { setNumber = function(ch, v) out_channels[ch] = v end }

dofile(this_dir .. "../deploy/chuso1800_deploy.lua")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("expected %s, got %s -- %s", tostring(expected), tostring(actual), msg), 2)
    end
end

-- Direct put_bit/put_bits check: this is the exact shape of expression the
-- minifier bug corrupts (a shift applied to a parenthesized and/or or
-- bitwise-and expression).
assert_eq(put_bit(true, 5), 32, "put_bit(true, 5) must actually shift, not collapse to 0/1")
assert_eq(put_bit(false, 5), 0, "put_bit(false, 5)")
assert_eq(put_bits(3, 5, 5), 96, "put_bits(3, 5, 5) must actually shift by 5")

-- Full-pipeline regression: PR #3's real-hardware report (notch_pos=4,
-- direction=1, brake_pressure_sw=5, sap_pressure_sw=1, catenary=1500,
-- speed~0, controller_stop=0, regen_flag=0, fresh state) must reach
-- phase1 and draw real current -- not freeze in the coasting/idle fixed
-- point (position_counter homed to 1, phase1/2/regen all false) that the
-- put_bit/put_bits bug produced.
local stateless_in = { 0.0, 1500, 5, 1, 1, 4, 0, 0 }
for i = 1, 8 do
    in_channels[i] = stateless_in[i]
    in_channels[i + 8] = stateless_in[i]
end

local reached_phase1 = false
local saw_real_current = false
for tick = 1, 30 do
    for i = 17, 32 do in_channels[i] = out_channels[i] end
    onTick()
    if out_channels[21] and (to_u32(out_channels[21]) & 2) ~= 0 then reached_phase1 = true end
    if (out_channels[17] or 0) > 100 then saw_real_current = true end
end

if not reached_phase1 then
    error("deploy artifact never reached phase1_latch=true -- put_bit/put_bits minify regression is back")
end
if not saw_real_current then
    error("deploy artifact never produced real motor current -- put_bit/put_bits minify regression is back")
end

print("PASS  verify_deploy_artifact (put_bit/put_bits survive minification, phase1 engages)")
