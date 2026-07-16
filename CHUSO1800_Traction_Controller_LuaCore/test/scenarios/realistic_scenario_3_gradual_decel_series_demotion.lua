-- User-specified realistic driving scenario 3 (DESIGN_LOG.md #27/#28):
-- full-notch accel to 60km/h -> notch off -> external resistance gradually
-- decelerates the vehicle to 20km/h (expected to switch into series field
-- control, i.e. phase1_latch+regen_latch both engaged) -> re-power to
-- accelerate back to 60km/h (climbing the ladder from wherever it was left
-- by the demotion, series-wound characteristic first, not skipping back to
-- a bare Parallel reconnect).
--
-- Unlike scenarios 1/2 (coasting under the module's own electrical
-- deceleration only), this uses `speed_ramp` to model an externally-imposed
-- deceleration (e.g. going uphill or through resistance) independent of the
-- module's own physics -- the #28 fix's `near_stop`-gated field-current-
-- excess demotion is exactly the mechanism expected to fire here as current
-- gradually rises during the speed decay in the fully-shorted Parallel step.

return function(h)
    local M = require("realistic_driving")
    local Sim, kmh = M.Sim, M.kmh

    local sim = Sim.new(h, "Scenario 3: 60km/h accel -> notch off -> external decel to 20km/h (series field control) -> reaccel 60km/h")

    sim:phase("full notch accel to 60km/h", {
        notch = 4, seconds = 90,
        until_fn = function(self) return self.speed >= kmh(60) end,
    })

    local saw_series_field_control = false
    sim:phase("notch off, external gradual decel to 20km/h over 30s", {
        notch = 0, seconds = 30,
        speed_ramp = { target_kmh = 20, over_seconds = 30 },
        until_fn = function(self, stateless_out, st)
            if st.phase1_latch and st.regen_latch then saw_series_field_control = true end
            return false
        end,
    })

    sim:phase("reaccel to 60km/h", {
        notch = 4, seconds = 90,
        until_fn = function(self) return self.speed >= kmh(60) end,
    })

    h.assert_eq(#sim.anomalies, 0, "no anomalies: " .. table.concat(sim.anomalies, "; "))
    h.assert_true(saw_series_field_control,
        "gradual external deceleration demotes Parallel+field-control into series field control (phase1_latch and regen_latch both engaged)")
    h.assert_true(sim.speed >= kmh(59), "vehicle successfully reaccelerates back to 60km/h")
end
