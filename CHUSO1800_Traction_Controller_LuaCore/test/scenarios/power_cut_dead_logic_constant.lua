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
        core.encode_state({ position_counter = 13, phase1_latch = true, OLD_I = 100000, OLD_IF_A = 500, OLD_PHI = 5 }),
        core.encode_state({ position_counter = 14, phase2_latch = true, regen_latch = true }),
        core.encode_state({ regen_delay_seconds = 0.5, regen_bc_smooth = -50, bc_target_smooth = -999 }),
    }

    local extreme_inputs = {
        core.encode_stateless_in({}),
        core.encode_stateless_in({ speed = 1000, catenary_voltage_sw = 999999, notch_pos = 7, forward_signal = true }),
        core.encode_stateless_in({ controller_stop = true, eb_signal = true }),
        core.encode_stateless_in({ speed = -1000, backward_signal = true, notch_pos = 7 }),
    }

    for si, state in ipairs(extreme_states) do
        for ii, stateless_in in ipairs(extreme_inputs) do
            local s = state
            for tick = 1, 20 do
                local stateless_out, ns = core.calculateTick(stateless_in, s)
                s = ns
                local out = core.decode_stateless_out(stateless_out)
                h.assert_false(out.power_cut, string.format("power_cut stays false (state %d, input %d, tick %d)", si, ii, tick))
            end
        end
    end
end
