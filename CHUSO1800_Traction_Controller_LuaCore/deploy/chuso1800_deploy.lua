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
local t=3
local u=6
local v=12
local w=30
local x=600
local y=30
local z=x
local A=z//y
local B=1
local function C(b,D,E)if b<D then return D end
if b>E then return E end
return b end
function to_u32(F)return string.unpack("I4",string.pack("I4",math.floor(F or 0)&0xFFFFFFFF))end
function get_bits(G,H,I)local J=G>>H
local K=1<<I
local L=K-1
return J&L end
function get_bit(G,H)local J=G>>H
local M=J&1
return M~=0 end
function put_bits(F,H,I)local K=1<<I
local L=K-1
local N=math.floor(F or 0)local O=N&L
return O<<H end
function put_bit(P,H)local M=P and 1 or 0
return M<<H end
function sr_latch(Q,R,S)if S then return false end
if R then return true end
return Q end
local function T(U,V)if V then return math.min(U+1,u)end
return 0 end
local function W(U)return U>=u end
local function X(U,V,Y)if not V then return 0,false end
local Z=U+1
if Z>=Y then return 0,true end
return Z,false end
local function _(a0,a1,V)local a2=V and math.min(a0+A,z)or math.max(a0-B,0)local a3=a1 and a2>0 or a2>=z
return a2,a3 end
local function a4(a5)return a5*b*d*e/(d*math.abs(a5)+e)end
local function a6(a5)return b*d*e*e/((d*math.abs(a5)+e)*(d*math.abs(a5)+e))end
function physics_tick(a7,a8,a9,aa,ab,ac,ad,ae,af,ag,ah,ai,aj,ak,al)local am=a7*9.55*g/h
local an=a9+1
local ao=100000
local ap=4
local aq=150
local ar=l
if not ac and not ad then a8=0 end
if ac then ap=8 end
if ad and an==1 then ap=4 end
if ae then if ag then local as=aa*f*9.55*a*al*aj*g*0.99/h/i
aq=ak+(as-ah)*20
aq=aq*math.min(1,470/(a*math.abs(am))/a4(aq+aj*0.15))else if af and ab<=3 then ar=ak end
if not af then ar=0 end
if ar==0 then ar=math.max(math.min(0,aj+20),aj-20)end
aq=ak+(aj-ar)*0.1 end else ar=ak
if ab==0 then ar=0 end
aq=ak+(aj-ar)*0.1
if ab~=0 and aq>180 then aq=180 end end
if ap==8 then ao=j[an]end
if ap==4 then ao=k[an]end
if aq<20 then aq=20 elseif aq>500 then aq=500 end
local at,au,av,aw,ax=a8/ap,am,ao/ap,aa*0.2,aq*aa
local j=l
local ay=0
for az=1,5 do local a5=j*aw+ax
ay=a4(a5)local aA=a6(a5)local aB=a*aA*aw*au+c+av
local aC=a*ay*au-at+(c+av)*j
if math.abs(aB)>=0.000001 then j=j-aC/aB else if aB>0 then j=j-aC elseif aB<0 then j=j+aC end end end
ay=a4(j*aw+ax)if a8==0 then j=0
ay=0 end
local aD=9.55*a*ay*j
local aE=math.min(aa*f*aD*g/h/i,0)-ai
if aE<0.01 and j<0 then aE=0 end
return j,a*ay*am,f*aD*g*0.99/h/i,a8*j*f/ap*2,aq,aE,j,aq,ay end
function zero_state()return{0,0,0,0,0,0,0,0}end
function decode_state(aF)local aG=to_u32(aF[1])local aH=to_u32(aF[2])return get_bits(aG,0,5),get_bit(aG,5),get_bit(aG,6),get_bit(aG,7),get_bits(aG,8,4),get_bits(aG,12,5),get_bits(aH,0,10),get_bit(aH,19),get_bits(aH,10,3),get_bits(aH,13,3),get_bits(aH,16,3),aF[3],aF[4],aF[5],aF[6],aF[7]end
function encode_state(a9,aI,aJ,aK,aL,aM,aN,aO,aP,aQ,aR,aj,ak,al,aS,aT)local aU=put_bits(a9,0,5)|put_bit(aI,5)|put_bit(aJ,6)|put_bit(aK,7)|put_bits(aL,8,4)|put_bits(aM,12,5)local aV=put_bits(aN,0,10)|put_bits(aP,10,3)|put_bits(aQ,13,3)|put_bits(aR,16,3)|put_bit(aO,19)return{aU,aV,aj or 0,ak or 0,al or 0,aS or 0,aT or 0,0}end
function encode_stateless_in(a7,aW,aX,aY,aa,aZ,a_,b0)return{a7 or 0,aW or 0,aX or 0,aY or 0,aa or 0,aZ or 0,a_ and 1 or 0,b0 and 1 or 0}end
function decode_stateless_out(b1)local b2=to_u32(b1[5])return b1[1],b1[2],b1[3],b1[4],get_bit(b2,0),get_bit(b2,1),get_bit(b2,2),get_bit(b2,3),get_bit(b2,4),get_bit(b2,5),get_bit(b2,6),get_bit(b2,7)end
local function b3(b4)return b4[1],b4[2],b4[3],b4[4],b4[5],C(math.floor(b4[6]or 0),0,7),(b4[7]or 0)~=0,(b4[8]or 0)~=0 end
local function b5(a7,aX,aa,a_)local b6=math.abs(a7)>m
local b7=aX<o
return a_ or aa==0 or b6 or b7 end
local function b8(aZ,a9,b9)local ab=aZ*(b9 and 0 or 1)local ba=b9 and 0 or a9
return ab,ab>=1 and ab<=7,ab>=2 and ab<=7,ab>=3 and ab<=7,ba==0,ba>=0 and ba<=13,ba>=14 and ba<=20,ba==14,ba~=14 end
local function bb(aY,b0)local ai=-math.floor((aY-1)*2)/7.2
return ai,ai<s and b0,math.max(-ai,0)end
local function bc(bd,be,bf,aq,aE,b9,bg)if b9 then return 0,0,0,0,bg end
return bd,be,bf,aq,aE end
local function bh(aI,aJ,aR,aP,aQ,bd)local bi=aJ and n-20 or n
local bj=bd<bi
return W(aR),T(aR,bj),W(aP),T(aP,aI),W(aQ),T(aQ,aJ)end
local function bk(bd)return bd>=-50 and bd<=50 end
local function bl(aI,aS,aM,aq,af,bm)local bn=aI and aS<r
local bo=bn and q or p
local bp=aq>p
local bq=aq>bo and not af
local br,bs=X(aM,bq,w)return bp and bm,bq,br,bs end
local function bt(aI,aJ,aK,af,bu,bv,bw,bx,by,bz,bA,bd,ag,bB,b0,bm,bC,bD,a7,b9)local bE=aI and af
local bF=aI and bA and aK
local bG=af and bw
local bH=math.abs(a7)<t
local bI=bk(bd)and not(af or ag)local bJ=bI and not aK
local bK=bJ or bB and not b0
local bL=aK and aJ and not aI and bw and bI and bH
local bM=bu and bx and bm and bD
local bN=bG and not aJ or bB and aJ and b0
local bO=bv and by and bC and bD
local bP=bv and bz and bD
local bQ=not b0 and aI and aK
local bR=b9 or bQ
local bS=bK or aI and not(bv and bz)or bL or bR
local bT=bK or bB and bm or bP or bR
local bU=not aI and not aJ
local bV=not bw and bU
return sr_latch(aI,bN,bT),sr_latch(aJ,bP,bS),sr_latch(aK,aJ and bw,bE or bU or bR),bM or bO or bV or bF end
local function bW(a9,aL,bX)local br,bs=X(aL,bX,v)local bY=(a9+(bs and 1 or 0))%21
local bZ=bY-a9
return bY,bZ~=0,br end
local function b_(aT,aS,aN,aO,bf,ai,b0,c0)local c1=aO or not b0
local c2=c1 and 0 or ai
local c3,c4=_(aN,aO,c0)return bf*0.2+aT*0.8,math.min(C(c2,aS-0.1,aS+0.02),0),c3,c4 end
function core_tick(b4,aF)local c5,c6,c7,c8,c9,ca,cb,cc,cd,ce,cf,cg,ch,ci,cj,ck=decode_state(aF)local a7,aW,aX,aY,aa,aZ,a_,b0=b3(b4)local b9=b5(a7,aX,aa,a_)local ab,af,bu,bv,bw,bx,by,bz,bA=b8(aZ,c5,b9)local ai,ag,bg=bb(aY,b0)local cl,cm,bf,cn,co,cp,cq,cr,cs=physics_tick(a7,aW,c5,aa,ab,c6,c7,c8,af,ag,cj,ai,cg,ch,ci)local bd,ct,cu,aq,aE=bc(cl,cn,bf,co,cp,b9,bg)local bD,cv,bm,cw,bC,cx=bh(c6,c7,cf,cd,ce,bd)local c0,bq,cy,bB=bl(c6,cj,ca,aq,af,bm)local aI,aJ,aK,bX=bt(c6,c7,c8,af,bu,bv,bw,bx,by,bz,bA,bd,ag,bB,b0,bm,bC,bD,a7,b9)local a9,cz,cA=bW(c5,c9,bX)local aT,aS,aN,aO=b_(ck,cj,cb,cc,cu,ai,b0,c0)local cB=put_bit(cz,0)|put_bit(aI,1)|put_bit(aJ,2)|put_bit(aK,3)|put_bit(af,4)|put_bit(ag,5)|put_bit(bq,6)local b1={bd,ct,aT,aE,cB,0,0,0}local cC=encode_state(a9,aI,aJ,aK,cA,cy,aN,aO,cw,cx,cv,cq,cr,cs,aS,aT)return b1,cC end
function calculateTick(b4,aF)local a={aF[1],aF[2],i2f(aF[3]),i2f(aF[4]),i2f(aF[5]),i2f(aF[6]),i2f(aF[7]),aF[8]}local b1,cC=core_tick(b4,a)local b={cC[1],cC[2],f2i(cC[3]),f2i(cC[4]),f2i(cC[5]),f2i(cC[6]),f2i(cC[7]),cC[8]}return b1,b end
--[[
//# sourceMappingURL=main.lua.map
]]