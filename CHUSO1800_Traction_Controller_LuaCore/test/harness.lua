-- Minimal assertion helpers for the scenario scripts. No external test
-- framework dependency -- just `lua test/run_all.lua`.

local harness = {}

function harness.assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("expected %s, got %s%s",
            tostring(expected), tostring(actual), msg and (" -- " .. msg) or ""), 2)
    end
end

function harness.assert_near(actual, expected, eps, msg)
    eps = eps or 1e-9
    if type(actual) ~= "number" or type(expected) ~= "number" or math.abs(actual - expected) > eps then
        error(string.format("expected ~%s (eps %s), got %s%s",
            tostring(expected), tostring(eps), tostring(actual), msg and (" -- " .. msg) or ""), 2)
    end
end

function harness.assert_true(cond, msg)
    if not cond then
        error("expected true" .. (msg and (" -- " .. msg) or ""), 2)
    end
end

function harness.assert_false(cond, msg)
    if cond then
        error("expected false" .. (msg and (" -- " .. msg) or ""), 2)
    end
end

--------------------------------------------------------------------------
-- Named-table convenience wrappers around chuso1800_core's positional
-- state/physics functions (see DESIGN_LOG.md #13: the core functions
-- themselves take/return plain positional values so storm-lua-minify
-- doesn't carry un-shrinkable table-key strings into the deploy build;
-- scenario files are free to use named tables since they're never part of
-- that build). chuso1800_core.lua is not a module (DESIGN_LOG.md #15):
-- these call the plain global functions test/run_all.lua's dofile()
-- already loaded, not a `core.` table.
--------------------------------------------------------------------------

-- f: { position_counter, phase1_latch, phase2_latch, regen_latch,
-- traction_advance_counter, field_current_excess_counter,
-- regen_delay_level, phase1_cap_counter, phase2_cap_counter,
-- current_below_limit_cap_counter, OLD_I, OLD_IF_A, OLD_PHI,
-- regen_bc_smooth, bc_target_smooth }
function harness.encode_state(f)
    return encode_state(
        f.position_counter, f.phase1_latch, f.phase2_latch, f.regen_latch,
        f.traction_advance_counter, f.field_current_excess_counter,
        f.regen_delay_level, f.phase1_cap_counter, f.phase2_cap_counter, f.current_below_limit_cap_counter,
        f.OLD_I, f.OLD_IF_A, f.OLD_PHI, f.regen_bc_smooth, f.bc_target_smooth)
end

function harness.decode_state(state_in)
    local position_counter, phase1_latch, phase2_latch, regen_latch,
        traction_advance_counter, field_current_excess_counter,
        regen_delay_level, phase1_cap_counter, phase2_cap_counter, current_below_limit_cap_counter,
        OLD_I, OLD_IF_A, OLD_PHI, regen_bc_smooth, bc_target_smooth = decode_state(state_in)
    return {
        position_counter = position_counter, phase1_latch = phase1_latch, phase2_latch = phase2_latch,
        regen_latch = regen_latch, traction_advance_counter = traction_advance_counter,
        field_current_excess_counter = field_current_excess_counter, regen_delay_level = regen_delay_level,
        phase1_cap_counter = phase1_cap_counter, phase2_cap_counter = phase2_cap_counter,
        current_below_limit_cap_counter = current_below_limit_cap_counter,
        OLD_I = OLD_I, OLD_IF_A = OLD_IF_A, OLD_PHI = OLD_PHI,
        regen_bc_smooth = regen_bc_smooth, bc_target_smooth = bc_target_smooth,
    }
end

-- f: { speed, catenary_voltage_sw, brake_pressure_sw, sap_pressure_sw,
-- direction, notch_pos, controller_stop, regen_flag }
function harness.encode_stateless_in(f)
    return encode_stateless_in(f.speed, f.catenary_voltage_sw, f.brake_pressure_sw,
        f.sap_pressure_sw, f.direction, f.notch_pos, f.controller_stop, f.regen_flag)
end

function harness.decode_stateless_out(stateless_out)
    local motor_current, W, bc_target_smooth, bcT, cam_pulse, phase1_latch, phase2_latch, regen_latch,
        notch_ge1, low_bc_with_regen_flag, field_current_excess_cond, power_cut = decode_stateless_out(stateless_out)
    return {
        motor_current = motor_current, W = W, bc_target_smooth = bc_target_smooth, bcT = bcT,
        cam_pulse = cam_pulse, phase1_latch = phase1_latch, phase2_latch = phase2_latch, regen_latch = regen_latch,
        notch_ge1 = notch_ge1, low_bc_with_regen_flag = low_bc_with_regen_flag,
        field_current_excess_cond = field_current_excess_cond, power_cut = power_cut,
    }
end

-- p: { speed, vl, position_counter, direction, notch_eff, phase1, phase2,
-- regen, notch_ge1, low_bc_with_regen_flag, regen_bc_smooth_seed,
-- regen_bc_target, OLD_I, OLD_IF_A, OLD_PHI }
function harness.physics_tick(p)
    local motor_current, back_emf, accel, W, iF_a, bcT, OLD_I, OLD_IF_A, OLD_PHI = physics_tick(
        p.speed, p.vl, p.position_counter, p.direction, p.notch_eff,
        p.phase1, p.phase2, p.regen, p.notch_ge1, p.low_bc_with_regen_flag,
        p.regen_bc_smooth_seed, p.regen_bc_target, p.OLD_I, p.OLD_IF_A, p.OLD_PHI)
    return {
        motor_current = motor_current, back_emf = back_emf, accel = accel, W = W, iF_a = iF_a, bcT = bcT,
        OLD_I = OLD_I, OLD_IF_A = OLD_IF_A, OLD_PHI = OLD_PHI,
    }
end

return harness
