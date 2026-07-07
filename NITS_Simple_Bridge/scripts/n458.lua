_p=property
sig,riseB,curB,oldB,curN,oldN,chgN={},{},{},{},{},{},{}
toi = math.floor
_pg=function(l)return toi(_p.getNumber(l))end

function pk(intv)
	local r = ('f'):unpack(('I4'):pack(intv))
	return r
end

function unpk(fl)
	local r = ('I4'):unpack(('f'):pack(fl))
	return r
end

MODE={}
for i=1,8 do
	MODE[i]=_pg(("M%d/N%d Mode"):format(i,i+8))
	sig[i]={b=0,f=0,up=false}
end

interval = 0
channel = 0
watchdog = false
function onTick()
	watchdog = not watchdog
	for i=1,16 do
		oldN[i] = curN[i]
		curN[i] = input.getNumber(i)
		chgN[i] = oldN[i] ~= curN[i]

		oldB[i] = curB[i]
		curB[i] = input.getBool(i)
		riseB[i] = (not oldB[i]) and curB[i]
	end
	for i=1,8 do
		if curB[i] or curB[i+8] then
			local b,f=curN[i],curN[i+8]
			if (MODE[i] & 1)==0 then
				f=b
				chgN[i+8]=false
			end
			if (MODE[i] & 2)==0 then
				b=toi(b);f=toi(f)
			else
				b=unpk(b);f=unpk(f)
			end
			if chgN[i] or chgN[i+8] or riseB[i] then
				sig[i].b = b
				sig[i].f = f
				sig[i].up=true
			end
		end
	end

	local db,df,cmd=0,0,0

	interval=interval-1
	if interval<=0 then
		while channel<8 do
			channel=channel+1
			if sig[channel].up then
				db=sig[channel].b
				df=sig[channel].f
				cmd=0x48-1+channel
				sig[channel].up=false
				break
			end
		end

		if channel>=8 then
			interval=2
			channel=0
		end
	end


	if cmd~=0 then
		output.setNumber(6, pk((toi(cmd) << 24) | (db & 0xffffff)))
		output.setNumber(7, pk((toi(cmd) << 24) | (df & 0xffffff)))
	else
		output.setNumber(6, 0)
		output.setNumber(7, 0)
	end
	output.setBool(14, cmd~=0)
end
