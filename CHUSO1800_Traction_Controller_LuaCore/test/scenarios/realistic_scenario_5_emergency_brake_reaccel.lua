-- User-specified realistic driving scenario 5 (DESIGN_LOG.md #27/#28):
-- full-notch accel to 80km/h -> emergency brake (BP<4atm,gauge, i.e.
-- SPEC.md §11 traction_inhibit's brake_pressure_sw < BRAKE_MIN_PRESSURE)
-- decelerates the vehicle to 30km/h -> 5s notch off -> reaccel to 80km/h.
-- The concern under test: no anomalous current spike anywhere across the
-- EB trip, the release/homing that follows it, and the subsequent restart
-- from whatever cam position homing left behind.

return function(h)
    local M = require("realistic_driving")
    local Sim, kmh = M.Sim, M.kmh

    local sim = Sim.new(h, "Scenario 5: 80km/h accel -> EB brake to 30km/h -> 5s notch off -> reaccel 80km/h (no anomalous current)")

    sim:phase("full notch accel to 80km/h", {
        notch = 4, seconds = 90,
        until_fn = function(self) return self.speed >= kmh(80) end,
    })
    sim:phase("emergency brake (BP<4atm), external decel to 30km/h over 10s", {
        notch = 4, eb = true, seconds = 10,
        speed_ramp = { target_kmh = 30, over_seconds = 10 },
    })
    sim:phase("notch off, 5s", { notch = 0, seconds = 5 })
    sim:phase("reaccel to 80km/h", {
        notch = 4, seconds = 90,
        until_fn = function(self) return self.speed >= kmh(80) end,
    })

    h.assert_eq(#sim.anomalies, 0, "no anomalies (in particular, no anomalous current spike): " .. table.concat(sim.anomalies, "; "))
    h.assert_true(sim.speed >= kmh(79), "vehicle successfully reaccelerates back to 80km/h")
end
