spda=0
spd=0
spdt=0

brka=0
brk=0

bc=0

mr=0
function onTick()
spdt=math.abs(input.getNumber(4))
spda=(spda*0.78)+((spdt-spd)*0.034)
spd=spd+spda

brkt=input.getNumber(1)
if input.getBool(1) then brkt=32 end
if brkt<=0 then
	brkt=1.25
elseif brkt>=32 then
	brkt=0.25
else
	brkt=1.25-(brkt/32)
end
brka=(brka*0.78)+((brkt-brk)*0.034)
brk=brk+brka

bc=input.getNumber(5)/98
mr=input.getNumber(6)-1
end

function onDraw()S=screen C=S.setColor
C(0,0,0,64)S.drawText(38-((spdt*3.6)//100)*3,16,("%2d"):format((spdt*3.6)//1))

C(255,0,0)
needle(8,24,((8-mr)/6)*math.pi,5)
C(0,0,0)
needle(42,13,(100-spd*3.6)/80*math.pi,6)
needle(8,8,brk*math.pi,5)
needle(8,24,((8-bc)/6)*math.pi,5)
end

function needle(x,y,a,l)
S.drawLine(x,y,x+l*math.cos(a),y-l*math.sin(a))
end
