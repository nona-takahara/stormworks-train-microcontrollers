d={}function onTick()d={}for i=1,30 do
b,a=('I3B'):unpack(('f'):pack(input.getNumber(i)))d[i]=(66<=a and a<=126 or 194<=a and a<=254)and(a-66>>2&32|a-66&31)<<24|b or nil
end
end
c=12
e=18
f=10
g=19
h=14
j=24
k=21
l=13
m=16
n=25
o=15
p=-1
q=22t={{171,171,171},{0,0,0},{n,126,49},{122,4,4},{g,g,g},nil}S=screen
function C(c)c=c or{0,0,0,0}S.setColor(c[1],c[2],c[3],c[4]or 255)end
u,v=0,0
function R(x,y,w,h)S.drawRectF(x+u,y+v,w,h)end
function H(x,y,w)R(x,y,w,1)end
function V(x,y,h)R(x,y,1,h)end
function D(x,y)H(x,y,1)end
function T(i,x,y)u,v=x,y
if i==-29then H(6,0,2)H(6,2,2)R(6,4,2,2)H(6,4,5)V(7,0,7)H(7,1,3)R(7,3,4,2)H(7,6,4)V(9,1,6)D(f,0)V(c,0,3)H(c,0,3)H(c,2,3)D(c,6)V(l,2,4)R(l,4,2,2)V(h,0,3)V(h,4,3)V(m,0,7)end
if i==-28then D(0,6)R(1,3,3,2)V(2,0,5)H(2,1,3)D(2,6)D(4,6)end
if i==-27then V(0,0,2)H(0,1,5)D(0,3)R(0,5,2,2)H(0,6,3)V(2,0,5)R(2,1,2,3)H(2,3,3)D(3,5)V(4,0,2)V(4,3,2)D(4,6)end
if i==-26then R(0,2,2,2)V(1,0,7)H(1,1,4)V(3,0,2)H(3,3,2)R(3,5,2,2)end
if i==-25then H(0,6,5)V(1,2,5)V(3,0,7)H(3,2,2)end
if i==-24 or i==31then V(0,0,7)R(0,0,2,2)H(0,1,5)R(0,3,2,2)V(2,5,2)V(3,0,5)R(3,3,2,2)V(4,3,4)end
if i==-23 or i==n or i==o then D(6,2)D(6,6)V(7,0,2)H(7,1,3)H(7,3,4)D(7,5)R(8,1,2,4)V(9,0,7)end
if i==81 or i==83 or i==-21then D(0,0)V(0,4,3)D(1,2)V(2,0,2)H(2,1,3)D(2,6)V(3,1,5)R(3,1,2,2)D(4,6)V(6,0,7)H(6,5,2)H(8,1,3)H(8,4,2)H(8,6,2)V(9,0,7)H(9,5,2)end
if i==82 or i==-20then H(0,1,5)H(0,3,5)R(0,5,3,2)H(0,5,4)V(2,0,7)D(4,6)end
if i==-19then H(0,3,5)V(1,2,3)D(2,1)D(2,5)end
if i==75 or i==74 or i==f or i==-18then H(0,0,5)H(0,2,5)V(0,4,3)H(0,5,3)R(1,2,2,2)V(2,0,7)H(2,4,3)V(4,0,7)V(6,0,7)H(6,0,5)R(6,4,3,2)H(6,5,5)V(8,2,4)H(8,3,3)V(f,0,7)end
if i==-17then H(0,1,3)V(0,4,3)V(1,0,4)D(2,6)V(3,2,4)H(3,3,2)D(4,1)end
if i==-16 or i==29then V(0,0,5)H(0,0,5)H(0,2,5)H(0,4,5)D(0,6)V(1,4,2)V(3,4,3)H(3,6,2)V(4,0,5)end
if i==-15then R(0,0,2,6)H(0,1,5)H(2,6,2)V(3,1,6)end
if i==-14 or i==61then D(0,0)V(0,3,4)H(0,6,5)H(2,0,2)V(2,2,3)R(2,2,3,2)V(3,0,4)V(4,2,3)end
if i==59 or i==-13 or i==60then R(0,0,2,3)H(0,1,5)H(0,4,2)V(1,0,7)H(1,3,4)H(1,5,2)V(3,0,4)H(3,6,2)V(4,3,4)end
if i==57 or i==-12then D(0,0)D(0,2)V(0,4,2)H(0,5,5)V(2,0,7)R(2,1,2,3)H(2,1,3)H(2,3,3)V(4,0,2)end
if i==-11then D(0,0)V(0,3,4)H(0,6,5)H(1,1,4)V(2,0,2)H(2,3,3)V(2,5,2)V(3,1,4)V(4,0,2)V(4,5,2)end
if i==-9then V(0,0,4)H(0,0,2)H(0,2,2)H(0,5,2)V(1,4,3)H(1,6,2)V(3,0,6)R(3,0,2,4)D(4,6)end
if i==-8 or i==j or i==3 or i==h then V(6,0,7)H(6,0,5)H(6,2,5)H(6,4,5)V(8,0,7)V(f,0,7)end
if i==-7 or i==58then H(0,1,2)V(0,5,2)H(0,5,2)V(1,1,2)H(1,2,3)V(1,4,2)H(1,4,3)H(2,0,2)H(2,6,3)V(3,0,5)V(4,5,2)end
if i==32 or i==-6then R(0,2,3,2)H(0,3,5)V(1,0,7)R(1,1,2,3)H(1,1,4)H(1,6,3)V(3,0,2)V(3,3,4)R(3,3,2,2)V(4,1,4)end
if i==-23 or i==n or i==o or i==34 or i==q or i==-5then H(0,1,5)H(0,5,5)R(1,1,3,5)V(2,0,7)end
if i==-4 or i==77 or i==-22 or i==11 or i==c or i==l or i==78then H(0,1,5)V(0,3,4)H(0,3,2)H(0,5,5)V(2,0,3)V(2,4,3)H(3,3,2)V(4,3,4)D(6,0)D(6,2)V(6,4,3)H(8,1,3)H(8,6,3)V(9,1,6)end
if i==65 or i==66 or i==67 or i==5 or i==6 or i==7 or i==-10 or i==-3then H(0,2,2)H(0,5,2)V(1,0,7)V(3,0,7)H(3,2,2)H(3,6,2)D(6,0)D(6,2)V(6,4,3)H(6,5,2)H(7,1,4)H(7,3,3)V(8,0,5)V(9,5,2)H(9,6,2)V(f,0,3)D(f,4)end
if i==-8 or i==j or i==3 or i==h or i==g or i==20 or i==30 or i==23 or i==-2then D(0,0)V(0,3,4)H(0,6,5)V(2,0,2)H(2,0,3)R(2,3,3,2)V(3,2,5)V(4,0,2)end
if i==p then R(0,2,5,3)R(1,1,3,5)end
if i==2then H(0,3,5)D(2,1)D(2,5)V(3,2,3)end
if i==4then D(6,1)H(7,0,3)D(8,4)D(8,6)D(9,3)V(f,1,2)end
if i==m then R(0,2,2,2)H(0,3,3)V(1,0,7)R(1,0,2,2)H(1,1,4)V(3,1,2)D(3,4)D(3,6)D(4,3)D(4,5)H(6,0,5)H(6,6,5)V(7,3,4)V(9,0,7)H(9,3,2)end
if i==17then D(0,1)D(0,5)H(1,0,3)H(1,6,3)H(2,3,2)V(4,1,2)V(4,4,2)end
if i==e then V(0,3,2)H(0,4,5)D(1,2)H(2,1,2)V(3,0,7)end
if i==q then D(6,2)D(6,6)V(7,0,2)H(7,1,3)H(7,3,4)D(7,5)R(8,1,2,4)V(9,0,7)end
if i==g or i==23then V(6,0,7)H(6,0,5)H(6,2,5)H(6,4,5)V(8,0,7)V(f,0,7)end
if i==j then H(e,0,2)H(e,2,2)R(e,4,2,2)H(e,4,5)V(g,0,7)H(g,1,3)R(g,3,4,2)H(g,6,4)V(k,1,6)D(q,0)V(j,0,3)H(j,0,3)H(j,2,3)D(j,6)V(n,2,4)R(n,4,2,2)V(26,0,3)V(26,4,3)V(28,0,7)end
if i==n then H(e,0,2)H(e,2,2)R(e,4,2,2)H(e,4,5)V(g,0,7)H(g,1,3)R(g,3,4,2)H(g,6,4)V(k,1,6)D(q,0)V(j,0,3)H(j,0,3)H(j,2,3)D(j,6)V(n,2,4)R(n,4,2,2)V(26,0,3)V(26,4,3)V(28,0,7)end
if i==54then V(0,0,7)R(0,0,2,3)H(0,0,4)H(0,2,5)R(0,4,2,3)H(0,4,3)H(0,6,5)V(2,2,3)R(2,2,3,2)V(3,0,4)R(3,1,2,3)R(3,5,2,2)R(6,1,2,5)H(6,1,5)H(6,3,5)H(6,5,3)V(9,0,4)H(9,6,2)V(f,3,4)end
if i==55then V(0,0,7)H(0,0,5)H(0,2,5)H(0,4,2)H(0,6,5)R(2,5,3,2)R(3,0,2,7)R(6,2,2,2)H(6,3,3)V(7,0,7)H(7,1,4)H(7,5,4)V(9,0,3)V(9,4,3)D(f,3)end
if i==58then D(6,1)H(6,3,2)D(7,0)V(7,2,5)H(7,2,4)H(9,0,2)H(9,6,2)V(f,2,5)end
if i==60then V(6,0,7)H(6,0,4)H(6,3,4)H(6,6,4)V(f,1,2)V(f,4,2)end
if i==4 or i==63then D(0,0)D(0,2)V(0,4,3)R(0,4,2,2)H(0,5,5)H(1,1,4)V(1,3,3)H(1,3,4)R(2,0,3,4)R(3,0,2,7)end
if i==68then H(0,3,5)H(0,5,2)H(1,1,3)V(1,3,4)V(2,0,4)V(3,3,4)H(3,5,2)H(6,6,5)H(7,2,3)V(8,0,7)end
if i==8 or i==9 or i==69 or i==70then H(0,1,5)V(0,4,3)H(0,4,5)V(1,1,4)R(1,3,3,2)V(2,0,2)D(2,6)V(3,1,4)V(4,4,3)end
if i==71then V(0,0,7)R(0,0,5,2)H(0,3,3)H(0,5,3)V(2,3,4)H(2,4,3)H(2,6,3)V(3,0,3)H(6,1,3)R(6,3,3,2)R(7,0,2,7)H(7,0,4)H(7,2,4)H(7,5,3)V(f,0,3)D(f,4)D(f,6)V(c,1,3)H(c,1,2)H(c,3,3)R(l,5,3,2)H(h,0,3)R(o,0,2,3)V(m,0,4)end
if i==72then H(0,2,5)D(0,6)D(1,5)V(2,0,5)D(3,5)D(4,6)V(6,1,4)R(6,2,2,3)D(6,6)D(7,0)D(8,6)V(9,0,2)H(9,1,2)V(9,3,2)H(9,4,2)D(f,6)end
if i==74 or i==f then D(c,0)D(c,2)V(c,4,3)H(c,4,5)R(h,1,2,4)H(h,2,3)D(h,6)D(m,0)D(m,6)end
if i==76then D(0,1)H(0,3,5)D(1,0)V(1,2,5)H(1,5,4)H(2,1,2)V(3,0,6)H(3,0,2)R(3,2,2,4)V(4,2,5)D(6,0)V(6,3,4)H(6,6,5)H(7,1,4)V(8,0,2)V(8,3,4)H(8,4,3)V(9,1,2)V(f,0,2)V(f,3,4)end
if i==82then H(6,1,4)H(6,3,4)V(7,1,5)V(8,0,2)H(8,6,2)V(f,4,2)H(c,1,2)D(c,3)V(l,0,3)D(l,5)H(h,4,2)H(h,6,2)V(o,1,6)H(o,1,2)H(o,5,2)D(e,3)H(g,2,2)H(g,4,2)V(k,0,2)V(k,5,2)end
if i==1then H(0,2,5)H(0,5,3)R(1,0,2,6)V(2,0,7)H(2,6,3)V(4,1,4)T(-28,x+6,y)T(m,x+c,y)end
if i==3then H(e,0,3)D(e,2)H(e,4,5)D(e,6)V(g,0,2)V(g,3,3)R(g,3,3,2)D(k,1)V(k,3,4)H(k,6,2)D(q,0)D(q,2)T(-9,x+j,y)end
if i==8then H(e,6,5)V(g,1,6)H(g,1,2)H(g,3,4)D(k,0)V(k,3,4)T(-17,x+c,y)end
if i==h then H(e,1,5)H(e,3,5)H(e,5,4)V(g,0,2)R(g,3,3,4)V(20,1,6)V(k,0,2)T(-9,x+j,y)end
if i==27then H(6,6,5)H(7,1,3)T(k,x+j,y)end
if i==52then V(0,0,7)H(0,0,5)R(0,2,2,3)H(0,2,5)H(0,4,5)H(0,6,5)R(3,2,2,3)V(4,0,7)T(-11,x+6,y)end
if i==53then H(0,1,2)H(0,3,2)R(0,5,3,2)H(0,5,4)V(1,0,2)H(2,2,3)V(2,4,3)R(2,4,2,2)V(3,0,6)H(3,0,2)D(4,6)T(-2,x+6,y)end
if i==56then H(0,4,5)D(1,1)V(1,3,4)H(1,6,3)H(2,0,2)D(2,2)V(3,0,2)V(3,3,4)T(-6,x+6,y)end
if i==64then H(0,1,2)H(0,4,2)H(0,6,5)V(1,0,7)H(1,0,4)R(1,2,4,2)V(3,2,5)R(3,5,2,2)V(4,0,4)H(6,0,5)D(6,6)V(7,2,4)H(7,2,4)H(7,4,4)V(f,2,3)T(-15,x+c,y)end
if i==73then V(0,1,2)H(0,2,3)H(0,4,4)H(0,6,2)D(1,0)V(1,2,5)R(1,2,2,4)R(1,3,3,3)H(1,3,4)V(2,1,5)H(2,1,3)V(3,0,2)V(3,3,4)H(3,6,2)V(4,1,3)D(c,0)D(c,2)V(c,4,3)H(l,3,2)V(h,0,7)H(h,2,3)H(h,6,3)V(m,1,4)T(-17,x+6,y)end
if i==80then H(0,1,3)V(0,4,3)V(1,0,4)D(2,5)H(3,2,2)D(3,4)H(3,6,2)H(6,1,3)V(6,4,3)V(7,0,4)D(8,5)H(9,2,2)D(9,4)H(9,6,2)D(f,0)V(c,1,5)D(l,6)D(h,5)D(o,1)V(m,2,3)T(-20,x+e,y)end
if i==81then D(e,0)V(e,3,4)R(e,4,2,3)H(e,6,5)V(20,0,4)H(20,0,3)H(20,3,3)R(k,5,2,2)V(q,0,7)T(-14,x+c,y)end
if i==-30then T(p,x+6,y)end
if i==-22 or i==c or i==l then T(-15,x+c,y)end
if i==5then T(17,x+e,y)end
if i==6then T(e,x+e,y)end
if i==7then T(p,x+e,y)end
if i==9then T(p,x+e,y)end
if i==f then T(p,x+e,y)end
if i==11then T(76,x+c,y)end
if i==c then T(-19,x+e,y)end
if i==l then T(2,x+e,y)end
if i==o then T(-9,x+e,y)end
if i==k then T(-11,x+6,y)end
if i==28then T(-24,x+c,y)T(-25,x+e,y)end
if i==31then T(-27,x+6,y)T(-26,x+e,y)end
if i==32then T(-25,x+6,y)T(-26,x+c,y)end
if i==33then T(m,x+c,y)end
if i==34then T(-28,x+c,y)end
if i==35then T(-27,x+e,y)end
if i==57then T(-7,x+6,y)end
if i==59then T(-7,x+6,y)end
if i==61then T(-12,x+6,y)end
if i==65then T(17,x+c,y)end
if i==66then T(e,x+c,y)end
if i==67then T(p,x+c,y)end
if i==8 or i==9 or i==69 or i==70then T(-16,x+6,y)end
if i==70then T(p,x+c,y)end
if i==75then T(p,x+c,y)end
if i==77then T(-19,x+c,y)end
if i==78then T(2,x+c,y)end
if i==83then T(-6,x+c,y)T(-5,x+e,y)end
end
function onDraw(p,j,x,y,l)for i=1,30 do
p=d[i]if p then
j=p>>4&255
x,y=p>>14&127,p>>21&31
l=(p>>26&15)+1
if p&15==5then
C(t[l])T(j,x,y)end
end
end
end