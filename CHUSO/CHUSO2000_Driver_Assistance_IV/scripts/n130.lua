C=11
function onTick()
local arc=math.floor(input.getNumber(2))
output.setNumber(7,math.floor(input.getNumber(1))) -- operation.number
output.setNumber(8,arc) -- ARC

output.setNumber( 9,math.min((math.floor(input.getNumber(3))>>12)&15,C)) -- operation.type
output.setNumber(10,(math.floor(input.getNumber(3))>>6)&63)  -- operation.dep.
output.setNumber(11,(math.floor(input.getNumber(3)))&63)     -- operation.dest.

if input.getNumber(5)==0 then
	output.setNumber(12,math.min((math.floor(input.getNumber(3))>>12)&15,C)) -- operation.type
	output.setNumber(13,(math.floor(input.getNumber(3)))&63)     -- operation.dest.
else
	output.setNumber(12,math.min((math.floor(input.getNumber(5))>>12)&15,C)) -- operation.type
	output.setNumber(13,(math.floor(input.getNumber(5)))&63)     -- operation.dest.
end

local statbound=(math.floor(input.getNumber(6))>>14)&3
local arcbound=arc//10000
if arcbound~=0 then if arcbound%2==0 then arcbound=1 else arcbound=2 end end
if statbound==0 then statbound=arcbound elseif arcbound~=statbound then statbound=3 end
output.setNumber(14,statbound) -- position.bound
local t= (math.floor(input.getNumber(6))>>12)&3
local s1=(math.floor(input.getNumber(6))>>6)&63
local s2=(math.floor(input.getNumber(6)))&63
if t==2 and s1==s2 then
output.setNumber(15,4) -- position.type
else
output.setNumber(15,t) -- position.type
end
output.setNumber(16,s1) -- position.station
end

