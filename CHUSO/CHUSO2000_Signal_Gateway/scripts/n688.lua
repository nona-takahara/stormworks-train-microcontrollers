sB, sN = output.setBool, output.setNumber

function clamp(x, a, b)
	return math.min(math.max(x, a), b)
end

function I(c)
	return ('I3B'):unpack(('f'):pack(input.getNumber(c)))
end

function bit_at(n, i)
	return n >> i & 1 ~= 0
end

function swap_bits(n, a, b, w, k)
	if k then
		return n
	end
	m = (1 << w) - 1
	t = n >> a & m
	n = n ~ (n & m << a) | (n >> b & m) << a
	n = n ~ (n & m << b) | t << b
	return n
end

function b2i(f)
	return f and 1 or 0
end

function onTick()
	ext_mode = input.getBool(1)
	cmn = I(32)
	cars_f, cars_b = cmn & 15, cmn >> 5 & 15

	data_0x42, data_0x48, data_0x49, data_0x4c = 0, 0, 0, nil

	for i = 1, 31 do
		ns = i > 16
		rel_i = 0
		if i <= 15 then
			rel_i = cars_f + 1 - i
		elseif i >= 17 then
			rel_i = cars_b - 31 + i
		end

		cmd_body, cmd_type = I(i)

		if cmd_type == 0x42 then
			data_0x42 = data_0x42 | swap_bits(cmd_body, 0, 2, 2, ns)
		elseif ext_mode then
			if cmd_type == 0x48 then
				data_0x48 = swap_bits(swap_bits(cmd_body, 2, 10, 8, ns), 0, 1, 1, ns)
			elseif cmd_type == 0x49 and cmd_body >> 23 & 1 == 0 and cmd_body >> 19 & 15 == rel_i then
				data_0x49 = swap_bits(cmd_body, 0, 2, 2, ns) & 0x7FFFFF
			elseif cmd_type == 0x4c then
				data_0x4c = cmd_body
			end
		end
	end

	door_open_a, door_close_a = bit_at(data_0x42, 3) or bit_at(data_0x48, 1), bit_at(data_0x42, 2)
	door_open_b, door_close_b = bit_at(data_0x42, 1) or bit_at(data_0x48, 0), bit_at(data_0x42, 0)
	door_update = door_open_a or door_open_b
	door_mode_update = bit_at(data_0x48, 18)
	doorcut_f_update, doorcut_b_update = bit_at(data_0x48, 10), bit_at(data_0x48, 2)
	door_mode, doorcut_f, doorcut_b = data_0x48 >> 19 & 15, data_0x48 >> 11 & 127, data_0x48 >> 3 & 127

	doorcut_sf = clamp(doorcut_f - cars_f * 6, 0, 6)
	doorcut_sb = clamp(doorcut_b - cars_b * 6, 0, 6)

	sB(1, door_mode_update or door_update)
	sB(2, doorcut_f_update or door_update)
	sB(3, doorcut_b_update or door_update)
	sN(1, door_mode)
	sN(2, doorcut_f)
	sN(3, doorcut_b)
	sN(4, doorcut_sf)
	sN(5, doorcut_sb)

	sB(9, door_open_a)
	sB(10, door_close_a)
	sB(11, door_open_b)
	sB(12, door_close_b)
	for i = 0, 11 do
		sB(13 + i, bit_at(data_0x49, i))
	end

	sB(25, data_0x4c ~= nil)
	sN(25, data_0x4c or 0)
end
