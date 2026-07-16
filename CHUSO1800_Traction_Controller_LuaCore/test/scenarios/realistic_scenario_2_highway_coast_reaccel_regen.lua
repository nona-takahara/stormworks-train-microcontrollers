-- User-specified realistic driving scenario 2 (DESIGN_LOG.md #27/#28):
-- full-notch accel to 60km/h -> notch off -> 10s coast -> reaccel to 85km/h
-- (expecting NO cam rotation, since the vehicle should still be sitting in
-- Parallel+field-control the whole time -- see the ~40km/h+ coasting =
-- armature current held at 0A clarification in DESIGN_LOG.md #27) -> 20s
-- coast -> SAP 4atm brake to a stop (expecting regen braking to engage, then
-- cleanly hand off to the pneumatic brake once regen ends).
--
-- This is the exact scenario that originally exposed the #27/#28
-- regressions: pre-fix, the 10s coast at 60km/h spuriously released
-- Parallel+field-control, forcing a full Series-through-Parallel ladder
-- re-climb during reacceleration (21 expect_cam_static violations) and
-- silently discarding regen-braking readiness (zero regen during the final
-- SAP4 descent, pure pneumatic-only deceleration throughout).

return function(h)
    local M = require("realistic_driving")
    local Sim, kmh = M.Sim, M.kmh

    local sim = Sim.new(h, "Scenario 2: 60km/h accel -> notch off -> 10s coast -> reaccel 85km/h (no cam rotation) -> 20s coast -> SAP4 brake (regen -> regen ends)")

    sim:phase("full notch accel to 60km/h", {
        notch = 4, seconds = 90,
        until_fn = function(self) return self.speed >= kmh(60) end,
    })
    sim:phase("notch off, 10s coast", { notch = 0, seconds = 10 })
    sim:phase("reaccel to 85km/h (expect NO cam rotation)", {
        notch = 4, seconds = 60, expect_cam_static = true,
        until_fn = function(self) return self.speed >= kmh(85) end,
    })
    sim:phase("notch off, 20s coast", { notch = 0, seconds = 20 })

    local saw_regen_current = false
    local regen_ended_before_stop = false
    sim:phase("SAP 4atm brake to stop (regen then regen-ends)", {
        notch = 0, sap = 4.0, seconds = 120,
        until_fn = function(self, stateless_out, st)
            if st.regen_latch and stateless_out[1] < -10 then saw_regen_current = true end
            if saw_regen_current and (not st.regen_latch) and self.speed > kmh(0.5) then
                regen_ended_before_stop = true
            end
            return self.speed <= kmh(0.5)
        end,
    })

    h.assert_eq(#sim.anomalies, 0, "no anomalies: " .. table.concat(sim.anomalies, "; "))
    h.assert_true(saw_regen_current, "regen braking actually engages (negative armature current) during the SAP4 descent")
    h.assert_true(regen_ended_before_stop, "regen cleanly hands off to the pneumatic brake before the vehicle stops")
    h.assert_true(sim.speed <= kmh(1), "vehicle actually comes to a stop under SAP4 braking")
end
