function onTick()
B=input.getNumber(1)>0
PP=input.getNumber(2)

EB=input.getBool(1)
NITS=input.getBool(2)
Ctrl=input.getBool(3)
DCls=not (input.getBool(4) or input.getBool(5))
PBPres=input.getBool(6)
NextStop=input.getBool(7)
TASC=input.getBool(8)
end

function onDraw()S=screen C=S.setColor R=S.drawRectF
C(255,0,0)
if EB then R(19,14,1,4)P(18,15)R(18,17,1,2)R(21,14,1,5)P(22,15)P(22,17) R(24,15,5,1)P(25,14)P(27,14)P(24,16)P(28,16)R(25,17,3,1)P(24,18)P(26,18)P(28,18)end

C(255,50,0)
if B then R(18,9,5,1)P(19,8)P(21,8)P(18,10)P(22,10)R(19,11,3,1)P(18,12)P(20,12)P(22,12) R(25,8,2,2)P(25,10)P(27,8)P(27,10)R(24,11,1,2)R(26,11,1,2)R(28,8,1,5)end
if ConstB then R(57,14,1,5)P(56,15)P(56,17)R(58,15,1,2)P(59,14)R(60,15,1,3)R(59,17,1,2) P(62,14)R(62,16,1,2)R(63,18,4,1)P(64,17)P(66,17)P(65,16)P(64,15)P(66,15)R(64,14,3,1)
end
if PBPres then R(59,15,2,4)P(58,14)P(60,14)P(58,16)R(56,15,1,3)P(57,15)P(57,17)R(62,15,1,4)R(63,14,4,1)R(65,15,1,4)R(64,16,3,1)R(63,18,4,1)end
if NextStop then R(57,20,1,2)R(59,20,1,2)P(56,22)R(58,21,1,3)R(60,21,1,3)R(57,23,1,2)R(59,23,1,2)P(62,21)P(62,23)P(64,20)P(66,21)P(66,23)P(64,24)R(63,21,3,3)end

C(0,160,0)
if DCls then R(56,8,5,1)R(57,8,1,4)R(57,10,4,1)R(60,8,1,3)P(56,12) R(62,8,1,5)R(63,8,1,2)R(65,8,1,2)R(66,8,1,5)P(64,10)P(65,11)P(64,12)end
if (not EB) and PP and PP>0 then
R(18,21,4,1)R(19,20,1,3)R(18,23,1,2)R(21,21,1,4)R(21,22,4,1)R(24,22,1,3)P(23,24)P(20,24)P(22,20)P(24,20)
dgt3(26,20,PP)
end
if DCls and Ctrl then R(40,28,5,3)end
if NITS then
R(56,26,1,5)P(57,26)R(58,27,1,4)R(60,26,1,5)R(62,26,3,1)R(63,26,1,5)P(66,26)P(65,27)P(66,28)P(66,29)P(65,30)
end
if TASC then
R(19,26,1,5)R(18,26,3,1)R(21,27,1,4)P(22,26)P(22,28)R(23,27,1,4)P(25,26)P(24,27)P(25,28)P(25,29)P(24,30)P(28,26)R(27,27,1,3)P(28,30)
end
end

function P(x,y)R(x,y,1,1)end

function dgt3(x,y,n)
if n==0 or 4<=n and n~=7 then R(x,y,1,3) end
if n%2==0 and n~=4 then R(x,y+2,1,3) end
if n~=1 and n~=4 then R(x,y,3,1) end
if 2<=n and n~=7 then R(x,y+2,3,1) end
if n~=1 and n~=4 and n~=7 then R(x,y+4,3,1) end
if n~=5 and n~=6 then R(x+2,y,1,3) end
if n~=2 then R(x+2,y+2,1,3) end
end