gB, sB, sN = input.getBool, output.setBool, output.setNumber
function gI(c)
	return math.floor(input.getNumber(c))
end

function onTick()
	for i = 9, 24 do
		sB(i, gB(i))
	end
	data = {}
	for i = 1, 8 do
		data[i] = gI(i)
	end

	recv_0x4c, data_0x4c = gB(25), gI(25)
	is_swap, addr1, val = data_0x4c >> 23 & 1 ~= 0, data_0x4c >> 20 & 7, data_0x4c & 0xFFFFF
	addr2 = val & 7

	for i = 0, 7 do
		write_val = nil
		if recv_0x4c and not is_swap and i == addr1 then
			write_val = val
		elseif recv_0x4c and is_swap and i == addr1 then
			write_val = data[addr2 + 1]
		elseif recv_0x4c and is_swap and i == addr2 then
			write_val = data[addr1 + 1]
		end
		sB(1 + i, write_val ~= nil)
		sN(1 + i, write_val or 0)
	end
end
