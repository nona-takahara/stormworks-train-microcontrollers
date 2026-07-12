-- Numeric regression: physics_tick() must match the UNTOUCHED
-- CHUSO1800_Traction_Controller/scripts/n409.lua bit-for-bit (within
-- floating point epsilon), across several fixed input patterns and ~200
-- ticks each (long enough for OLD_I/OLD_IF_A/OLD_PHI to settle).


local function locate_n409()
    local this_file = debug.getinfo(1, "S").source:sub(2)
    local this_dir = this_file:match("(.*/)") or "./"
    return this_dir .. "../../../CHUSO1800_Traction_Controller/scripts/n409.lua"
end

return function(h)
    local in_numbers, in_bools = {}, {}
    local out_numbers, out_bools = {}, {}

    input = {
        getNumber = function(ch) return in_numbers[ch] or 0 end,
        getBool = function(ch) return in_bools[ch] or false end,
    }
    output = {
        setNumber = function(ch, v) out_numbers[ch] = v end,
        setBool = function(ch, v) out_bools[ch] = v end,
    }

    local n409_path = locate_n409()
    local chunk = assert(loadfile(n409_path), "could not load " .. n409_path)
    chunk()
    h.assert_true(type(onTick) == "function", "n409.lua defines global onTick")

    local scenarios = {
        {
            name = "idle",
            speed = 0, vl = 1500, cam = 0, direction = 0, notch_eff = 0,
            phase1 = false, phase2 = false, regen = false, notch_ge1 = false,
            low_bc = false, regen_bc_smooth_seed = 0, regen_bc_target = 0,
        },
        {
            name = "series_notch4",
            speed = 5, vl = 1500, cam = 8, direction = 1, notch_eff = 4,
            phase1 = true, phase2 = false, regen = false, notch_ge1 = true,
            low_bc = false, regen_bc_smooth_seed = 0, regen_bc_target = 0,
        },
        {
            name = "parallel_notch5_cam14",
            speed = 12, vl = 1500, cam = 14, direction = 1, notch_eff = 5,
            phase1 = false, phase2 = true, regen = false, notch_ge1 = true,
            low_bc = false, regen_bc_smooth_seed = 0, regen_bc_target = 0,
        },
        {
            name = "regen_braking",
            speed = 15, vl = 1500, cam = 1, direction = 1, notch_eff = 0,
            phase1 = false, phase2 = false, regen = true, notch_ge1 = false,
            low_bc = true, regen_bc_smooth_seed = -0.05, regen_bc_target = -0.1,
        },
        {
            name = "reverse_series",
            speed = -3, vl = 1500, cam = 5, direction = -1, notch_eff = 3,
            phase1 = true, phase2 = false, regen = false, notch_ge1 = true,
            low_bc = false, regen_bc_smooth_seed = 0, regen_bc_target = 0,
        },
    }

    for _, sc in ipairs(scenarios) do
        OLD_I = 0
        OLD_IF_A = 0
        OLD_PHI = 0
        local core_OLD_I, core_OLD_IF_A, core_OLD_PHI = 0, 0, 0

        for tick = 1, 200 do
            in_numbers = {
                [1] = sc.speed, [2] = sc.vl, [3] = sc.cam, [4] = sc.direction,
                [5] = sc.notch_eff, [6] = 200, [7] = sc.regen_bc_smooth_seed,
                [8] = sc.regen_bc_target,
            }
            in_bools = {
                [1] = sc.phase1, [2] = sc.phase2, [3] = sc.regen,
                [4] = sc.notch_ge1, [5] = sc.low_bc,
            }
            out_numbers, out_bools = {}, {}

            onTick()

            local phys = h.physics_tick({
                speed = sc.speed, vl = sc.vl, position_counter = sc.cam,
                direction = sc.direction, notch_eff = sc.notch_eff,
                phase1 = sc.phase1, phase2 = sc.phase2, regen = sc.regen,
                notch_ge1 = sc.notch_ge1, low_bc_with_regen_flag = sc.low_bc,
                regen_bc_smooth_seed = sc.regen_bc_smooth_seed,
                regen_bc_target = sc.regen_bc_target,
                OLD_I = core_OLD_I, OLD_IF_A = core_OLD_IF_A, OLD_PHI = core_OLD_PHI,
            })

            local tag = sc.name .. " tick " .. tick
            h.assert_near(phys.motor_current, out_numbers[1], 1e-9, tag .. " ch1 motor_current")
            h.assert_near(phys.back_emf, out_numbers[2], 1e-9, tag .. " ch2 back_emf")
            h.assert_near(phys.accel, out_numbers[3], 1e-9, tag .. " ch3 accel")
            h.assert_near(phys.W, out_numbers[4], 1e-9, tag .. " ch4 W")
            h.assert_near(phys.iF_a, out_numbers[6], 1e-9, tag .. " ch6 iF_a")
            h.assert_near(phys.bcT, out_numbers[7], 1e-9, tag .. " ch7 bcT")

            core_OLD_I, core_OLD_IF_A, core_OLD_PHI = phys.OLD_I, phys.OLD_IF_A, phys.OLD_PHI
        end
    end
end
