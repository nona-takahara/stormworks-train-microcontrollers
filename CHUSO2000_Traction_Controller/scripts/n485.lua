-- VVVF Controller by Nona Takahara
MASS_M_CAR = 35 -- Mg (t)
UNIT_CURRENT_MAX_P = 720 -- A
UNIT_CURRENT_MAX_B = 1200 -- A
REG_BRAKE = false
MOTOR_PER_UNIT = 4 -- Number of motors(REAL) controlled from this microcontroller(SW)
CONST_VF = 0.0256 -- V/f constant V/(km/h)
BOOST = 1.25

MAX_LINE_VOLTAGE = 1.82 -- kV
REFINE_VOLTAGE = 1.70 -- kV
LINE_VOLTAGE_LPF = 0.1
MIN_VOLTAGE_RATIO_P = 0.01
MIN_VOLTAGE_RATIO_B = 0.1

_CONS=false
function TargetCurrent(notch, unitMass, velocity, cv, boost)
    local vfcCurrent, maxCurrent, slipMaxSpdAtMaxC = 0, 0, 100
    local bsk = boost and BOOST or 1
    if notch == 1 then
        vfcCurrent = 0.5
        maxCurrent = 0.5
        slipMaxSpdAtMaxC = 3.6
    elseif notch == 2 then
        if (velocity > 41 and cv == 0) or cv > 41 then
            vfcCurrent = clamp((cv - velocity) / 3.5, -1.543, 1.543)
            maxCurrent = vfcCurrent < 0 and -1.543 or 1.543
            if math.abs(cv - velocity) > 1.0 then _CONS = true end
            if math.abs(cv - velocity) < 0.3 then _CONS = false end
            if not _CONS or cv==0 then vfcCurrent = 0 end
        else
            vfcCurrent = 1.03
            maxCurrent = 1.03
            slipMaxSpdAtMaxC = 24
        end
    elseif notch == 3 then
        vfcCurrent = 1.543
        maxCurrent = 1.543
        slipMaxSpdAtMaxC = 37
    elseif notch >= 4 then
        vfcCurrent = 1.543
        maxCurrent = 1.543
    elseif notch ~= 0 then
        vfcCurrent = math.max(notch, -53 * MASS_M_CAR / unitMass) / 24 * 1.415
        maxCurrent = -clamp(velocity - 0.1, 0, 4.285 * MASS_M_CAR / unitMass)
        if notch == 0 or vfcCurrent > 0 then vfcCurrent = 0; maxCurrent = 0 end
    end

    return vfcCurrent * unitMass * bsk, maxCurrent * unitMass * bsk, slipMaxSpdAtMaxC / bsk^2
end

function transition(a, b, c, d)
    d = d or c
    a = math.min(a + c, math.max(a - d, b))
    if a ~= a then a = 0 end
    return a
end

function clamp(a, b, c)
    return math.min(math.max(a, b), c)
end

function sign(x)
    if x < 0 then return -1 end
    if x > 0 then return 1 end
    return 0
end

MIN_NUM = 0.0009765625
POWER_EFFECT = 11
BRAKE_EFFECT = 12
_PanV = 0
_Watchdog = false
_MI = 0
function CalculateCurrent(velocity, panV, notch, unitM, cv, boost)
    local motorV = math.max(math.min(velocity * CONST_VF, panV / math.sqrt(2)), MIN_NUM) -- line voltage of motor
    if notch <= 0 then
        if motorV <= (MIN_VOLTAGE_RATIO_B * panV) then
            notch = 0
            DISABLE_RB = true
        end
        motorV = math.max(motorV, MIN_VOLTAGE_RATIO_B * panV)
    else
        motorV = math.max(motorV, MIN_VOLTAGE_RATIO_P * panV)
    end
    local vfcI, maxI, slipMaxSpdAtMaxI = TargetCurrent(notch, unitM, velocity, cv, boost)

    local min = math.min
    if vfcI < 0 then min = math.max end

    local tgMI = min(
        maxI / math.max(velocity / math.max(slipMaxSpdAtMaxI, MIN_NUM), 1), -- limit: slip, power
        vfcI * velocity * CONST_VF / motorV -- constant power
    )
    if vfcI == 0 then tgMI = 0 end
    _MI = transition(_MI, tgMI, unitM / MASS_M_CAR)

    -- refine rev
    local i_pRevMaxI = -UNIT_CURRENT_MAX_B *
        clamp((MAX_LINE_VOLTAGE - panV) / math.max(MAX_LINE_VOLTAGE - REFINE_VOLTAGE, MIN_NUM), 0, 1)
    local maxRevMI = panV * i_pRevMaxI / (MOTOR_PER_UNIT * math.sqrt(3) * motorV)
    local resI = 0

    if REG_BRAKE then
        resI = math.max(maxRevMI - _MI, 0)
    else
        _MI = math.max(maxRevMI, _MI)
    end

    local trq = MOTOR_PER_UNIT * math.sqrt(3) * motorV * _MI / (MASS_M_CAR * velocity)
    if trq >= 0 then
        trq = trq * POWER_EFFECT
    else
        trq = trq * BRAKE_EFFECT
    end
    local panI = (_MI - resI) * MOTOR_PER_UNIT * math.sqrt(3) * motorV / math.max(panV, MIN_NUM)

    return trq / 3.6, panI, _MI, resI
