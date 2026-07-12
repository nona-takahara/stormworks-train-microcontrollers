-- SPEC.md §4.4: power_cut_latch/startup_delay/motor_current_oor is provably
-- dead in main.sw-net (startup_delay's enable is unconnected -> always Off;
-- motor_current_oor's +-200000A threshold is unreachable from the Newton
-- solve). This module simplifies it away entirely (see README.md
-- "Simplifications") and exposes `power_cut` as a hardcoded-false status
-- bit. This test drives an adversarial mix of extreme inputs/states across
-- many ticks and confirms the bit never becomes true.

local core = require("chuso1800_core")

return function(h)
    local extreme_states = {
        core.zero_state(),
        h.encode_state(core, { position_counter = 13, phase1_latch = true, OLD_I = 100000, OLD_IF_A = 500, OLD_PHI = 5 }),
        h.encode_state(core, { position_counter = 14, phase2_latch = true, regen_latch = true }),
        h.encode_state(core, { regen_delay_level = 600, regen_bc_smooth = -50, bc_target_smooth = -999 }),
    }

    local extreme_inputs = {
        h.encode_stateless_in(core, {}),
        h.encode_stateless_in(core, { speed = 1000, catenary_voltage_sw = 999999, notch_pos = 7, direction = 1, brake_pressure_sw = 5 }),
        h.encode_stateless_in(core, { controller_stop = true, brake_pressure_sw = 0 }),
        h.encode_stateless_in(core, { speed = -1000, direction = -1, notch_pos = 7, brake_pressure_sw = 5 }),
    }

    for si, state in ipairs(extreme_states) do
        for ii, stateless_in in ipairs(extreme_inputs) do
            local s = state
            for tick = 1, 20 do
                local stateless_out, ns = core.calculateTick(stateless_in, s)
                s = ns
                local out = h.decode_stateless_out(core, stateless_out)
                h.assert_false(out.power_cut, string.format("power_cut stays false (state %d, input %d, tick %d)", si, ii, tick))
            end
        end
    end
end
