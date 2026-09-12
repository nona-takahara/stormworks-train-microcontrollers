_p=property
EXT_ID = tonumber(_p.getText("NITS Ext. ID"),16)
curB, oldB, riseB, refB, curN, oldN, refN = {}, {}, {}, {}, {}, {}, {}
ext2b, ext2f, extlast, logb, logf = {}, {}, 0, {}, {}
toi = math.floor;_pg=function(l)return toi(_p.getNumber(l))end

function bit(exp, pos) return (exp and 1 or 0) << pos end
function bbit(b, e)
    if e then return (1 << b) else return 0 end
end

function ub(exp,update,pos)
	if update then
		if exp then return shift(2,pos,2) else return shift(1,pos,2) end
	end
	return 0
end

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

function bit_ex_ar(dat, l)
	local p=dat
	for i,d in ipairs(l) do
		p=bit_ex(p,d[1],d[2])
	end
	return p
end

function pk(intv)
	local r = ('f'):unpack(('I4'):pack(intv))
	return r
end

function unpk(fl)
	local r = ('I4'):unpack(('f'):pack(fl))
	return r
end

EXTRA_BRAKE=toi(0)
PAN_FRONT=_pg("Front Pantograph")
PAN_BACK=_pg("Rear Pantograph")
DOOR=_pg("Side doors")
AXLE=_pg("Powered Axle")
CAB=_pg("Cab")
DDC=_pg("Double Decker") -- no implemention

count4b = 0
watchdog = false
function onTick()
	local df,db,cmd,mode=0,0,0,0
	watchdog = not watchdog
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

		oldN[i] = curN[i]
		curN[i] = input.getNumber(i)
		if oldN[i] ~= curN[i] then
			refN[i] = true
		else
			refN[i] = refN[i] or false
		end
	end
	
	if (unpk(curN[2])>>24)~=0 then refN[2]=false end

	if refB[23] then cmd=0x4a end
	if refB[7] or refB[9] then cmd=0x49 end
	if refN[1] then cmd=0x4b end
	if riseB[10] or riseB[11] or refB[12] or refB[13] then cmd=0x48 end
	if refN[2] then cmd=0x4c end
	if arr_or(refB, 1, 6) or arr_or(refB, 14, 15) or refB[22] then cmd=0x60 end
	extlast=extlast+1
	if extlast>10 and cmd==0 then cmd=0x4b;extlast=0 end

	if cmd==0x48 then
		mode=13
		local car_count=math.floor(math.max(curN[4]-1,0)*6)&127
		df = bit(curB[11],1) | bit(curB[10],0)
		db = bit_ex(df, 0, 1)

		if curB[12] or refB[12] then
			if not curB[12] then
				car_count=0
			end
			if refB[12] then
				df=df|(1<<2)
				db=db|(1<<10)
				refB[12]=false
			end
			df=df|car_count<<3
			db=db|car_count<<11
		elseif curB[13] or refB[13] then
			if not curB[13] then
				car_count=0
			end
			if refB[13] then
				db=db|(1<<2)
				df=df|(1<<10)
				refB[13]=false
			end
			db=db|car_count<<3
			df=df|car_count<<11
		else
			db=db|math.floor(curN[5])<<19|math.floor(curN[7])<<11|math.floor(curN[6])<<3
			df=df|math.floor(curN[5])<<19|math.floor(curN[6])<<11|math.floor(curN[7])<<3
		end

		riseB[10] = false
		riseB[11] = false
	end
	if cmd==0x49 then
		mode=13
		if refB[7] then
			df = (0x11<<19)|ub(curB[7],refB[7],10)
			db = (0x1<<19)|ub(curB[7],refB[7],10)
			refB[7]=false
		elseif refB[9] then
			df = (0x1<<19)|ub(curB[9],refB[9],10)
			db = (0x11<<19)|ub(curB[9],refB[9],10)
			refB[9]=false
		end
	end
	if cmd==0x4a then
		mode=15
		local car_id=math.floor(curN[3])
		df=shift(EXTRA_BRAKE,23,1)|shift(car_id,18,4)|shift(PAN_FRONT,12,2)|shift(PAN_BACK,10,2)|shift(DOOR,7,3)|shift(DOOR,4,3)|shift(AXLE,2,2)|shift(CAB,0,2)
		db=shift(EXTRA_BRAKE,23,1)|shift(car_id,18,4)|shift(PAN_FRONT,10,2)|shift(PAN_BACK,12,2)|shift(DOOR,7,3)|shift(DOOR,4,3)|bit_ex(shift(AXLE,2,2),2,3)|bit_ex(shift(CAB,0,2),0,1)
		refB[23] = false
	end
	if cmd==0x4b then
		mode=14
		db=unpk(curN[1])
		df=bit_ex_ar(db,{{1,7},{2,8},{3,9},{4,10},{5,11},{6,12},{13,15},{14,16}})
		refN[1] = false
	end
	if cmd==0x4c then
		mode=14
		df=unpk(curN[2])&0xffffff
		db=unpk(curN[2])&0xffffff
		refN[2] = false
	end
	if cmd==0x60 then
		mode=14
		df=ub(curB[22],refB[22],20)|ub(curB[14],refB[14],18)|ub(curB[6],refB[6],16)|bbit(15,riseB[3])|bbit(14,riseB[4])|bbit(13,riseB[5])|ub(curB[15],refB[15],4)|ub(curB[2],refB[2],2)|ub(curB[1],refB[1],0)
		db=df
		arr_cls(refB,1,6)
		arr_cls(riseB,3,5)
		refB[14]=false
		refB[15]=false
		refB[22]=false
	end

	if mode~=0 and curN[16] then
		logb[cmd]=(toi(cmd) << 24) | db
		logf[cmd]=(toi(cmd) << 24) | df
		output.setNumber(6, pk((toi(cmd) << 24) | db))
		output.setNumber(7, pk((toi(cmd) << 24) | df))
	else
		output.setNumber(6, 0)
		output.setNumber(7, 0)
	end
	output.setBool(13, mode==13)
	output.setBool(14, mode==14)
	output.setBool(15, mode==15)
end
