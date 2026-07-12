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
local function Z(_,U)if U then return math.min(_+z,y)end
return math.max(_-A,0)end
local function a0(_)return _>=y end
local function a1(a2)return a2*b*d*e/(d*math.abs(a2)+e)end
local function a3(a2)return b*d*e*e/((d*math.abs(a2)+e)*(d*math.abs(a2)+e))end
local function a4(a5,a6,a7)return a6*a5+a7 end
local function a8(a5)return a5 end
local function a9(a6,aa,a,ab,a5,a7)return a*a1(a4(a5,a6,a7))*a-aa+(c+ab)*a6 end
local function ac(a6,aa,a,ab,a5,a7)return a*a3(a4(a5,a6,a7))*a8(a5)*a+c+ab end
local function ad(aa,a,ab,a5,a7,ae)local j=ae
for af=1,5 do local ag=ac(j,aa,a,ab,a5,a7)if math.abs(ag)>=0.000001 then j=j-a9(j,aa,a,ab,a5,a7)/ag else if ag>0 then j=j-a9(j,aa,a,ab,a5,a7)elseif ag<0 then j=j+a9(j,aa,a,ab,a5,a7)end end end
return j,a1(a4(a5,j,a7))end
function physics_tick(ah,ai,aj,ak,al,am,an,ao,ap,aq,ar,as,at,au,av)local aw=ah*9.55*g/h
local ax=aj+1
local ay=100000
local az=4
local a7=150
local aA=l
if not am and not an then ai=0 end
if am then az=8 end
if an and ax==1 then az=4 end
if ao then if aq then local aB=ak*f*9.55*a*av*at*g*0.99/h/i
a7=au+(aB-ar)*20
a7=a7*math.min(1,470/(a*math.abs(aw))/a1(a7+at*0.15))else if ap and al<=3 then aA=au end
if not ap then aA=0 end
if aA==0 then aA=math.max(math.min(0,at+20),at-20)end
a7=au+(at-aA)*0.1 end else aA=au
if al==0 then aA=0 end
a7=au+(at-aA)*0.1
if al~=0 and a7>180 then a7=180 end end
if az==8 then ay=j[ax]end
if az==4 then ay=k[ax]end
if a7<20 then a7=20 elseif a7>500 then a7=500 end
local j,aC=ad(ai/az,aw,ay/az,ak*0.2,a7*ak,l)if ai==0 then j=0
aC=0 end
local aD=9.55*a*aC*j
local aE=math.min(ak*f*aD*g/h/i,0)-as
if aE<0.01 and j<0 then aE=0 end
return j,a*aC*aw,f*aD*g*0.99/h/i,ai*j*f/az*2,a7,aE,j,a7,aC end
function zero_state()return{0,0,0,0,0,0,0,0}end
function decode_state(aF)local aG=to_u32(aF[1])local aH=to_u32(aF[2])return get_bits(aG,0,5),get_bit(aG,5),get_bit(aG,6),get_bit(aG,7),get_bits(aG,8,4),get_bits(aG,12,5),get_bits(aH,0,10),get_bits(aH,10,3),get_bits(aH,13,3),get_bits(aH,16,3),aF[3],aF[4],aF[5],aF[6],aF[7]end
function encode_state(aj,aI,aJ,aK,aL,aM,aN,aO,aP,aQ,at,au,av,aR,aS)local aT=put_bits(aj,0,5)|put_bit(aI,5)|put_bit(aJ,6)|put_bit(aK,7)|put_bits(aL,8,4)|put_bits(aM,12,5)local aU=put_bits(aN,0,10)|put_bits(aO,10,3)|put_bits(aP,13,3)|put_bits(aQ,16,3)return{aT,aU,at or 0,au or 0,av or 0,aR or 0,aS or 0,0}end
function encode_stateless_in(ah,aV,aW,aX,ak,aY,aZ,a_)return{ah or 0,aV or 0,aW or 0,aX or 0,ak or 0,aY or 0,aZ and 1 or 0,a_ and 1 or 0}end
function decode_stateless_out(b0)local b1=to_u32(b0[5])return b0[1],b0[2],b0[3],b0[4],get_bit(b1,0),get_bit(b1,1),get_bit(b1,2),get_bit(b1,3),get_bit(b1,4),get_bit(b1,5),get_bit(b1,6),get_bit(b1,7)end
local function b2(b3)return b3[1],b3[2],b3[3],b3[4],b3[5],B(math.floor(b3[6]or 0),0,7),(b3[7]or 0)~=0,(b3[8]or 0)~=0 end
local function b4(ah,aW,ak,aZ)local b5=math.abs(ah)>m
local b6=aW<o
return aZ or ak==0 or b5 or b6 end
local function b7(aY,aj,b8)local al=aY*(b8 and 0 or 1)local b9=b8 and 0 or aj
return al,al>=1 and al<=7,al>=2 and al<=7,al>=3 and al<=7,b9>=0 and b9<=1,b9>=0 and b9<=13,b9>=14 and b9<=20,b9==14,b9~=14 end
local function ba(aX,a_)local as=-math.floor((aX-1)*2)/7.2
return as,as<s and a_,math.max(-as,0)end
local function bb(bc,bd,be,a7,aE,b8,bf)if b8 then return 0,0,0,0,bf end
return bc,bd,be,a7,aE end
local function bg(aI,aJ,aQ,aO,aP,bc)local bh=aJ and n-20 or n
local bi=bc<bh
return V(aQ),S(aQ,bi),V(aO),S(aO,aI),V(aP),S(aP,aJ)end
local function bj(aI,aR,aM,a7,ap,bk)local bl=aI and aR<r
local bm=bl and q or p
local bn=a7>p
local bo=a7>bm and not ap
local bp,bq=W(aM,bo,v)return bn and bk,bo,bp,bq end
local function br(aI,aJ,aK,ap,bs,bt,bu,bv,bw,bx,by,bc,aq,bz,a_,bk,bA,bB)local bC=aI and ap
local bD=aI and by and aK
local bE=ap and bu
local bF=bc>=-50 and bc<=50
local bG=bF and not(ap or aq)local bH=bG and not aK
local bI=bH or bz and not a_
local bJ=bs and bv and bk and bB
local bK=bE and not aJ or bz and aJ
local bL=bt and bw and bA and bB
local bM=bt and bx and bB
local bN=bI or aI and not(bt and bx)local bO=bI or bz and bk or bM
local bP=not aI and not aJ
local bQ=not bu and bP
return sr_latch(aI,bK,bO),sr_latch(aJ,bM,bN),sr_latch(aK,aJ and bu,bC or bP),bJ or bL or bQ or bD end
local function bR(aj,aL,bS)local bp,bq=W(aL,bS,u)local bT=(aj+(bq and 1 or 0))%21
local bU=bT-aj
return bT,not(bU>=0 and bU<=1),bp end
local function bV(aS,aR,aN,be,as,a_,bW)local bX=a0(aN)or not a_
local bY=bX and 0 or as
return be*0.2+aS*0.8,math.min(B(bY,aR-0.1,aR+0.02),0),Z(aN,bW)end
function core_tick(b3,aF)local bZ,b_,c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,ca,cb,cc=decode_state(aF)local ah,aV,aW,aX,ak,aY,aZ,a_=b2(b3)local b8=b4(ah,aW,ak,aZ)local al,ap,bs,bt,bu,bv,bw,bx,by=b7(aY,bZ,b8)local as,aq,bf=ba(aX,a_)local cd,ce,be,cf,cg,ch,ci,cj,ck=physics_tick(ah,aV,bZ,ak,al,b_,c0,c1,ap,aq,cb,as,c8,c9,ca)local bc,cl,cm,a7,aE=bb(cd,cf,be,cg,ch,b8,bf)local bB,cn,bk,co,bA,cp=bg(b_,c0,c7,c5,c6,bc)local bW,bo,cq,bz=bj(b_,cb,c3,a7,ap,bk)local aI,aJ,aK,bS=br(b_,c0,c1,ap,bs,bt,bu,bv,bw,bx,by,bc,aq,bz,a_,bk,bA,bB)local aj,cr,cs=bR(bZ,c2,bS)local aS,aR,aN=bV(cc,cb,c4,cm,as,a_,bW)local ct=put_bit(cr,0)|put_bit(aI,1)|put_bit(aJ,2)|put_bit(aK,3)|put_bit(ap,4)|put_bit(aq,5)|put_bit(bo,6)local b0={bc,cl,aS,aE,ct,0,0,0}local cu=encode_state(aj,aI,aJ,aK,cs,cq,aN,co,cp,cn,ci,cj,ck,aR,aS)return b0,cu end
function calculateTick(b3,aF)local a={aF[1],aF[2],i2f(aF[3]),i2f(aF[4]),i2f(aF[5]),i2f(aF[6]),i2f(aF[7]),aF[8]}local b0,cu=core_tick(b3,a)local b={cu[1],cu[2],f2i(cu[3]),f2i(cu[4]),f2i(cu[5]),f2i(cu[6]),f2i(cu[7]),cu[8]}return b0,b end
--[[
//# sourceMappingURL=main.lua.map
]]