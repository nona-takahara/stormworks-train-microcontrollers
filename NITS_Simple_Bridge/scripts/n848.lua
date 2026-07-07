function unpk(fl)
	local r=('I4'):unpack(('f'):pack(fl))
	return r
end

_pg=function(l)return math.floor(property.getNumber(l))end
MODE={}
for i=1,8 do
	MODE[i]=_pg(("M%d/N%d Mode"):format(i,i+8))
end

opN={}
opB={}
function onTick()
	for i=1,8 do
		opN[i]=0
		opB[i]=false
	end

	for i=1,31 do
		local f,o,c
		f=input.getNumber(i)
		o=unpk(f)
		c=((o >> 24) & 0xff)-(0x48)+1

		if c>=1 and c<=8 then
			if (MODE[c] & 2)==0 then
				opN[c]=(o & 0xffffff) * 1.0
			else
				opN[c]=f --binary
			end
			opB[c]=true
		end
	end

	for i=1,8 do
		output.setNumber(i, opN[i])
		output.setBool(i, opB[i])
	end
end

