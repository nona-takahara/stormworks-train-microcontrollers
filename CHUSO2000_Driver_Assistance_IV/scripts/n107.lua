d={}function onTick()d={}for i=1,30 do
b,a=('I3B'):unpack(('f'):pack(input.getNumber(i)))d[i]=(66<=a and a<=126 or 194<=a and a<=254)and(a-66>>2&32|a-66&31)<<24|b or nil
end
end
e=19
f=12
g=13
h=18
k=171
l=15
o=21
p=10
q=24
z={k,k,k}A={0,0,0}B={e,e,e}E={122,4,4}r={{9,16,27},{135,59,5},nil,{122,33,4},B,{4,36,2},E,{4,e,122},A,z}s={z,A}t={z,A,{25,126,49},E,B,nil}n={z}S=screen
function C(c)c=c or{0,0,0,0}S.setColor(c[1],c[2],c[3],c[4]or 255)end
u,v=0,0
function R(x,y,w,h)S.drawRectF(x+u,y+v,w,h)end
function H(x,y,w)R(x,y,w,1)end
function V(x,y,h)R(x,y,1,h)end
function D(x,y)H(x,y,1)end
function Y(i,x,y)u,v=x,y
if i==1then H(0,2,3)R(1,1,2,3)V(2,0,5)end
if i==2then V(0,4,2)V(1,2,2)V(2,0,2)end
if i==3then H(0,0,5)R(1,0,3,2)V(2,0,3)end
if i==4then H(0,2,5)R(1,1,3,2)V(2,0,3)end
end
function T(i,x,y)u,v=x,y
if i==l then D(q,2)H(q,4,5)V(25,0,2)H(25,0,3)V(25,3,4)H(25,6,4)D(26,2)V(27,0,2)V(28,4,3)end
if i==e then D(f,5)D(g,4)D(14,3)D(l,2)D(16,1)V(h,1,2)H(h,1,5)H(h,4,5)D(h,6)V(e,3,3)R(e,4,3,2)V(20,0,3)V(20,4,3)V(o,3,3)V(22,1,2)D(22,6)V(q,1,6)H(q,1,5)H(q,4,2)V(26,0,4)H(27,4,2)H(27,6,2)V(28,1,6)end
if i==20then H(6,0,5)H(6,2,5)D(6,4)V(7,0,4)R(7,2,3,2)R(7,5,3,2)V(8,2,5)V(9,0,4)D(p,4)end
if i==o then H(0,1,5)V(0,5,2)V(1,0,5)R(1,3,4,2)V(2,3,4)R(2,3,2,3)V(3,0,6)R(3,1,2,4)D(4,6)end
if i==26then V(0,1,6)H(0,1,5)H(0,3,3)H(0,6,5)V(2,0,2)V(2,3,2)H(2,4,3)V(4,1,6)H(6,0,2)R(6,2,2,3)H(6,6,3)V(7,0,7)H(7,1,4)R(7,5,2,2)V(9,0,5)R(9,1,2,4)V(p,1,6)end
if i==28then V(0,0,7)R(0,0,2,6)H(0,0,3)R(0,2,3,2)H(0,2,5)D(2,6)V(3,1,2)V(3,4,2)D(4,0)V(4,2,2)D(4,6)V(6,1,2)H(6,2,5)V(6,4,3)H(6,6,5)V(8,0,7)V(p,1,2)V(p,4,3)end
if i==29then D(6,2)D(7,1)V(7,4,3)H(7,4,3)H(7,6,3)D(8,0)H(8,2,3)V(9,1,2)V(9,4,3)H(f,1,2)H(f,4,2)V(g,0,7)H(g,2,2)D(l,1)D(l,6)V(16,2,4)H(h,2,5)V(e,0,6)H(20,6,3)V(o,0,5)end
if i==30then H(6,0,2)R(6,2,2,2)H(6,2,5)H(6,5,3)V(7,0,7)R(7,5,2,2)H(7,6,4)H(9,0,2)V(9,2,3)V(p,5,2)H(f,0,5)H(f,4,5)V(g,2,5)R(g,2,3,3)V(14,0,5)V(l,2,5)V(h,0,7)R(h,0,2,2)R(h,3,2,3)R(h,3,5,2)R(o,0,2,2)R(o,3,2,3)V(22,0,7)end
if i==31then H(f,0,5)V(f,2,2)H(f,2,5)H(f,6,2)V(g,0,3)H(g,4,3)V(14,4,2)V(l,0,3)H(l,6,2)V(16,2,2)end
if i==32then H(h,2,5)V(e,0,5)H(e,0,3)H(e,4,3)H(20,6,2)V(o,0,3)V(o,4,3)end
if i==33then R(0,2,2,2)H(0,3,3)V(1,0,7)H(1,1,4)R(1,3,2,2)H(1,6,4)V(3,0,2)V(3,5,2)V(4,1,4)R(6,0,5,2)H(6,3,5)V(6,5,2)H(6,6,5)V(8,0,7)R(8,3,2,4)end
if i==34then H(6,0,5)V(6,2,5)H(6,2,5)R(6,4,5,2)V(8,0,6)V(p,2,5)H(h,1,3)R(h,3,5,2)V(e,0,7)H(e,6,2)D(o,0)V(o,3,3)D(22,1)D(22,6)end
if i==35then H(0,2,2)H(0,4,2)D(0,6)V(1,1,5)H(1,1,4)H(1,3,4)H(1,5,4)V(2,5,2)V(3,0,2)V(3,3,3)V(4,5,2)D(6,6)V(7,4,2)V(8,0,4)V(9,4,2)D(p,6)H(f,1,5)H(f,3,2)H(f,5,2)V(g,0,7)H(g,4,4)H(g,6,2)V(l,0,6)R(l,1,2,4)D(16,6)end
if i==36then H(0,1,5)H(0,4,5)V(2,0,7)V(6,1,6)H(6,1,5)H(6,6,5)V(p,1,6)H(f,0,2)H(f,2,5)R(f,4,2,2)H(f,4,5)V(g,0,7)H(g,6,4)V(l,0,7)R(l,0,2,3)end
if i==37then V(0,1,5)H(1,0,3)H(1,6,3)D(4,1)D(4,5)end
if i==38then V(0,1,2)D(0,5)H(1,0,3)H(1,3,3)H(1,6,3)D(4,1)V(4,4,2)end
if i==39then V(0,1,5)H(0,4,2)H(1,0,3)H(1,6,3)D(2,3)H(3,2,2)V(4,1,5)end
if i==40then H(1,1,2)H(1,6,3)V(2,0,7)end
if i==41then D(0,1)H(0,6,5)H(1,0,3)V(1,5,2)D(2,4)D(3,3)V(4,1,2)end
if i==42then V(0,0,4)H(0,0,5)H(0,2,4)D(0,5)H(1,6,3)V(4,3,3)end
if i==43then V(0,2,4)H(0,3,4)D(1,1)H(1,6,3)H(2,0,2)V(4,4,2)end
if i==44then H(0,0,5)V(2,3,4)D(3,2)V(4,0,2)end
if i==45then V(0,1,2)V(0,4,2)H(1,0,3)H(1,3,3)H(1,6,3)V(4,1,2)V(4,4,2)end
if i==46then V(0,1,2)H(1,0,3)H(1,3,4)H(1,6,2)D(3,5)V(4,1,4)end
if i==48then H(0,0,5)V(2,0,7)H(2,2,2)D(4,3)end
if i==49then H(0,6,5)V(2,0,7)H(2,2,2)end
if i==50then D(0,2)D(0,4)H(1,3,3)V(2,1,5)D(4,2)D(4,4)end
if i==27then D(0,6)H(1,2,2)D(1,5)D(2,4)D(3,3)V(4,0,3)V(4,4,2)H(f,6,5)H(g,3,3)V(l,3,4)D(h,2)H(e,3,4)T(o,x+q,y)end
end
function onDraw(p,j,x,y,l)C({5,6,7})S.drawClear()for i=1,30 do
p=d[i]if p then
j=p>>4&255
x,y=p>>14&127,p>>21&31
l=(p>>26&15)+1
if p&3==0then
u,v=0,0
C(r[l])R(p>>2&127,p>>9&31,x,y)end
if p&15==5then
C(t[l])T(j,x,y)end
if p&15==9then
C(s[l])Y(j,x,y)end
if p&15==1then
C(n[l])w=(p>>4&3)+1
m=w>2 and(d[i+1]or 0)>>4&16383 or p>>7&127
u,v=x+4*w-4,y
for j=1,w do
c=m%10
if m~=0 or j==1 or p>>6&1~=0then
if c==0 or 3<c and c~=7then V(0,0,3)end
if c%2==0 and c~=4then V(0,2,3)end
if c~=1 and c~=4then H(0,0,3)end
if 1<c and c~=7then H(0,2,3)end
if c~=1 and c~=4 and c~=7then H(0,4,3)end
if c~=5 and c~=6then V(2,0,3)end
if c~=2then V(2,2,3)end
end
m=m//10
u=u-4
end
end
end
end
end