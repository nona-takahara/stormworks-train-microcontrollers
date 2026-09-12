-- Regression for the 1982 compound-motor model. The former n409 numerical
-- identity test is intentionally not applicable after changing the motor
-- constants, SI unit convention, and series-field ratio.

return function(h)
    local idle = h.physics_tick({
        speed = 0, vl = 1500, position_counter = 0, direction = 1, notch_eff = 0,
        phase1 = false, phase2 = false, regen = false, notch_ge1 = false,
        low_bc_with_regen_flag = false, regen_bc_smooth_seed = 0, regen_bc_target = 0,
        OLD_I = 0, OLD_IF_A = 0, OLD_PHI = 0,
    })
    h.assert_eq(idle.motor_current, 0, "open main circuit has zero armature current")
    h.assert_eq(idle.back_emf, 0, "open main circuit has zero back EMF output")
    h.assert_eq(idle.accel, 0, "open main circuit has zero torque")
    h.assert_eq(idle.W, 0, "open main circuit has zero line power")

    -- At zero speed the back-EMF term vanishes, so the series-current result
    -- has a closed-form value independent of the magnetic curve.
    local standstill = h.physics_tick({
        speed = 0, vl = 1500, position_counter = 8, direction = 1, notch_eff = 4,
        phase1 = true, phase2 = false, regen = false, notch_ge1 = true,
        low_bc_with_regen_flag = false, regen_bc_smooth_seed = 0, regen_bc_target = 0,
        OLD_I = 0, OLD_IF_A = 0, OLD_PHI = 0,
    })
    local expected_i = (1500 / 8) / (0.12 + 0.9710 / 8)
    h.assert_near(standstill.motor_current, expected_i, 1e-9,
        "series standstill current follows V/(motor resistance + group resistance)")
    h.assert_near(standstill.W, 1500 * expected_i, 1e-6,
        "series two-car line power uses one line-current path")

    local function direction_case(speed, direction)
        return h.physics_tick({
            speed = speed, vl = 1500, position_counter = 10, direction = direction, notch_eff = 4,
            phase1 = true, phase2 = false, regen = false, notch_ge1 = true,
            low_bc_with_regen_flag = false, regen_bc_smooth_seed = 0, regen_bc_target = 0,
            OLD_I = 250, OLD_IF_A = 175, OLD_PHI = 0.02,
        })
    end
    local forward = direction_case(8, 1)
    local reverse = direction_case(-8, -1)
    h.assert_near(reverse.motor_current, forward.motor_current, 1e-9,
        "reversing speed and direction preserves armature-current magnitude")
    h.assert_near(reverse.back_emf, forward.back_emf, 1e-9,
        "reversing speed and field preserves back-EMF polarity at the supply")
    h.assert_near(reverse.accel, -forward.accel, 1e-9,
        "reversing direction reverses vehicle acceleration")

    -- In regenerative control, separately excited flux must drive armature
    -- current negative while the per-motor back EMF limiter remains active.
    local braking = h.physics_tick({
        speed = 25, vl = 1500, position_counter = 0, direction = 1, notch_eff = 0,
        phase1 = false, phase2 = true, regen = true, notch_ge1 = false,
        low_bc_with_regen_flag = true, regen_bc_smooth_seed = 0, regen_bc_target = -1,
        OLD_I = 0, OLD_IF_A = 200, OLD_PHI = 0,
    })
    h.assert_true(braking.motor_current < 0, "regenerative control produces negative armature current")
    h.assert_true(math.abs(braking.back_emf) <= 470.000001,
        "regenerative per-motor back EMF stays within the inherited 470V limit")
    h.assert_true(braking.accel < 0, "negative current with positive field produces braking torque")
end
