-- Reusable closed-loop driving-scenario harness for CHUSO1800 Lua Core
-- regression tests (see test/scenarios/realistic_scenario_*.lua). Unlike the
-- other scenario files -- which drive core_tick with a handful of fixed
-- inputs to check a single transition -- this harness integrates the
-- module's own outputs (accel, bcT) back into a simulated vehicle speed
-- every tick, so a scenario can string together realistic driving phases
-- (accelerate to a target speed, coast, brake) end-to-end and let both
-- powering AND regen-braking deceleration come from the module's own
-- physics, not an external assumption.
--
-- Origin: DESIGN_LOG.md #27/#28 -- these scenarios (proposed by the user as
-- a battery of realistic driving profiles to exercise notch-off coasting,
-- externally-imposed deceleration, emergency braking, and regen
-- interruption/resumption) are what surfaced the #27/#28 regressions in the
-- first place, so they're kept here as permanent regression coverage rather
-- than one-off scratch scripts.
--
-- Assumes chuso1800_core.lua's globals (core_tick, zero_state, ...) are
-- already loaded, same as every other file under test/scenarios/.

local KMH = 1 / 3.6
local TICK_DT = 1 / 60

-- far beyond POWER_LIMIT_CURRENT(210)/field-current-excess thresholds
-- (300/400): anything past this during a phase is a real anomaly, not just
-- an expected transient current-limited climb.
local CURRENT_SPIKE_A = 1000

local M = {}
M.TICK_DT = TICK_DT

function M.kmh(v) return v * KMH end
function M.to_kmh(v) return v / KMH end

local Sim = {}
Sim.__index = Sim
M.Sim = Sim

-- h: the test harness module (test/harness.lua), for its encode/decode
-- wrappers and to keep this file free of any core_tick-shape knowledge.
function Sim.new(h, name)
    local self = setmetatable({}, Sim)
    self.h = h
    self.name = name
    self.state = zero_state()
    self.speed = 0
    self.t = 0
    self.anomalies = {}
    self.last_pos = 0
    return self
end

function Sim:anomaly(msg)
    table.insert(self.anomalies, string.format("t=%.2fs v=%.2fkm/h: %s", self.t, M.to_kmh(self.speed), msg))
end