end

DISABLE_RB = true
function onTick()
    _Watchdog = not _Watchdog

    local velocity = input.getNumber(1) * 3.6 -- km/h
    local panV = input.getNumber(2) / 1000 -- kV
    local pN = input.getNumber(3) -- 0-5
    local bN = input.getNumber(4) -- 0-31
    local direction = input.getNumber(5)
    local cv = input.getNumber(6) * 3.6 -- constant speed km/h
    local unitCar = input.getNumber(30) + 1 -- Mg (t)
    local maxlackBrk = input.getNumber(31)
    local eb = input.getBool(1)
    local boost = input.getBool(2)
    local disable_rb = input.getBool(3) or DISABLE_RB
    local is_M_car = input.getBool(4)

    local elec_bN = bN
    local trq, panI, _MI, resI, btrq, air_btrq, lack_btrq = 0, 0, 0, 0, 0, 0, 0

    if bN >= 32 or eb then
        bN = input.getNumber(7)*28.8; pN = 0; disable_rb = true
    end

    if is_M_car then
        if (direction == 0) or ((sign(velocity) ~= sign(direction)) and (math.abs(velocity) > 3)) then
            pN = 0
        end
        if (direction == 0) or (sign(velocity) ~= sign(direction)) then
            disable_rb = true
        end
        velocity = math.max(math.abs(velocity), MIN_NUM)
        if pN~=0 then
            DISABLE_RB = false
        end

        -- voltage safeguard
        if panV < 1.150 then
            pN = 0
        end
        if panV < 1.050 then
            elec_bN = 0
        end

        panV = panV * LINE_VOLTAGE_LPF + _PanV * (1 - LINE_VOLTAGE_LPF)
        _PanV = panV

        if bN > 0 then pN = 0 end
        if disable_rb then elec_bN = 0 end

        trq, panI, _MI, resI = CalculateCurrent(
            velocity, panV, pN - elec_bN, MASS_M_CAR * unitCar, cv, boost
        )

        if disable_rb then unitCar = 1; maxlackBrk = 0 end

        btrq = ((bN / 8.0) / 3.6) * unitCar
        air_btrq = math.max(btrq + math.min(trq, 0), 0)
        lack_btrq = math.max(air_btrq - (maxlackBrk * unitCar), 0)
        if disable_rb then lack_btrq = btrq end

        output.setNumber(30, 0)
        output.setNumber(31, 0)
        output.setBool(20, (elec_bN ~= 0) and (trq < 0))
    else
        unitCar = 1
        DISABLE_RB = false
        panV = input.getNumber(23) / 1000
        panI = input.getNumber(29)
        _MI = input.getNumber(24)
        lack_btrq = (bN / 8.0) / 3.6
        if (input.getNumber(15) == 1911) and input.getBool(16) and (not disable_rb) then
            lack_btrq = input.getNumber(25)
        end
        output.setNumber(30, input.getNumber(8))
        output.setNumber(31, input.getNumber(9))
        output.setBool(20, input.getBool(20))
    end

    output.setBool(16, (not disable_rb) and (bN ~= 0) and (trq < 0))
    output.setBool(17, _Watchdog)
    output.setBool(18, trq ~= 0)
    output.setBool(19, resI > 0)

    output.setNumber(15, 1911)
    if unitCar ~= 1 then
        output.setNumber(25,(air_btrq - lack_btrq) / (unitCar - 1))
    else
        output.setNumber(25, 0)
    end
    output.setNumber(23, panV * 1000)
    output.setNumber(29, panI) -- line current
    output.setNumber(24, _MI) -- current per motor
    output.setNumber(2, trq * direction) -- torque: almost m/s^2
    output.setNumber(1, lack_btrq)
end