function i2f(a)local b=('f'):unpack(('I4'):pack(a&0xFFFFFFFF))return b end
function f2i(b)local a=('I4'):unpack(('f'):pack(b))return a end
s1={0,0,0,0,0,0,0,0}s2={0,0,0,0,0,0,0,0}function onTick()local c,d,e,f={},{},{},{}local g,h,i
for j=1,8 do c[j]=input.getNumber(j)d[j]=input.getNumber(j+8)e[j]=input.getNumber(j+16)f[j]=f2i(input.getNumber(j+24))end
local k=true
for j=1,8 do k=k and s2[j]==f[j]end
if not k then i,s1=calculateTick(d,f)end
g,h=calculateTick(c,s1)for j=1,8 do output.setNumber(j,e[j])output.setNumber(j+8,i2f(f[j]))output.setNumber(j+16,g[j])output.setNumber(j+24,i2f(h[j]))end
s2=s1
s1=h end
local a=12.16
local b=0.00029
local c=0.07
local d=0.85
local e=150
local f=4
local g=5.31
local h=0.86/2
local i=35*1000
local j={7.428,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334,0,2.568,1.734,1.218,0.7570,0.4110,0.1334}local k={0,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334,3.714,2.568,1.734,1.218,0.7570,0.4110,0.1334}local l=200
local m=property.getNumber("Over Speed Th. [m/s]")local n=property.getNumber("Power Limit Current [A]")local o=4
local p=300
local q=400
local r=-0.1
local s=-0.05
local t=6
local u=12
local v=30
local w=600
local x=30
local y=w
local z=y//x
local A=1
local function B(b,C,D)if b<C then return C end
if b>D then return D end
return b end
function to_u32(E)return string.unpack("I4",string.pack("I4",math.floor(E or 0)&0xFFFFFFFF))end
function get_bits(F,G,H)local I=F>>G
local J=1<<H
local K=J-1
return I&K end
function get_bit(F,G)local I=F>>G
local L=I&1
return L~=0 end
function put_bits(E,G,H)local J=1<<H
local K=J-1
local M=math.floor(E or 0)local N=M&K
return N<<G end
function put_bit(O,G)local L=O and 1 or 0
return L<<G end
function sr_latch(P,Q,R)if R then return false end
if Q then return true end
return P end
local function S(T,U)if U then return math.min(T+1,t)end
return 0 end
local function V(T)return T>=t end
local function W(T,U,X)if not U then return 0,false end
local Y=T+1
if Y>=X then return 0,true end
return Y,false end
local function Z(_,a0,U)local a1=U and math.min(_+z,y)or math.max(_-A,0)local a2=a0 and a1>0 or a1>=y
return a1,a2 end
local function a3(a4)return a4*b*d*e/(d*math.abs(a4)+e)end
local function a5(a4)return b*d*e*e/((d*math.abs(a4)+e)*(d*math.abs(a4)+e))end
local function a6(a7,a8,a9)return a8*a7+a9 end
local function aa(a7)return a7 end
local function ab(a8,ac,a,ad,a7,a9)return a*a3(a6(a7,a8,a9))*a-ac+(c+ad)*a8 end
local function ae(a8,ac,a,ad,a7,a9)return a*a5(a6(a7,a8,a9))*aa(a7)*a+c+ad end
local function af(ac,a,ad,a7,a9,ag)local j=ag
for ah=1,5 do local ai=ae(j,ac,a,ad,a7,a9)if math.abs(ai)>=0.000001 then j=j-ab(j,ac,a,ad,a7,a9)/ai else if ai>0 then j=j-ab(j,ac,a,ad,a7,a9)elseif ai<0 then j=j+ab(j,ac,a,ad,a7,a9)end end end
return j,a3(a6(a7,j,a9))end
function physics_tick(aj,ak,al,am,an,ao,ap,aq,ar,as,at,au,av,aw,ax)local ay=aj*9.55*g/h
local az=al+1
local aA=100000
local aB=4
local a9=150
local aC=l
if not ao and not ap then ak=0 end
if ao then aB=8 end
if ap and az==1 then aB=4 end
if aq then if as then local aD=am*f*9.55*a*ax*av*g*0.99/h/i
a9=aw+(aD-at)*20
a9=a9*math.min(1,470/(a*math.abs(ay))/a3(a9+av*0.15))else if ar and an<=3 then aC=aw end
if not ar then aC=0 end
if aC==0 then aC=math.max(math.min(0,av+20),av-20)end
a9=aw+(av-aC)*0.1 end else aC=aw
if an==0 then aC=0 end
a9=aw+(av-aC)*0.1
if an~=0 and a9>180 then a9=180 end end
if aB==8 then aA=j[az]end
if aB==4 then aA=k[az]end
if a9<20 then a9=20 elseif a9>500 then a9=500 end
local j,aE=af(ak/aB,ay,aA/aB,am*0.2,a9*am,l)if ak==0 then j=0
aE=0 end
local aF=9.55*a*aE*j
local aG=math.min(am*f*aF*g/h/i,0)-au
if aG<0.01 and j<0 then aG=0 end
return j,a*aE*ay,f*aF*g*0.99/h/i,ak*j*f/aB*2,a9,aG,j,a9,aE end
function zero_state()return{0,0,0,0,0,0,0,0}end
function decode_state(aH)local aI=to_u32(aH[1])local aJ=to_u32(aH[2])return get_bits(aI,0,5),get_bit(aI,5),get_bit(aI,6),get_bit(aI,7),get_bits(aI,8,4),get_bits(aI,12,5),get_bits(aJ,0,10),get_bit(aJ,19),get_bits(aJ,10,3),get_bits(aJ,13,3),get_bits(aJ,16,3),aH[3],aH[4],aH[5],aH[6],aH[7]end
function encode_state(al,aK,aL,aM,aN,aO,aP,aQ,aR,aS,aT,av,aw,ax,aU,aV)local aW=put_bits(al,0,5)|put_bit(aK,5)|put_bit(aL,6)|put_bit(aM,7)|put_bits(aN,8,4)|put_bits(aO,12,5)local aX=put_bits(aP,0,10)|put_bits(aR,10,3)|put_bits(aS,13,3)|put_bits(aT,16,3)|put_bit(aQ,19)return{aW,aX,av or 0,aw or 0,ax or 0,aU or 0,aV or 0,0}end
function encode_stateless_in(aj,aY,aZ,a_,am,b0,b1,b2)return{aj or 0,aY or 0,aZ or 0,a_ or 0,am or 0,b0 or 0,b1 and 1 or 0,b2 and 1 or 0}end
function decode_stateless_out(b3)local b4=to_u32(b3[5])return b3[1],b3[2],b3[3],b3[4],get_bit(b4,0),get_bit(b4,1),get_bit(b4,2),get_bit(b4,3),get_bit(b4,4),get_bit(b4,5),get_bit(b4,6),get_bit(b4,7)end
local function b5(b6)return b6[1],b6[2],b6[3],b6[4],b6[5],B(math.floor(b6[6]or 0),0,7),(b6[7]or 0)~=0,(b6[8]or 0)~=0 end
local function b7(aj,aZ,am,b1)local b8=math.abs(aj)>m
local b9=aZ<o
return b1 or am==0 or b8 or b9 end
local function ba(b0,al,bb)local an=b0*(bb and 0 or 1)local bc=bb and 0 or al
return an,an>=1 and an<=7,an>=2 and an<=7,an>=3 and an<=7,bc==0,bc>=0 and bc<=13,bc>=14 and bc<=20,bc==14,bc~=14 end
local function bd(a_,b2)local au=-math.floor((a_-1)*2)/7.2
return au,au<s and b2,math.max(-au,0)end
local function be(bf,bg,bh,a9,aG,bb,bi)if bb then return 0,0,0,0,bi end
return bf,bg,bh,a9,aG end
local function bj(aK,aL,aT,aR,aS,bf)local bk=aL and n-20 or n
local bl=bf<bk
return V(aT),S(aT,bl),V(aR),S(aR,aK),V(aS),S(aS,aL)end
local function bm(aK,aU,aO,a9,ar,bn)local bo=aK and aU<r
local bp=bo and q or p
local bq=a9>p
local br=a9>bp and not ar
local bs,bt=W(aO,br,v)return bq and bn,br,bs,bt end
local function bu(aK,aL,aM,ar,bv,bw,bx,by,bz,bA,bB,bf,as,bC,b2,bn,bD,bE)local bF=aK and ar
local bG=aK and bB and aM
local bH=ar and bx
local bI=bf>=-50 and bf<=50
local bJ=bI and not(ar or as)local bK=bJ and not aM
local bL=bK or bC and not b2
local bM=bv and by and bn and bE
local bN=bH and not aL or bC and aL
local bO=bw and bz and bD and bE
local bP=bw and bA and bE
local bQ=bL or aK and not(bw and bA)local bR=bL or bC and bn or bP
local bS=not aK and not aL
local bT=not bx and bS
return sr_latch(aK,bN,bR),sr_latch(aL,bP,bQ),sr_latch(aM,aL and bx,bF or bS),bM or bO or bT or bG end
local function bU(al,aN,bV)local bs,bt=W(aN,bV,u)local bW=(al+(bt and 1 or 0))%21
local bX=bW-al
return bW,bX~=0,bs end
local function bY(aV,aU,aP,aQ,bh,au,b2,bZ)local b_=aQ or not b2
local c0=b_ and 0 or au
local c1,c2=Z(aP,aQ,bZ)return bh*0.2+aV*0.8,math.min(B(c0,aU-0.1,aU+0.02),0),c1,c2 end
function core_tick(b6,aH)local c3,c4,c5,c6,c7,c8,c9,ca,cb,cc,cd,ce,cf,cg,ch,ci=decode_state(aH)local aj,aY,aZ,a_,am,b0,b1,b2=b5(b6)local bb=b7(aj,aZ,am,b1)local an,ar,bv,bw,bx,by,bz,bA,bB=ba(b0,c3,bb)local au,as,bi=bd(a_,b2)local cj,ck,bh,cl,cm,cn,co,cp,cq=physics_tick(aj,aY,c3,am,an,c4,c5,c6,ar,as,ch,au,ce,cf,cg)local bf,cr,cs,a9,aG=be(cj,cl,bh,cm,cn,bb,bi)local bE,ct,bn,cu,bD,cv=bj(c4,c5,cd,cb,cc,bf)local bZ,br,cw,bC=bm(c4,ch,c8,a9,ar,bn)local aK,aL,aM,bV=bu(c4,c5,c6,ar,bv,bw,bx,by,bz,bA,bB,bf,as,bC,b2,bn,bD,bE)local al,cx,cy=bU(c3,c7,bV)local aV,aU,aP,aQ=bY(ci,ch,c9,ca,cs,au,b2,bZ)local cz=put_bit(cx,0)|put_bit(aK,1)|put_bit(aL,2)|put_bit(aM,3)|put_bit(ar,4)|put_bit(as,5)|put_bit(br,6)local b3={bf,cr,aV,aG,cz,0,0,0}local cA=encode_state(al,aK,aL,aM,cy,cw,aP,aQ,cu,cv,ct,co,cp,cq,aU,aV)return b3,cA end
function calculateTick(b6,aH)local a={aH[1],aH[2],i2f(aH[3]),i2f(aH[4]),i2f(aH[5]),i2f(aH[6]),i2f(aH[7]),aH[8]}local b3,cA=core_tick(b6,a)local b={cA[1],cA[2],f2i(cA[3]),f2i(cA[4]),f2i(cA[5]),f2i(cA[6]),f2i(cA[7]),cA[8]}return b3,b end
--[[
//# sourceMappingURL=main.lua.map
]]