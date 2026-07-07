EXT_ID = tonumber(property.getText("NITS Ext. ID"),16)
curB, oldB, riseB, refB, curN, oldN, refN = {}, {}, {}, {}, {}, {}, {}
ext2b, ext2f, extlast, logb, logf = {}, {}, 0, {}, {}
toi = math.floor

function bit(exp, pos) return (exp and 1 or 0) << pos end

function bit_arr(ar, be, en)
	local r = 0
	for i = be, en do
		r = r << 1|(ar[i] and 1 or 0)
	end
	return r
end

function shift(val, pos, len) return (toi(val) & toi(2 ^ len - 1)) << pos end

function arr_or(ar, be, en)
	for i = be, en do
		if ar[i] then
			return true
		end
	end
	return false
end

function arr_cls(ar, be, en)
	for i = be, en do
		ar[i] = false
	end
end

function bit_ex(dat, i1, i2)
	local t1, t2 = dat & (1 << i1), dat & (1 << i2)
	return (dat ~ t1 ~ t2)|bit(t1 ~= 0, i2)|bit(t2 ~= 0, i1)
end

function pk(intv)
	local r = ('f'):unpack(('I4'):pack(intv))
	return r
end

function unpk(fl)
	local r = ('I4'):unpack(('f'):pack(fl))
	return r
end

function push_ext(back, front)
	extlast = extlast + 1
	ext2b[extlast] = back
	ext2f[extlast] = front
end

function pop_ext()
	local d1, d2 = ext2b[1] or 0, ext2f[1] or 0
	for i = 1, extlast - 1 do
		ext2b[i] = ext2b[i + 1] or 0
		ext2f[i] = ext2f[i + 1] or 0
	end
	ext2b[extlast] = 0
	ext2f[extlast] = 0
	extlast = extlast - 1
	return d1, d2 or d1
end

function make_nits(force41)
	local b41_42, b43 = 0, 0
	-- deny
	if curB[6] then
		ext2b, ext2f = {}, {}
		return 0x47 << 24, 0x47 << 24, false
	end

	-- interrapt
	if curB[7] then
		return unpk(input.getNumber(6)), unpk(input.getNumber(7)), false
	end

	-- check ext. mode
	if refN[8] or refB[32] then
		refN[8] = false
		refB[32] = false
		return 0x47 << 24|EXT_ID, 0x47 << 24|EXT_ID, false
	end

	b43 = bit_arr(curB, 1, 5) << 19
	b41_42 = b43|bit_arr(riseB, 10, 15) << 13

	-- 0x41
	if curB[32] and (force41 or (arr_or(refB, 16, 18) or arr_or(refN, 1, 3))) then
		local p = (0x41 << 24)|b41_42
		p = p|bit(curB[18], 12)|bit(curB[16], 9)|bit(curB[17], 8)
		p = p|shift(curN[3], 10, 2)|shift(curN[2], 5, 3)|shift(curN[1], 0, 5)

		arr_cls(riseB, 1, 5)
		arr_cls(riseB, 10, 15)
		arr_cls(refB, 16, 18)
		arr_cls(refN, 1, 3)
		return p, bit_ex(bit_ex(p, 20, 19), 9, 8), true
	end

	-- 0x42
	if arr_or(riseB, 10, 15) or arr_or(riseB, 19, 30) then
		local p = (0x42 << 24)|b41_42|bit_arr(riseB, 19, 30)
		arr_cls(riseB, 1, 5)
		arr_cls(riseB, 10, 15)
		arr_cls(riseB, 19, 30)
		return p, bit_ex(bit_ex(bit_ex(p, 20, 19), 3, 1), 2, 0), false
	end

	-- ext.
	if extlast >= 1 then
		local e1,e2=pop_ext()
		return e1, e2, false
	end

	if curB[9] then
		return unpk(input.getNumber(6)), unpk(input.getNumber(7)), false
	end

	-- 0x43
	b43 = 0x43 << 24|b43|shift(curN[5], 9, 10)|shift(curN[4] / 2, 0, 9)
	return b43, bit_ex(b43, 20, 19), false
end

n41time = 0
watchdog = false
function onTick()
	watchdog = not watchdog
	n41time = n41time > 0 and n41time - 1 or 0
	for i = 1, 32 do
		oldB[i] = curB[i]
		curB[i] = input.getBool(i)
		if oldB[i] == false and curB[i] == true then
			riseB[i] = true
			refB[i] = true
		else
			riseB[i] = riseB[i] or false
			if oldB[i] == true and curB[i] == false then
				refB[i] = true
			else
				refB[i] = refB[i] or false
			end
		end
	end

	for i = 1, 9 do
		oldN[i] = curN[i]
		curN[i] = input.getNumber(i)
		if oldN[i] ~= curN[i] then
			refN[i] = true
		else
			refN[i] = refN[i] or false
		end
	end

	if curB[8] then -- push
		push_ext(unpk(curN[6]), unpk(curN[7]))
	end

	local n1, n2, f = make_nits(n41time <= 0)
	if f then n41time = 60 end
	logb[(n1 >> 24) & 0xff] = unpk(pk(n1))
	logf[(n2 >> 24) & 0xff] = unpk(pk(n2))
	logl = unpk(pk(n1))

	output.setNumber(1, pk(n1))
	output.setNumber(2, pk(n2))
	output.setNumber(3, extlast)
	output.setBool(1, watchdog)
end

function onDraw()
	screen.drawText(0, 0, string.format("%x", logb[0x41] or 0))
	screen.drawText(0, 8, string.format("%x", logb[0x42] or 0))
	screen.drawText(0, 16, string.format("%x", logb[0x60] or 0))
	screen.drawText(0, 24, string.format("%x", logl or 0))
end
