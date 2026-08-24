function i2f(b)local c=('f'):unpack(('I4'):pack(b&0xFFFFFFFF))return c end
function f2i(b)local c=('I4'):unpack(('f'):pack(b))return c end
s1={0,0,0,0,0,0,0,0}s2={0,0,0,0,0,0,0,0}function onTick()local b,c,g,d={},{},{},{}local h,e,i
for a=1,8 do b[a]=input.getNumber(a)c[a]=input.getNumber(a+8)g[a]=input.getNumber(a+16)d[a]=f2i(input.getNumber(a+24))end
local f=true
for a=1,8 do f=f and s2[a]==d[a]end
if not f then i,s1=calculateTick(c,d)end
h,e=calculateTick(b,s1)for a=1,8 do output.setNumber(a,g[a])output.setNumber(a+8,i2f(d[a]))output.setNumber(a+16,h[a])output.setNumber(a+24,i2f(e[a]))end
s2=s1
s1=e end
local N=78.941
local aj=0.05696
local _=400
local ak=0.12
local aa=0.30
local ab=1.00-aa
local aA=390
local al=ab*aA
local aB=470
local U=4
local V=5.60
local W=0.86/2
local ac=35*1000
local aC={7.428,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334,0,2.568,1.734,1.218,0.7570,0.4110,0.1334}local aD={0,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334,3.714,2.568,1.734,1.218,0.7570,0.4110,0.1334}local am=200
local aE=property.getNumber("Over Speed Th. [m/s]")local an=property.getNumber("Power Limit Current [A]")local aF=property.getNumber("Field Control Current [A]")local aG=4
local ao=300
local aH=400
local aI=-0.1
local aJ=-0.05
local aK=3
local ap=6
local aL=12
local aM=30
local aN=600
local aO=30
local ad=aN
local aP=ad//aO
local aQ=1
local function aq(j,k,l)if j<k then return k end
if j>l then return l end
return j end
function to_u32(j)return string.unpack("I4",string.pack("I4",math.floor(j or 0)&0xFFFFFFFF))end
function get_bits(j,k,l)local m=j>>k
local n=1<<l
local o=n-1
return m&o end
function get_bit(j,k)local l=j>>k
local m=l&1
return m~=0 end
function put_bits(j,k,l)local m=1<<l
local n=m-1
local o=math.floor(j or 0)local p=o&n
return p<<k end
function put_bit(j,k)local l=j and 1 or 0
return l<<k end
function sr_latch(j,k,l)if l then return false end
if k then return true end
return j end
local function ae(j,k)if k then return math.min(j+1,ap)end
return 0 end
local function af(j)return j>=ap end
local function ar(j,k,l)if not k then return 0,false end
local m=j+1
if m>=l then return 0,true end
return m,false end
local function aR(j,k,l)local m=l and math.min(j+aP,ad)or math.max(j-aQ,0)local n=k and m>0 or m>=ad
return m,n end
local function ag(j)return aj*j/(_+math.abs(j))end
local function aS(j)local k=_+math.abs(j)return aj*_/(k*k)end
function physics_tick(j,k,l,m,n,o,p,t,w,x,A,B,u,s,G)local z=j*V/W
local C=l+1
local D=100000
local y=4
local r=150
local E=am
if not o and not p then k=0 end
if o then y=8 end
if p and C==1 then y=4 end
if t then if x then local O=m*U*N*G*u*V*0.99/W/ac
r=s+(O-A)*20
local H=ag(m*(r+aa*u))if math.abs(z)>0.000001 and math.abs(H)>0.000001 then r=r*math.min(1,aB/(N*math.abs(z*H)))end else if w and n<=3 then E=s/ab end
if w and n>3 then E=aF end
if not w then E=0 end
if E==0 then E=math.max(math.min(0,u+20),u-20)end
r=s+(u-E)*0.1 end else if n==0 then r=s+u*0.1 else r=s+(ab*u-s)*0.1
if r>al then r=al end end end
if y==8 then D=aC[C]end
if y==4 then D=aD[C]end
if r<20 then r=20 elseif r>500 then r=500 end
local R,K=k/y,D/y
local L,M=m*aa,r*m
local q=am
local v=0
for O=1,5 do local H=q*L+M
v=ag(H)local P=aS(H)local J=N*P*L*z+ak+K
local I=N*v*z-R+(ak+K)*q
if math.abs(J)>=0.000001 then q=q-I/J else if J>0 then q=q-I elseif J<0 then q=q+I end end end
v=ag(q*L+M)if k==0 then q=0
v=0 end
local Q=N*v*q
local F=math.min(m*U*Q*V/W/ac,0)-B
if F<0.01 and q<0 then F=0 end
return q,N*v*z,U*Q*V*0.99/W/ac,k*q*U/y*2,r,F,q,r,v end
function zero_state()return{0,0,0,0,0,0,0,0}end
function decode_state(j)local k=to_u32(j[1])local l=to_u32(j[2])return get_bits(k,0,5),get_bit(k,5),get_bit(k,6),get_bit(k,7),get_bits(k,8,4),get_bits(k,12,5),get_bits(l,0,10),get_bit(l,19),get_bits(l,10,3),get_bits(l,13,3),get_bits(l,16,3),j[3],j[4],j[5],j[6],j[7]end
function encode_state(j,k,l,m,n,o,p,t,w,x,A,B,u,s,G,z)local C=put_bits(j,0,5)|put_bit(k,5)|put_bit(l,6)|put_bit(m,7)|put_bits(n,8,4)|put_bits(o,12,5)local D=put_bits(p,0,10)|put_bits(w,10,3)|put_bits(x,13,3)|put_bits(A,16,3)|put_bit(t,19)return{C,D,B or 0,u or 0,s or 0,G or 0,z or 0,0}end
function encode_stateless_in(j,k,l,m,n,o,p,t)return{j or 0,k or 0,l or 0,m or 0,n or 0,o or 0,p and 1 or 0,t and 1 or 0}end
function decode_stateless_out(j)local k=to_u32(j[5])return j[1],j[2],j[3],j[4],get_bit(k,0),get_bit(k,1),get_bit(k,2),get_bit(k,3),get_bit(k,4),get_bit(k,5),get_bit(k,6),get_bit(k,7)end
local function aT(j)return j[1],j[2],j[3],j[4],j[5],aq(math.floor(j[6]or 0),0,7),(j[7]or 0)~=0,(j[8]or 0)~=0 end
local function aU(j,k,l,m)local n=math.abs(j)>aE
local o=k<aG
return m or l==0 or n or o end
local function aV(j,k,l)local m=j*(l and 0 or 1)local n=l and 0 or k
return m,m>=1 and m<=7,m>=2 and m<=7,m>=3 and m<=7,n==0,n>=0 and n<=13,n>=14 and n<=20,n==14,n~=14 end
local function aW(j,k)local l=-math.floor((j-1)*2)/7.2
return l,l<aJ and k,math.max(-l,0)end
local function aX(j,k,l,m,n,o,p)if o then return 0,0,0,0,p end
return j,k,l,m,n end
local function aY(j,k,l,m,n,o)local p=k and an-20 or an
local t=o<p
return af(l),ae(l,t),af(m),ae(m,j),af(n),ae(n,k)end
local function aZ(j)return j>=-50 and j<=50 end
local function a_(j,k,l,m,n,o)local p=j and k<aI
local t=p and aH or ao
local w=m>ao
local x=m>t and not n
local A,B=ar(l,x,aM)return w and o,x,A,B end
local function ba(j,k,l,m,n,o,p,t,w,x,A,B,u,s,G,z,C,D,y,r)local E=j and m
local R=j and A and l
local K=m and p
local L=math.abs(y)<aK
local M=aZ(B)and not(m or u)local q=M and not l
local v=q or s and not G
local Q=l and k and not j and p and M and L
local F=n and t and z and D
local O=K and not k or s and k and G
local H=o and w and C and D
local P=o and x and D
local J=not G and j and l
local I=r or J
local ah=v or j and not(o and x)or Q or I
local ai=v or s and z or P or I
local S=not j and not k
local T=not p and S
local X=sr_latch(j,O,ai)local Y=sr_latch(k,P,ah)local as=(j or k)and not X and not Y
return X,Y,sr_latch(l,k and p,E or S or I),F or H or T or R,as end
local function bb(j,k,l)local m,n=ar(k,l,aL)local o=(j+(n and 1 or 0))%21
local p=o-j
return o,p~=0,m end
local function bc(j,k,l,m,n,o,p,t,w)local x=m or not p
local A=x and 0 or o
local B,u=aR(l,m,t)local s=w and 0 or n*0.2+j*0.8
return s,math.min(aq(A,k-0.1,k+0.02),0),B,u end
function core_tick(j,k)local l,m,n,o,p,t,w,x,A,B,u,s,G,z,C,D=decode_state(k)local y,r,E,R,K,L,M,q=aT(j)local v=aU(y,E,K,M)local Q,F,O,H,P,J,I,ah,ai=aV(L,l,v)local S,T,X=aW(R,q)local Y,as,bd,be,bf,bg,bh,bi,bj=physics_tick(y,r,l,K,Q,m,n,o,F,T,C,S,s,G,z)local Z,at,bk,bl,bm=aX(Y,be,bd,bf,bg,v,X)local bn,bo,au,bp,bq,br=aY(m,n,u,A,B,Z)local bs,bt,bu,bv=a_(m,C,t,bl,F,au)local av,aw,ax,bw,ay=ba(m,n,o,F,O,H,P,J,I,ah,ai,Z,T,bv,q,au,bq,bn,y,v)if ay then Z,at=0,0 end
local bx,by,bz=bb(l,p,bw)local az,bA,bB,bC=bc(D,C,w,x,bk,S,q,bs,v or ay)local bD=put_bit(by,0)|put_bit(av,1)|put_bit(aw,2)|put_bit(ax,3)|put_bit(F,4)|put_bit(T,5)|put_bit(bt,6)local bE={Z,at,az,bm,bD,0,0,0}local bF=encode_state(bx,av,aw,ax,bz,bu,bB,bC,bp,br,bo,bh,bi,bj,bA,az)return bE,bF end
function calculateTick(bI,bG)local bJ={bG[1],bG[2],i2f(bG[3]),i2f(bG[4]),i2f(bG[5]),i2f(bG[6]),i2f(bG[7]),bG[8]}local bK,bH=core_tick(bI,bJ)local bL={bH[1],bH[2],f2i(bH[3]),f2i(bH[4]),f2i(bH[5]),f2i(bH[6]),f2i(bH[7]),bH[8]}return bK,bL end
--[[
//# sourceMappingURL=main.lua.map
]]