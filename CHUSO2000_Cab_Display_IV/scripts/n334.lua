ATC=false
ATS=false
idc=0

Cross=false
Notice=false
Patt=false
Rsig=false
Gsig=false

ticker=0

function onTick()
if Notice or Patt then ticker=(ticker+1)%60 else ticker=0 end

idc=input.getNumber(1)

ATC=input.getBool(1)
Rsig=input.getBool(2)
Gsig=input.getBool(3)
Cross=input.getBool(4)
Patt=input.getBool(5)
Notice=input.getBool(6)
ATS=input.getBool(10)
end

function onDraw()S=screen C=S.setColor R=S.drawRectF
C(255,0,0)
if Rsig then R(39,2,2,2)end
if Cross then P(41,23)P(41,25)P(42,24)P(43,23)P(43,25)end

C(0,96,0)
if idc<0 then --none
elseif idc<5 then P(36,19) --0
elseif idc<10 then P(35,18) --5
elseif idc<15 then P(34,16) --10
elseif idc<20 then P(33,15) --15
elseif idc<25 then P(33,13) --20
elseif idc<30 then P(33,11) --25
elseif idc<35 then P(34,10) --30
elseif idc<40 then P(35,8) --35
elseif idc<45 then P(36,7) --40
elseif idc<50 then P(37,6) --45
elseif idc<55 then P(39,5) --50
elseif idc<60 then P(40,4) --55
elseif idc<65 then P(42,4) --60
elseif idc<70 then P(44,4) --65
elseif idc<75 then P(45,5) --70
elseif idc<80 then P(47,6) --75
elseif idc<85 then P(48,7) --80
elseif idc<90 then P(49,8) --85
elseif idc<95 then P(50,10) --90
elseif idc<100 then P(51,11) --90
elseif idc<110 then P(51,13) --100
else P(50,16) end--110

if Patt and ticker<=30 then R(37,21,1,4)P(38,21)P(39,22)P(38,23)end
if Notice and ticker<=30 then R(45,22,4,2)end

C(0,160,0)
if Gsig then R(44,2,2,2)end
if ATS then R(56,3,1,4)R(57,2,2,1)R(59,3,1,4)R(57,4,2,1) R(60,2,3,1)R(61,3,1,4) P(63,3)R(64,2,3,1)R(64,4,2,1)P(66,5)R(63,6,3,1)end
if ATC then R(18,3,1,4)R(19,2,2,1)R(21,3,1,4)R(19,4,2,1) R(22,2,3,1)R(23,3,1,4) R(25,3,1,3)R(26,2,3,1)R(26,6,3,1)end
end

function P(x,y)R(x,y,1,1)end