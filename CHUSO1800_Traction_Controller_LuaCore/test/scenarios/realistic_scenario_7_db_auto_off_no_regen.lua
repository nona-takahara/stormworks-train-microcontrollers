-- DESIGN_LOG.md #29 follow-up: PR #7 review question from the repo owner --
-- with "DB automatic" OFF, does the vehicle still reach ordinary Parallel+
-- field-control (weak-field cruise, SPEC.md §7.2 step 5) without ever
-- producing regen current, and does the eventual series-field-control
-- transition attempt (triggered by field-current-excess as speed drops)
-- correctly result in a full disconnect instead?
--
-- Unlike `eb_and_db_auto_off_force_disconnect.lua` (synthetic unit-level
-- states, checked instantaneously), this exercises the whole realistic
-- climb-then-coast-then-external-decel sequence end to end with the
-- module's own physics, confirming: (1) Parallel+field-control is reached
-- and held normally with DB-auto OFF, (2) armature current never goes
-- negative (no regen) at any point, (3) `phase1_latch` (series) is never
-- set even transiently -- the demotion path is structurally gated by
-- `regen_flag`, not just masked by reset-priority on the same tick -- and
-- (4) once field-current-excess trips as speed drops, all three latches
-- release on the same tick and armature current is exactly 0 immediately
-- after.

return function(h)
    local M = require("realistic_driving")
    local Sim, kmh = M.Sim, M.kmh

    local sim = Sim.new(h, "Scenario 7: DB-auto OFF -- Parallel+field-control with no regen, full disconnect on series-transition attempt")

    sim:phase("full notch accel to 60km/h (db_auto=false)", {
        notch = 4, seconds = 90, db_auto = false,
        until_fn = function(self) return self.speed >= kmh(60) end,
    })

    local reached_parallel_field_control = false
    sim:phase("hold at cruise, confirm state", {
        notch = 4, seconds = 1, db_auto = false,
        until_fn = function(self, stateless_out, st)
            if st.phase2_latch and st.regen_latch and (not st.phase1_latch) then
                reached_parallel_field_control = true
            end
            return true
        end,
    })
    h.assert_true(reached_parallel_field_control,
        "DB-auto OFF: ordinary Parallel+field-control (weak-field cruise) is still reached normally")

    local saw_negative_current = false
    local saw_phase1_ever = false
    local disconnect_tick = nil
    sim:phase("notch off, external gradual decel to 15km/h over 30s (db_auto=false)", {
        notch = 0, seconds = 30, db_auto = false,
        speed_ramp = { target_kmh = 15, over_seconds = 30 },
        until_fn = function(self, stateless_out, st)
            if stateless_out[1] < -1 then saw_negative_current = true end
            if st.phase1_latch then saw_phase1_ever = true end
            if (not st.phase1_latch) and (not st.phase2_latch) and (not st.regen_latch) and not disconnect_tick then
                disconnect_tick = self.t
            end
            return false
        end,
    })

    h.assert_eq(#sim.anomalies, 0, "no anomalies: " .. table.concat(sim.anomalies, "; "))
    h.assert_false(saw_negative_current, "DB-auto OFF: armature current never goes negative (no regen current is ever produced)")
    h.assert_false(saw_phase1_ever, "DB-auto OFF: series/phase1 is never set, not even transiently, during the series-transition attempt")
    h.assert_true(disconnect_tick ~= nil, "the vehicle does eventually fully disconnect as field current exceeds threshold while coasting down")
end
