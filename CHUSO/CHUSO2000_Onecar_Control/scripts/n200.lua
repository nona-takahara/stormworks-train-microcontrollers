function pk(intv)
	local r = ('f'):unpack(('I4'):pack(intv))
	return r
end

function unpk(fl)
	local r = ('I4'):unpack(('f'):pack(fl))
	return r
end

function gN(i)
    return input.getNumber(i)
end

b={}
function onTick()
	local i1,i2=unpk(gN(1)),unpk(gN(2))
	if i1 ~= 1<<24 then
		table.insert(b,i1)
	end
	if i2 ~= 1<<24 then
		table.insert(b,i2)
	end

    if #b ~= 0 then
        output.setNumber(1,pk(b[1]))
        table.remove(b,1)
    else
        output.setNumber(1,pk(1<<24))
    end
end