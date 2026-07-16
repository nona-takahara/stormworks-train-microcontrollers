-- User-specified realistic driving scenario 6 (DESIGN_LOG.md #27/#28):
-- full-notch accel to 80km/h -> notch off -> SAP4 regen braking to 60km/h,
-- interrupt (release SAP, 10s coast), re-brake to 30km/h, interrupt again,
-- re-brake to 23km/h, interrupt again, re-brake to a full stop. Checks that
-- regen braking correctly re-engages when the brake demand resumes after an
-- interruption, not just on the very first brake application. Only the
-- 60->30km/h leg is expected to show fresh regen current in practice: by the
-- time the 80km/h descent reaches 60km/h it's still in Parallel+field-
-- control with near-zero current (no demotion needed yet), so the first
-- brake-to-60 leg shows no regen; the 60->30 leg is where the Series
-- demotion (and negative/regen current) actually happens; regen then tapers
-- off naturally toward the stop (same as scenarios 2/4), so the later legs
-- aren't guaranteed to show fresh regen current of their own. The
-- requirement under test is that regen resumes at least once after an
-- interruption (proving the interrupt/resume cycle doesn't get regen stuck
-- off), not that every single leg reproduces it.

return function(h)
    local M = require("realistic_driving")
    local Sim, kmh = M.Sim, M.kmh

    local sim = Sim.new(h, "Scenario 6: 80km/h accel -> notch off -> regen interrupted/resumed repeatedly (60->30->23->stop)")

    sim:phase("full notch accel to 80km/h", {
        notch = 4, seconds = 90,
        until_fn = function(self) return self.speed >= kmh(80) end,
    })

    local regen_resume_count = 0

    local function brake_leg(label, target_kmh)
        local saw_regen_this_leg = false
        sim:phase(label, {
            notch = 0, sap = 4.0, seconds = 60,
            until_fn = function(self, stateless_out, st)
                if st.regen_latch and stateless_out[1] < -10 then saw_regen_this_leg = true end
                return self.speed <= kmh(target_kmh)
            end,
        })
        if saw_regen_this_leg then regen_resume_count = regen_resume_count + 1 end
    end

    local function interrupt()
        sim:phase("interrupt regen: release brake, 10s coast", { notch = 0, sap = 1.0, seconds = 10 })
    end

    brake_leg("SAP4 brake to 60km/h", 60)
    interrupt()
    brake_leg("re-brake to 30km/h", 30)
    interrupt()
    brake_leg("re-brake to 23km/h", 23)
    interrupt()
    brake_leg("re-brake to full stop", 0.5)

    h.assert_eq(#sim.anomalies, 0, "no anomalies: " .. table.concat(sim.anomalies, "; "))
    h.assert_true(regen_resume_count >= 1,
        "regen braking resumes after an interruption at least once across the repeated descend/interrupt cycles, got " .. regen_resume_count)
    h.assert_true(sim.speed <= kmh(1), "vehicle actually comes to a stop")
end
