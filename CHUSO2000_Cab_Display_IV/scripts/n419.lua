bound = false--property.getBool("Cab bound")
info0 = 0
info1 = 0
info2 = 0
carcnt = 1

function onTick()
    info0 = unpk(input.getNumber(27))
    info1 = unpk(input.getNumber(28))
    info2 = unpk(input.getNumber(29))
    carcnt = input.getNumber(31) + input.getNumber(32) + 1
	bound = input.getBool(1)
end

function onDraw()
    S = screen
    C = S.setColor
    R = S.drawRectF
    C(0, 0, 0)
    R(70, 3, 11, 5)
    R(86, 3, 3, 5)
    R(90, 3, 3, 5)
    C(25, 25, 25)
    R(68, 1, 27, 1)
    R(68, 1, 1, 30)
    R(68, 30, 27, 1)
    R(94, 1, 1, 30)

    C(30, 30, 30)
    R(79, 9, 1, 4)
    P(80, 10)
    R(78, 12, 3, 1)             --up
    R(89, 9, 1, 4)
    P(90, 11)
    R(88, 9, 3, 1)              --down

    R(76, 14, 16, 1)
    R(75, 15, 18, 2)

    R(70, 17, 1, 4)
    P(71, 18)
    R(72, 17, 1, 4)
    R(75, 19, 18, 1)
    R(70, 22, 1, 3)
    P(71, 22)
    P(71, 24)
    P(72, 23)
    R(75, 23, 18, 1)
    R(70, 26, 1, 4)
    P(71, 26)
    P(71, 28)
    P(72, 27)
    R(75, 27, 18, 1)

    for i = 1, 6 do
        local CE = (info0 & (1 << (i - 1))) ~= 0
        local DClose = CE and ((info2 & (1 << (i + 23))) ~= 0)
        local DC = CE and ((info2 & (1 << (i + 15))) ~= 0)
        local Me = CE and ((info1 & (1 << (i + 23))) ~= 0)
        local Mc = CE and ((info0 & (1 << (i + 23))) ~= 0) or ((info0 & (1 << (i + 15))) ~= 0)
        local PNr = CE and ((info2 & (1 << (i + 7))) ~= 0)
        local PNg = PNr and ((info1 & (1 << (i - 1))) ~= 0) and ((info1 & (1 << (i + 7))) == 0) and ((info1 & (1 << (i + 15))) == 0) and ((info1 & (1 << (i + 23))) == 0)
        local x
		if bound then
			x=73+(7-i)*3 -- front is up bound
		else
			x=73+i*3 --front is down bound
		end
        C(30, 30, 30)
        R(x, 18, 1, 3)
        R(x, 22, 1, 3)
        R(x, 26, 1, 3)

        C(DClose and 255 or 0, CE and 160 or 0, 0)
        P(x, 15)

        if Me then C(255, 0, 0) elseif Mc then C(255, 50, 0) else C(0, 0, 0) end
        P(x, 19)

        C(DC and 255 or 0, 0, 0)
        P(x, 23)

        if PNg then C(255, 50, 0) elseif PNr then C(255, 0, 0) else C(0, 0, 0) end
        P(x, 27)
    end
end

function P(x, y) R(x, y, 1, 1) end

function toi(x)
    return math.tointeger(x) or 0
end

function enc(ch, dat)
    return ('f'):unpack(('I4'):pack(toi(ch) << 24|toi(dat) & 0xFFFFFF))
end

function dec(fl)
    local i = ('I4'):unpack(('f'):pack(fl))
    return (i >> 24) & 0xFF, i & 0xFFFFFF
end

function unpk(fl)
    local i = ('I4'):unpack(('f'):pack(fl))
    return i
end

function numberToBinStr(x)
	ret=""
	while x~=1 and x~=0 do
		ret=tostring(x%2)..ret
		x=math.modf(x/2)
	end
	ret=tostring(x)..ret
	return ret
end
