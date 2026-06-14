-- Constants
K=12.16
Kmu=0.00029
MOT_RES=0.07
Ks=0.85
PHIs=150

MOT_CTRL=4

GEAR_RATIO=5.31
WHEEL_R=0.86/2
WEIGHT=35*1000
-- End

function calc_phi(iF)
    return iF*Kmu*Ks*PHIs/(Ks*math.abs(iF)+PHIs)
end

function deriv_phi(iF)
    return Kmu*Ks*PHIs*PHIs/((Ks*math.abs(iF)+PHIs)*(Ks*math.abs(iF)+PHIs))
end

function calc_iF(pF, ia, iF_a)
    return ia * pF + iF_a
end

function deriv_iF(pF)
    return pF
end

function calc_ia(ia, Vt, n, RpN, pF, iF_a)
    return K*calc_phi(calc_iF(pF,ia,iF_a))*n - Vt + (MOT_RES + RpN)*ia
end

function deriv_ia(ia, Vt, n, RpN, pF, iF_a)
    return K*deriv_phi(calc_iF(pF,ia,iF_a))*deriv_iF(pF)*n + MOT_RES + RpN
end

function calc_current_phi(Vt, n, RpN, pF, iF_a)
    local i = input.getNumber(6)

    for _ = 1, 5 do
        local ndf = deriv_ia(i, Vt, n, RpN, pF, iF_a)
        if math.abs(ndf)>=0.000001 then
            i = i - calc_ia(i, Vt, n, RpN, pF, iF_a)/ndf
        else
            if ndf > 0 then
                i = i - calc_ia(i, Vt, n, RpN, pF, iF_a)
            elseif ndf < 0 then
                i = i + calc_ia(i, Vt, n, RpN, pF, iF_a)
            end
        end
    end
    return i, calc_phi(calc_iF(pF,i,iF_a))
end

SR={ 7.428,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334,     0,2.568,1.734,1.218,0.7570,0.4110,0.1334}
PR={     0,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334, 3.714,2.568,1.734,1.218,0.7570,0.4110,0.1334}

OLD_I = 0
OLD_IF_A = 0
OLD_PHI = 0

function onTick()
    local rpm=input.getNumber(1) * 9.55 * GEAR_RATIO/WHEEL_R
    local vl=input.getNumber(2)
    local notch=input.getNumber(3)+1
    local direction=input.getNumber(4)
    local res=100000
    local srsmtr=4
    local iF_a=150
    local target_i = input.getNumber(6)

    if (not input.getBool(1)) and (not input.getBool(2)) then vl=0 end
    if input.getBool(1) then srsmtr=8 end
    if input.getBool(2) and notch==1 then srsmtr=4 end

    if input.getBool(3) then
        if input.getBool(5) then
            local oldtrq = direction * (MOT_CTRL * 9.55 * K * OLD_PHI * OLD_I * GEAR_RATIO * 0.99 / WHEEL_R / WEIGHT)
            iF_a = OLD_IF_A + (oldtrq - input.getNumber(7))*20
            iF_a = iF_a * math.min(1,(470/(K*math.abs(rpm)))/calc_phi(iF_a+OLD_I*0.15))
        else
            if input.getBool(4) and input.getNumber(5)<=3 then target_i = OLD_IF_A end
            if not input.getBool(4) then target_i = 0 end

            if target_i == 0 then target_i = math.max(math.min(0,OLD_I+20),OLD_I-20) end
            iF_a = OLD_IF_A + (OLD_I - target_i)*0.1
        end
    else
        target_i = OLD_IF_A
        if input.getNumber(5)==0 then target_i = 0 end
        iF_a = OLD_IF_A + (OLD_I - target_i)*0.1
        if input.getNumber(5)~=0 and iF_a > 180 then iF_a = 180 end
    end
    if srsmtr==8 then res=SR[notch] end
    if srsmtr==4 then res=PR[notch] end
    
    if iF_a < 20 then iF_a = 20 elseif iF_a > 500 then iF_a = 500 end

    local i, phi = calc_current_phi(vl/srsmtr, rpm, res/srsmtr, direction*0.2, iF_a * direction)
    if vl==0 then i=0; phi=0 end
    OLD_IF_A = iF_a
    OLD_I = i
    OLD_PHI = phi
    local trqN = 9.55 * K * phi * i
    output.setNumber(1, i)
    output.setNumber(2, K * phi * rpm)
    output.setNumber(3, MOT_CTRL * trqN * GEAR_RATIO * 0.99 / WHEEL_R / WEIGHT)
    output.setNumber(4, vl * i * (MOT_CTRL/srsmtr) * 2)
    output.setNumber(5, notch-1)
    output.setNumber(6, iF_a)
	local bcT = math.min(direction*MOT_CTRL*trqN*GEAR_RATIO/WHEEL_R/WEIGHT,0)-input.getNumber(8)
	if bcT < 0.01 and i < 0 then
		bcT = 0
	end
	output.setNumber(7, bcT)
end