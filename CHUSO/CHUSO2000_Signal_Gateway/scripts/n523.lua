front = 0
back = 0
infos = { {}, {}, {}, {}, {}, {} }
ob = {}

function onTick()
    if not input.getBool(32) then return end
    ch, dt = dec(input.getNumber(32))
    front = dt & 31
    back = (dt >> 5) & 31

    local c = 1
    for i = 1, front do
        ch, dt = dec(input.getNumber(i))
        setinfo(c, ch, dt)
        c = c + 1
    end
    ch, dt = dec(input.getNumber(16))
	local mc=c
    setinfo(c, ch, dt)
    c = c + 1
    for i = 1, back do
        ch, dt = dec(input.getNumber(31 - back + i))
        setinfo(c, ch, dt)
        c = c + 1
    end
    for i = c, 6 do
        infos[i].ext    = false
        infos[i].dclose = false
        infos[i].err    = false
        infos[i].dcut   = false
        infos[i].sos    = false
        infos[i].mcrr   = false
        infos[i].bcrr   = false
        infos[i].bpow   = false
    end

    local o0, o1, o2 = 0, 0, 0
    for i = 1, 6 do
        -- o0 -> 27: mcrr, bcrr
        o0 = o0 | bbit(30-i, infos[i].mcrr) | bbit(22-i, infos[i].bcrr) | bbit(6-i, infos[i].ext)
        -- o1 -> 28: merr, berr, batl, sos
        o1 = o1 | bbit(30-i, infos[i].merr) | bbit(22-i, infos[i].berr) | bbit(14-i, infos[i].batl) | bbit(6-i, infos[i].sos)
        -- o2 -> 29: not dclose, dcut, err, bpow
        o2 = o2 | bbit(30-i, infos[i].dclose) | bbit(22-i, infos[i].dcut) | bbit(14-i, infos[i].err) | bbit(6-i, infos[i].bpow)
    end
    output.setNumber(1, enc(o0))
    output.setNumber(2, enc(o1))
    output.setNumber(3, enc(o2))

    for i = 1, 24 do
        ob[i] = false
    end
    for i = 1, 31 do
        local cmd, dt = dec(input.getNumber(i))
        if cmd == 0x60 then
            for j = 0, 23 do
                ob[j + 1] = (dt & (1 << j)) ~= 0
            end
        end
    end
    for i = 1, 24 do
        output.setBool(i, ob[i])
    end

	if mc>1 then
		output.setBool(31, infos[mc-1].dcut)
	else
		output.setBool(31, false)
	end
	if mc<6 then
		output.setBool(32, infos[mc+1].dcut)
	else
		output.setBool(32, false)
	end
end

function setinfo(c, ch, dt)
    infos[c].ext = true
    if ch >= 0x41 and ch <= 0x43 then
        infos[c].dclose = (dt & (3 << 19)) ~= 0
        infos[c].err = (dt & (1 << 21)) ~= 0
    end
    if ch == 0x4B then
        infos[c].dcut = (dt & (1 << 20)) ~= 0
        infos[c].sos = (dt & (1 << 21)) ~= 0
        infos[c].mcrr = (dt & (1 << 23)) ~= 0
        infos[c].bcrr = (dt & (1 << 22)) ~= 0
    end
    if ch == 0x4A then
        infos[c].bpow = (dt & (1 << 23)) ~= 0
    end
end

function toi(x)
    return math.tointeger(x) or 0
end

function enc(dat)
    local x=('f'):unpack(('I4'):pack(dat))
    return x
end

function dec(fl)
    local i = ('I4'):unpack(('f'):pack(fl))
    return (i >> 24) & 0xFF, i & 0xFFFFFF
end

function bbit(b, e)
    if e then return (1 << b) else return 0 end
end
