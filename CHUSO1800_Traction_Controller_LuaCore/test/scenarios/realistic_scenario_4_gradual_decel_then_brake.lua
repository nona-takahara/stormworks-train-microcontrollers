-- User-specified realistic driving scenario 4 (DESIGN_LOG.md #27/#28):
-- full-notch accel to 60km/h -> notch off -> external resistance gradually
-- decelerates the vehicle to 35km/h (expected to switch into series field
-- control, same mechanism as scenario 3) -> SAP 4atm brake to a stop
-- (expecting regen braking to engage from the series field control state,
-- then cleanly hand off to the pneumatic brake once regen ends).

return function(h)
    local M = require("realistic_driving")
    local Sim, kmh = M.Sim, M.kmh

    local sim = Sim.new(h, "Scenario 4: 60km/h accel -> notch off -> external decel to 35km/h (series field control) -> SAP4 brake (regen -> regen ends)")

    sim:phase("full notch accel to 60km/h", {
        notch = 4, seconds = 90,
        until_fn = function(self) return self.speed >= kmh(60) end,
    })
    sim:phase("notch off, external gradual decel to 35km/h over 20s", {
        notch = 0, seconds = 20,
        speed_ramp = { target_kmh = 35, over_seconds = 20 },
    })

    local saw_series_field_control = false
    local saw_regen_current = false
    local regen_ended_before_stop = false
    sim:phase("SAP 4atm brake to stop (regen then regen-ends)", {
        notch = 0, sap = 4.0, seconds = 60,
        until_fn = function(self, stateless_out, st)
            if st.phase1_latch and st.regen_latch then saw_series_field_control = true end
            if st.regen_latch and stateless_out[1] < -10 then saw_regen_current = true end
            if saw_regen_current and (not st.regen_latch) and self.speed > kmh(0.5) then
                regen_ended_before_stop = true
            end
            return self.speed <= kmh(0.5)
        end,
    })

    h.assert_eq(#sim.anomalies, 0, "no anomalies: " .. table.concat(sim.anomalies, "; "))
    h.assert_true(saw_series_field_control,
        "gradual external deceleration demotes Parallel+field-control into series field control")
    h.assert_true(saw_regen_current, "regen braking actually engages (negative armature current) during the SAP4 descent")
    h.assert_true(regen_ended_before_stop, "regen cleanly hands off to the pneumatic brake before the vehicle stops")
    h.assert_true(sim.speed <= kmh(1), "vehicle actually comes to a stop under SAP4 braking")
end
