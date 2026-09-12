function R(x,y,w,h)S.drawRectF(x+70,y+3,w,h)end
function V(x,y,h)R(x,y,1,h)end
function H(x,y,w)R(x,y,w,1)end
I=0
J=0
K=0
L=0
function onTick()
local i=(input.getNumber(2)//100)%100
K=i//10
L=(input.getNumber(2)//10000)%10
J=input.getNumber(1)
I=0
if K==1 then I=4
elseif K==2 then I=9
elseif K==3 then I=5
elseif K==4 then I=6
elseif K==5 then I=7
elseif K==7 then I=8
elseif i==2 then I=1
elseif i==1 then I=2
elseif i==3 then I=3
end

end

function onDraw()S=screen C=S.setColor
if I==1then C(255,0,0)H(0,0,5)H(8,0,3)V(2,0,2)V(4,0,2)H(0,2,2)V(9,0,3)H(6,2,5)R(6,1,2,3)V(0,0,5)V(2,3,2)H(0,4,3)V(4,3,2)V(10,2,3)H(9,4,2)end
if I==2then C(255,0,0)H(4,0,4)V(3,1,1)H(4,2,3)V(6,0,4)R(5,2,2,2)V(3,3,2)V(5,2,3)H(3,4,3)V(7,4,1)end
if I==3then C(255,0,0)H(0,0,5)V(6,0,1)H(8,0,3)V(9,0,2)V(2,2,1)V(8,2,1)V(10,2,1)V(0,0,5)V(4,0,5)H(0,4,5)V(6,2,3)H(6,4,5)end
if I==4then C(0,44,8)H(1,0,4)H(6,0,5)V(1,0,2)H(0,1,2)H(5,1,2)H(2,2,2)V(8,0,3)V(10,0,3)H(8,2,3)H(0,3,2)H(3,3,2)V(1,3,2)V(3,0,5)H(1,4,3)V(6,0,5)V(9,2,3)H(8,4,2)end
if I==5then C(0,44,8)V(0,0,1)H(2,0,3)H(7,0,3)V(6,1,1)R(8,0,2,3)R(8,1,3,2)V(0,2,2)V(4,0,4)R(2,2,3,2)H(0,3,5)H(6,3,2)V(2,0,5)V(6,3,2)H(8,4,3)end
if I==6then C(255,22,0)H(0,0,5)H(7,0,3)V(2,0,2)V(4,0,2)V(6,1,1)V(3,2,1)R(8,0,2,3)R(8,1,3,2)H(6,3,2)V(0,0,5)V(2,3,2)V(4,3,2)H(0,4,5)V(6,3,2)H(8,4,3)end
if I==7then C(255,0,0)H(1,0,3)V(7,0,1)H(9,0,2)V(0,1,1)V(6,1,1)R(2,0,2,3)R(2,1,3,2)H(9,2,2)H(0,3,2)H(6,3,2)V(0,3,2)H(2,4,3)V(7,2,3)V(10,2,3)H(9,4,2)end
if I==8then C(255,22,0)H(2,0,3)H(7,0,3)V(0,0,2)H(0,1,2)V(6,1,1)V(3,0,3)H(1,2,4)R(8,0,2,3)R(8,1,3,2)H(0,3,2)H(6,3,2)V(1,1,4)V(4,2,3)H(3,4,2)V(6,3,2)H(8,4,3)end
if I==9then C(0,44,8)V(0,0,1)H(2,0,3)V(6,0,1)H(8,0,3)V(1,1,1)V(4,0,2)H(2,2,2)V(6,2,2)V(10,0,4)R(8,2,3,2)H(6,3,5)V(0,2,3)V(2,2,3)V(4,3,2)H(0,4,5)V(8,0,5)end
if I==10then C(0,44,8)H(0,0,5)V(6,0,1)H(8,0,3)H(0,2,5)V(9,0,3)H(8,2,3)V(1,0,5)V(3,0,5)H(1,4,3)V(6,2,3)V(8,2,3)V(10,2,3)H(6,4,5)end
if I==11then C(255,22,0)V(6,0,1)H(8,0,3)H(0,1,2)V(8,0,2)R(3,1,2,2)H(2,2,3)H(9,2,2)V(3,0,4)V(0,0,5)V(2,4,1)V(4,4,1)V(6,2,3)V(8,3,2)V(10,0,5)H(6,4,5)end
if I==12then C(255,22,0)V(0,0,1)H(2,0,3)V(1,1,1)V(4,0,2)H(6,1,2)H(2,2,2)R(9,1,2,2)H(8,2,3)V(9,0,4)V(0,2,3)V(2,2,3)V(4,3,2)H(0,4,5)V(6,0,5)V(8,4,1)V(10,4,1)end
if I==13then C(0,44,8)H(8,0,3)H(0,1,2)V(6,0,2)H(6,1,2)R(3,1,2,2)H(2,2,3)V(9,0,3)H(7,2,4)V(3,0,4)H(6,3,2)V(0,0,5)V(2,4,1)V(4,4,1)V(7,1,4)V(10,2,3)H(9,4,2)end

C(255,50,0)
if J~=0 then
dgt3(16,0,(J//10)%10)
dgt3(20,0,(J//1)%10)
end

if L==2 then C(0,160,0) else C(0,0,0) end V(22,8,1)
if L==1 then C(0,160,0) else C(0,0,0) end V(6,8,1)
end

function dgt3(x,y,n)
if n==0 or 4<=n and n~=7 then R(x,y,1,3) end
if n%2==0 and n~=4 then R(x,y+2,1,3) end
if n~=1 and n~=4 then R(x,y,3,1) end
if 2<=n and n~=7 then R(x,y+2,3,1) end
if n~=1 and n~=4 and n~=7 then R(x,y+4,3,1) end
if n~=5 and n~=6 then R(x+2,y,1,3) end
if n~=2 then R(x+2,y+2,1,3) end
end