-- opts: notch, direction(default 1), sap(resolved sap_pressure_sw,
-- default 1.0=no demand), bp(resolved brake_pressure_sw, default 5=ok),
-- eb(bool), db_auto(bool), seconds(duration), speed_ramp={target_kmh=,
-- over_seconds=} (external deceleration/acceleration source, overrides the
-- closed loop -- for "外部抵抗による緩やかな減速" scenarios), print_every
-- (seconds, default never), expect_cam_static(bool, flag if cam moves),
-- until_fn(function(self, stateless_out, decoded_state) -> bool) stop early
-- if true.
function Sim:phase(label, opts)
    opts = opts or {}
    local notch = opts.notch or 0
    local direction = opts.direction or 1
    local sap = opts.sap or 1.0
    local bp = opts.bp or 5
    local eb = opts.eb or false
    local db_auto = opts.db_auto or false
    local seconds = opts.seconds or 999
    local ticks = math.floor(seconds * 60 + 0.5)
    local ramp = opts.speed_ramp
    local print_every = opts.print_every

    local start_speed = self.speed
    local ramp_target = ramp and M.kmh(ramp.target_kmh) or nil
    local last_print = -999

    for tick = 1, ticks do
        -- eb=true forces bp below BRAKE_MIN_PRESSURE(4) regardless of the
        -- passed bp, matching "非常制動(BP<4atm,gauge)" scenarios directly
        -- (SPEC §11 traction_inhibit: brake_pressure_sw < 4 trips EB).
        local effective_bp = eb and math.min(bp, 2) or bp
        local stateless_in = self.h.encode_stateless_in({
            speed = self.speed, catenary_voltage_sw = 1500, brake_pressure_sw = effective_bp,
            sap_pressure_sw = sap, direction = direction, notch_pos = notch, regen_flag = db_auto,
        })
        local so, ns = core_tick(stateless_in, self.state)
        self.state = ns
        local st = self.h.decode_state(self.state)
        local d = self.h.decode_stateless_out(so)

        if ramp then
            local frac = tick / ticks
            self.speed = start_speed + (ramp_target - start_speed) * frac
        else
            -- stateless_out[3] ("bc_target_smooth" in harness.lua's naming,
            -- but SIGNAL_MAP.md documents its real content as the vehicle's
            -- own smoothed acceleration -- see DESIGN_LOG.md #20/#25) is the
            -- electrical accel (already negative under regen); stateless_
            -- out[4]=bcT (SPEC §10.4: positive shortfall the pneumatic brake
            -- must supply on top of it). Total vehicle accel is their
            -- difference, matching the pneumatic_brake_fallback_demand
            -- convention (assumes an idealized air brake that fully
            -- delivers the requested deceleration; real Stormworks air-brake
            -- dynamics aren't modeled here).
            local total_accel = d.bc_target_smooth - d.bcT
            self.speed = self.speed + total_accel * TICK_DT
            if self.speed < 0 then self.speed = 0 end
        end
        self.t = self.t + TICK_DT

        if math.abs(d.motor_current) > CURRENT_SPIKE_A then
            self:anomaly(string.format("motor_current=%.1fA exceeds %dA threshold (phase '%s')",
                d.motor_current, CURRENT_SPIKE_A, label))
        end
        -- DESIGN_LOG.md #29 follow-up: a PR reviewer measurement found that
        -- physics_tick's "always compute from the OLD latch state" tick
        -- model (see chuso1800_core.lua's own header note) could leave one
        -- tick where the real physical output was still nonzero even though
        -- phase_state_machine had just decided to fully disconnect. Two
        -- distinct channels turned out to be involved: `motor_current` (also
        -- fed to the "W" output port, confirmed by the PR author to go to a
        -- *separate* system, not the vehicle's own physics) measured ~49A
        -- for one tick, and -- more importantly -- `bc_target_smooth`
        -- (Momelink-A N2, confirmed by the PR author to be what *actually*
        -- drives this vehicle's real acceleration) measured a raw value of
        -- ~0.39 m/s^2 immediately after EB, decaying over ~7 ticks before
        -- dropping under the reviewer's 0.1 m/s^2 bound (its EMA smoothing
        -- carries forward pre-disconnect history even though the accel
        -- *input* feeding it was already correctly zeroed). Both are now
        -- fixed at the source (`output_zero_this_tick` retroactively zeros
        -- motor_current/W; `smooth_bc`'s `force_bc_target_zero` bypasses the
        -- EMA and zeros both the output and the carried-forward state), so
        -- this checks both as an always-true invariant: with both series/
        -- phase1 and parallel/phase2 released, all three must be exactly
        -- zero, every tick, in every scenario -- not just at the specific
        -- transition moments the unit-level regression test
        -- (`eb_and_db_auto_off_force_disconnect.lua`) constructs. Checking
        -- it here means every realistic_scenario_*.lua exercises it for
        -- free, per the project's preference for extending the existing
        -- scenario set over adding narrow new ones.
        if (not st.phase1_latch) and (not st.phase2_latch) then
            if math.abs(d.motor_current) > 1e-9 or math.abs(d.W) > 1e-9 or math.abs(d.bc_target_smooth) > 1e-9 then
                self:anomaly(string.format(
                    "output nonzero while fully disconnected: motor_current=%.4fA W=%.4f bc_target_smooth(Momelink-A N2, real drive signal)=%.5f (phase '%s')",
                    d.motor_current, d.W, d.bc_target_smooth, label))
            end
        end
        if opts.expect_cam_static and st.position_counter ~= self.last_pos then
            self:anomaly(string.format("cam moved %d -> %d during phase '%s' (expected static)",
                self.last_pos, st.position_counter, label))
        end
        self.last_pos = st.position_counter

        if print_every and (self.t - last_print >= print_every) then
            last_print = self.t
            print(string.format("  [t=%6.2fs v=%6.2fkm/h] %s I=%9.2f accel=%7.3f bcT=%7.3f pos=%2d ph1=%s ph2=%s rg=%s",
                self.t, M.to_kmh(self.speed), label, d.motor_current, d.bc_target_smooth, d.bcT, st.position_counter,
                tostring(st.phase1_latch), tostring(st.phase2_latch), tostring(st.regen_latch)))
        end

        if opts.until_fn and opts.until_fn(self, so, st) then break end
    end
end

return M
