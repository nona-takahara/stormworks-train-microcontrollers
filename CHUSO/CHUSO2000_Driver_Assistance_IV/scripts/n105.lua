I,O=input,output
B=I.getBool
function N(c)return math.floor(I.getNumber(c))end
function onTick()function T(x,y,w,h)for i=1,2 do
x,y=N(1+2*i)-x,N(2+2*i)-y
if B(i)and 0<=x and x<w and 0<=y and y<h then
return 1
end
end
end
i=N(32)o={}function n(c,v,f,g)if f then
o[c]=v
if not g then
b(c,1)end
end
end
function b(c,f)if f then
o[c+32]=1
end
end
a=11
c=32
d=21
e=12
f=16
g=T(38,d,25,9)h=T(e,a,25,9)j=T(38,a,25,9)k=T(e,d,25,9)l=T(1,26,9,5)m=T(1,a,9,5)p=100
q=300
r=15
s=400t=1100
u=3000
v=T(e,a,f,9)w=T(29,a,f,9)x=T(46,a,f,9)y=T(e,d,f,9)z=T(1,1,7,9)A=1000
C=200
D=2000
E=1001
F=1102
G=T(47,1,r,9)H=T(29,d,f,9)J=301
K=302
L=i==s
M=1101
P=3100
Q=3101
R=3102
S=i==D
U=i==2001
V=i==C
W=i==201
X=i==E
Y=i==A
Z=i==401
a0=i==t
a1=i==F
a2=i==1103
a3=i==4000
a4=T(46,d,f,9)a5=L or Z or i==402 or i==403
a6=i==3103
a7=T(53,d,9,9)if i==0then n(c,u,T(47,9,r,9))n(c,p,T(1,19,31,a))n(c,4000,T(34,19,13,a))n(c,D,T(49,19,13,a))end
if a3 or S or U or i==p or i==u then n(c,0,z)end
if i==p then n(c,A,T(47,22,r,9))n(c,C,G)end
if V or W or X or Y then n(c,p,z)end
if V then n(c,201,l)n(1,1,v)n(1,2,w)n(1,3,x)n(1,4,y)end
if V or W then n(c,q,v)n(c,q,w)n(c,q,x)n(c,q,y)end
if W then n(c,C,m)n(1,5,v)n(1,6,w)n(1,a,x)n(1,7,y)n(c,q,H)n(1,8,H)n(c,q,a4)n(1,9,a4)end
if i==q or i==J or i==K or i==303then n(c,C,z)n(c,s,h)n(c,s,j)n(c,s,k)n(c,s,g)end
if i==q then n(c,J,l)n(2,1,h)n(2,2,j)n(2,3,k)n(2,4,g)end
if i==J then n(c,q,m)n(c,K,l)n(2,5,h)n(2,6,j)n(2,7,k)n(2,8,g)end
if i==K then n(c,J,m)n(c,303,l)n(2,9,h)n(2,10,j)n(2,a,k)n(2,e,g)end
if i==303then n(c,K,m)n(2,13,h)n(2,14,j)n(2,r,k)n(2,f,g)end
if a5 then n(c,q,z)end
if L then n(c,401,l)n(3,1,h)n(3,2,j)n(3,3,k)n(3,4,g)end
if a5 or L or a0 or i==M or a1 or a2 then n(c,p,h)n(c,p,j)n(c,p,k)n(c,p,g)end
if Z then n(c,s,m)n(c,402,l)n(3,5,h)n(3,6,j)n(3,7,k)n(3,8,g)end
if i==402then n(c,401,m)n(c,403,l)n(3,9,h)n(3,10,j)n(3,a,k)n(3,e,g)end
if i==403then n(c,402,m)n(3,13,h)n(3,14,j)n(3,r,k)n(3,f,g)end
if Y then n(c,E,l)n(c,p,v)n(4,1,v)n(5,0,v)n(c,p,w)n(4,2,w)n(5,0,w)n(c,p,x)n(4,3,x)n(5,0,x)n(c,p,y)n(4,4,y)n(5,0,y)end
if Y or X then n(c,p,G)n(4,0,G)n(5,0,G)end
if X then n(c,A,m)n(c,t,v)n(4,5,v)n(c,t,w)n(4,6,w)n(c,t,x)n(4,a,x)n(c,t,y)n(4,7,y)n(c,t,H)n(4,8,H)end
if a0 or a1 or a2 then n(c,E,z)end
if a0 then n(c,M,l)n(5,1,h)n(5,2,j)n(5,3,k)n(5,4,g)end
if i==M then n(c,A,z)n(c,t,m)n(c,F,l)n(5,5,h)n(5,6,j)n(5,7,k)n(5,8,g)end
if a1 then n(c,M,m)n(c,1103,l)n(5,9,h)n(5,10,j)n(5,a,k)n(5,e,g)end
if a2 then n(c,F,m)n(5,13,h)n(5,14,j)n(5,r,k)n(5,f,g)end
if S then n(c,2001,l)n(6,1,h)n(6,2,j)n(6,3,k)n(6,4,g)end
if S or U then n(c,0,h)n(c,0,j)n(c,0,k)n(c,0,g)end
if U then n(c,D,m)n(6,5,h)n(6,6,j)n(6,7,k)n(6,8,g)end
if i==u then n(c,P,g)end
if i==P or i==Q or i==R or a6 then n(c,u,z)n(c,u,h)n(c,u,j)n(c,u,k)n(c,u,g)end
if i==P then n(c,Q,l)n(7,-1000,h)n(7,-1000,j)n(7,0,k)n(7,0,g)end
if i==Q then n(c,P,m)n(c,R,l)n(7,q,h)n(7,1635,j)n(7,2925,k)n(7,3500,g)end
if i==R then n(c,Q,m)n(c,3103,l)n(7,4190,h)n(7,5570,j)n(7,7810,k)n(7,9030,g)end
if a6 then n(c,R,m)n(7,9220,h)n(7,10000,j)n(7,10000,k)n(7,10000,g)end
if a3 then n(9,0,T(53,a,9,9))n(c,0,a7)n(10,0,a7)n(8,0,T(2,a,9,9))n(8,1,T(e,a,9,9))n(8,2,T(22,a,9,9))n(8,3,T(c,a,9,9))n(8,4,T(42,a,9,9))n(8,5,T(2,d,9,9))n(8,6,T(e,d,9,9))n(8,7,T(22,d,9,9))n(8,8,T(c,d,9,9))n(8,9,T(42,d,9,9))end
for i=1,32 do
O.setNumber(i,o[i]or 0)O.setBool(i,(o[i+32]or 0)~=0)end
end