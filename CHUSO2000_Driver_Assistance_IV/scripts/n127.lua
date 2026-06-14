P=0
I1=0
I2=0
r=screen.drawRectF

function dgt3(x,y,n)
if n==0 or 4<=n and n~=7 then r(x,y,1,3) end
if n%2==0 and n~=4 then r(x,y+2,1,3) end
if n~=1 and n~=4 then r(x,y,3,1) end
if 2<=n and n~=7 then r(x,y+2,3,1) end
if n~=1 and n~=4 and n~=7 then r(x,y+4,3,1) end
if n~=5 and n~=6 then r(x+2,y,1,3) end
if n~=2 then r(x+2,y+2,1,3) end
end

function onTick()
P=input.getNumber(32)
I1=input.getNumber(7)
I2=input.getNumber(17)
end

function onDraw()
	if P==4000 then
		screen.setColor(0,0,0)
		r(22,2,17,7)
		r(46,2,17,7)
		screen.setColor(240,240,240)
		dgt3(23,3,(I1//1000)%10)
		dgt3(27,3,(I1//100)%10)
		dgt3(31,3,(I1//10)%10)
		dgt3(35,3,(I1//1)%10)

		dgt3(47,3,(I2//1000)%10)
		dgt3(51,3,(I2//100)%10)
		dgt3(55,3,(I2//10)%10)
		dgt3(59,3,(I2//1)%10)
	end
end
