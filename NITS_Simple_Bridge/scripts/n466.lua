function toi(x)
	return math.tointeger(math.floor(x)) or 0
end

ID = tonumber(property.getText("NITS Ext. ID"),16)

function gbit(val, dg)
	return ((val >> dg) & 1) == 1
end

function pk(intv)
	local r=('f'):unpack(('I4'):pack(intv))
	return r
end

function unpk(fl)
	local r=('I4'):unpack(('f'):pack(fl))
	return r
end

function bit_exch(dat, i1, i2)
    local t1 = dat & (toi(1) << i1)
    local t2 = dat & (toi(1) << i2)

    return (dat ~ t1 ~ t2) | bbit(i2, t1~=0) | bbit(i1, t2~=0)
end

op = {}
data_s4x = {}
_Watchdog = false
function onTick()
	_Watchdog = not _Watchdog
	output.setBool(15, _Watchdog)

	local s41, s4x, dt, ch
	s41 = 0
	s4x = false

	for i = 1, 32 do
		op[i] = false
	end

	output.setBool(6, false)
	output.setBool(7, false)
	output.setBool(8, false)

	dt = unpk(input.getNumber(32))
	local front_car = dt & 31
	local last_car = (dt >> 5) & 31

	for i = front_car+1, 15 do
		data_s4x[i] = 0
	end
	for i = 17, 31-last_car do
		data_s4x[i] = 0
	end

	for i = 1, 31 do
		dt = unpk(input.getNumber(i))
		ch = (dt >> 24) & 0xff

		if ch == 0x41 then
			s41 = i
			for j = 10, 15 do
				op[j] = op[j] or gbit(dt, 28 - j)
			end
		end
		if ch == 0x42 then
			for j = 10, 15 do
				op[j] = op[j] or gbit(dt, 28 - j)
			end
			for j = 19, 26 do
				op[j] = op[j] or gbit(dt, 30 - j)
			end
			if i <= 16 then
				op[27] = op[27] or gbit(dt, 3)
				op[28] = op[28] or gbit(dt, 2)
				op[29] = op[29] or gbit(dt, 1)
				op[30] = op[30] or gbit(dt, 0)
			else
				op[27] = op[27] or gbit(dt, 1)
				op[28] = op[28] or gbit(dt, 0)
				op[29] = op[29] or gbit(dt, 3)
				op[30] = op[30] or gbit(dt, 2)
			end
		end
		if ch >= 0x41 and ch <= 0x43 then
			s4x = true
			data_s4x[i] = dt
		end

		if ch == 0x47 then
			if (dt & 0xffffff) == ID then
				output.setBool(8, true)
			else
				if (dt & 0xffffff) ~= 0 then
					output.setBool(6, true)
				end
				output.setBool(7, true)
			end
		end
	end

	if s41 ~= 0 then
		dt = unpk(input.getNumber(s41))
		output.setNumber(1, dt & 31)
		output.setNumber(2, (dt >> 5) & 7)
		output.setNumber(3, (dt >> 10) & 3)
		output.setBool(18, gbit(dt, 12))
		if s41 <= 16 then
			output.setBool(16, gbit(dt, 9))
			output.setBool(17, gbit(dt, 8))
		else
			output.setBool(16, gbit(dt, 8))
			output.setBool(17, gbit(dt, 9))
		end
		output.setBool(9, true)
	else
		output.setBool(9, false)
	end


	for i = 1, 32 do
		dt=data_s4x[i] or 0
		op[1] = op[1] or gbit(dt, 23)
		if i ~= 16 then op[2] = op[2] or gbit(dt, 22) end
		op[3] = op[3] or gbit(dt, 21)
		if i <= 16 then
			op[4]=op[4] or gbit(dt, 20); op[5]=op[5] or gbit(dt, 19)
		else
			op[5]=op[5] or gbit(dt, 20); op[4]=op[4] or gbit(dt, 19)
		end
	end

	for j = 1, 5 do
		output.setBool(j, op[j])
	end
	for j = 10, 30 do
		output.setBool(j, op[j])
	end
	output.setBool(9, s4x)

	output.setNumber(4, front_car)
	output.setNumber(5, last_car)
	output.setNumber(6, front_car + last_car + 1)
end
