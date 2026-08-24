-- physics_tick's field-weakening traction row (regen_latch=field_control_latch
-- true, low_bc_with_regen_flag=false): notch 1-3 lets field current track
-- armature current directly (target_i=OLD_IF_A is correct there and left
-- untouched); notch 4+ is a real closed-loop control of armature current, and
-- its target must be POWER_LIMIT_CURRENT (the same "resistance-control
-- current limit" property used elsewhere for current-limited cam advance,
-- SPEC.md §7.3) rather than the unrelated fixed 200A Newton-method seed that
-- main.sw-net's CONST(200) node happened to share. DESIGN_LOG.md #31.


return function(h)
    local function run(notch_eff, ticks)
        local OLD_I, OLD_IF_A, OLD_PHI = 0, 150, 0
        local phys
        for _ = 1, ticks do
            phys = h.physics_tick({
                speed = 15, vl = 1500, position_counter = 0, direction = 1, notch_eff = notch_eff,
                phase1 = false, phase2 = true, regen = true, notch_ge1 = true, low_bc_with_regen_flag = false,
                regen_bc_smooth_seed = 0, regen_bc_target = 0,
                OLD_I = OLD_I, OLD_IF_A = OLD_IF_A, OLD_PHI = OLD_PHI,
            })
            OLD_I, OLD_IF_A, OLD_PHI = phys.OLD_I, phys.OLD_IF_A, phys.OLD_PHI
        end
        return phys
    end

    -- Notch 2 (<=3): external field settles at 70% of armature current, so
    -- the 30% series component and external field form a 100% series curve.
    local low_notch = run(2, 600)
    h.assert_near(low_notch.iF_a, low_notch.motor_current * 0.7, 1e-6,
        "notch<=3: external field settles at 70% of armature current")
    h.assert_true(low_notch.motor_current < 300,
        "notch<=3: settles below POWER_LIMIT_CURRENT, got " .. tostring(low_notch.motor_current))

    -- Notch 5 (>3): real feedback control uses the independent
    -- Field Control Current property, not the cam-advance current property.
    local high_notch = run(5, 600)
    h.assert_near(high_notch.motor_current, 315, 1e-6,
        "notch>3: armature current converges to POWER_LIMIT_CURRENT")
end
