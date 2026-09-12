-- User-specified realistic driving scenario 1 (DESIGN_LOG.md #27/#28):
-- full-notch accel to 25km/h -> notch off -> 20s coast -> SAP 4atm brake to
-- a stop. At this low a cruise speed the vehicle never reaches Parallel's
-- field-control step, so no regen braking is expected -- deceleration comes
-- entirely from the pneumatic brake fallback (bcT).

return function(h)
    local M = require("realistic_driving")
    local Sim, kmh = M.Sim, M.kmh

    local sim = Sim.new(h, "Scenario 1: 25km/h accel -> notch off -> 20s coast -> SAP4 brake (no regen)")

    sim:phase("full notch accel to 25km/h", {
        notch = 4, seconds = 60,
        until_fn = function(self) return self.speed >= kmh(25) end,
    })
    sim:phase("notch off, 20s coast", { notch = 0, seconds = 20 })
    sim:phase("SAP 4atm brake to stop", {
        notch = 0, sap = 4.0, seconds = 60,
        until_fn = function(self) return self.speed <= kmh(0.5) end,
    })

    h.assert_eq(#sim.anomalies, 0, "no anomalies: " .. table.concat(sim.anomalies, "; "))
    h.assert_true(sim.speed <= kmh(1), "vehicle actually comes to a stop under SAP4 braking")
end
