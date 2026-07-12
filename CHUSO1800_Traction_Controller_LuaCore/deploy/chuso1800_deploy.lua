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
function get_bits(F,G,H)return F>>G&1<<H-1 end
function get_bit(F,G)return F>>G&1~=0 end
function put_bits(E,G,H)return math.floor(E or 0)&1<<H-1<<G end
function put_bit(I,G)return I and 1 or 0<<G end
function sr_latch(J,K,L)if L then return false end
if K then return true end
return J end
local function M(N,O)if O then return math.min(N+1,t)end
return 0 end
local function P(N)return N>=t end
local function Q(N,O,R)if not O then return 0,false end
local S=N+1
if S>=R then return 0,true end
return S,false end
local function T(U,O)if O then return math.min(U+z,y)end
return math.max(U-A,0)end
local function V(U)return U>=y end
local function W(X)return X*b*d*e/(d*math.abs(X)+e)end
local function Y(X)return b*d*e*e/((d*math.abs(X)+e)*(d*math.abs(X)+e))end
local function Z(_,a0,a1)return a0*_+a1 end
local function a2(_)return _ end
local function a3(a0,a4,a,a5,_,a1)return a*W(Z(_,a0,a1))*a-a4+(c+a5)*a0 end
local function a6(a0,a4,a,a5,_,a1)return a*Y(Z(_,a0,a1))*a2(_)*a+c+a5 end
local function a7(a4,a,a5,_,a1,a8)local j=a8
for a9=1,5 do local aa=a6(j,a4,a,a5,_,a1)if math.abs(aa)>=0.000001 then j=j-a3(j,a4,a,a5,_,a1)/aa else if aa>0 then j=j-a3(j,a4,a,a5,_,a1)elseif aa<0 then j=j+a3(j,a4,a,a5,_,a1)end end end
return j,W(Z(_,j,a1))end
function physics_tick(ab,ac,ad,ae,af,ag,ah,ai,aj,ak,al,am,an,ao,ap)local aq=ab*9.55*g/h
local ar=ad+1
local as=100000
local at=4
local a1=150
local au=l
if not ag and not ah then ac=0 end
if ag then at=8 end
if ah and ar==1 then at=4 end
if ai then if ak then local av=ae*f*9.55*a*ap*an*g*0.99/h/i
a1=ao+(av-al)*20
a1=a1*math.min(1,470/(a*math.abs(aq))/W(a1+an*0.15))else if aj and af<=3 then au=ao end
if not aj then au=0 end
if au==0 then au=math.max(math.min(0,an+20),an-20)end
a1=ao+(an-au)*0.1 end else au=ao
if af==0 then au=0 end
a1=ao+(an-au)*0.1
if af~=0 and a1>180 then a1=180 end end
if at==8 then as=j[ar]end
if at==4 then as=k[ar]end
if a1<20 then a1=20 elseif a1>500 then a1=500 end
local j,aw=a7(ac/at,aq,as/at,ae*0.2,a1*ae,l)if ac==0 then j=0
aw=0 end
local ax=9.55*a*aw*j
local ay=math.min(ae*f*ax*g/h/i,0)-am
if ay<0.01 and j<0 then ay=0 end
return j,a*aw*aq,f*ax*g*0.99/h/i,ac*j*f/at*2,a1,ay,j,a1,aw end
function zero_state()return{0,0,0,0,0,0,0,0}end
function decode_state(az)local aA=to_u32(az[1])local aB=to_u32(az[2])return get_bits(aA,0,5),get_bit(aA,5),get_bit(aA,6),get_bit(aA,7),get_bits(aA,8,4),get_bits(aA,12,5),get_bits(aB,0,10),get_bits(aB,10,3),get_bits(aB,13,3),get_bits(aB,16,3),az[3],az[4],az[5],az[6],az[7]end
function encode_state(ad,aC,aD,aE,aF,aG,aH,aI,aJ,aK,an,ao,ap,aL,aM)local aN=put_bits(ad,0,5)|put_bit(aC,5)|put_bit(aD,6)|put_bit(aE,7)|put_bits(aF,8,4)|put_bits(aG,12,5)local aO=put_bits(aH,0,10)|put_bits(aI,10,3)|put_bits(aJ,13,3)|put_bits(aK,16,3)return{aN,aO,an or 0,ao or 0,ap or 0,aL or 0,aM or 0,0}end
function encode_stateless_in(ab,aP,aQ,aR,ae,aS,aT,aU)return{ab or 0,aP or 0,aQ or 0,aR or 0,ae or 0,aS or 0,aT and 1 or 0,aU and 1 or 0}end
function decode_stateless_out(aV)local aW=to_u32(aV[5])return aV[1],aV[2],aV[3],aV[4],get_bit(aW,0),get_bit(aW,1),get_bit(aW,2),get_bit(aW,3),get_bit(aW,4),get_bit(aW,5),get_bit(aW,6),get_bit(aW,7)end
local function aX(aY)return aY[1],aY[2],aY[3],aY[4],aY[5],B(math.floor(aY[6]or 0),0,7),(aY[7]or 0)~=0,(aY[8]or 0)~=0 end
local function aZ(ab,aQ,ae,aT)local a_=math.abs(ab)>m
local b0=aQ<o
return aT or ae==0 or a_ or b0 end
local function b1(aS,ad,b2)local af=aS*(b2 and 0 or 1)local b3=b2 and 0 or ad
return af,af>=1 and af<=7,af>=2 and af<=7,af>=3 and af<=7,b3>=0 and b3<=1,b3>=0 and b3<=13,b3>=14 and b3<=20,b3==14,b3~=14 end
local function b4(aR,aU)local am=-math.floor((aR-1)*2)/7.2
return am,am<s and aU,math.max(-am,0)end
local function b5(b6,b7,b8,a1,ay,b2,b9)if b2 then return 0,0,0,0,b9 end
return b6,b7,b8,a1,ay end
local function ba(aC,aD,aK,aI,aJ,b6)local bb=aD and n-20 or n
local bc=b6<bb
return P(aK),M(aK,bc),P(aI),M(aI,aC),P(aJ),M(aJ,aD)end
local function bd(aC,aL,aG,a1,aj,be)local bf=aC and aL<r
local bg=bf and q or p
local bh=a1>p
local bi=a1>bg and not aj
local bj,bk=Q(aG,bi,v)return bh and be,bi,bj,bk end
local function bl(aC,aD,aE,aj,bm,bn,bo,bp,bq,br,bs,b6,ak,bt,aU,be,bu,bv)local bw=aC and aj
local bx=aC and bs and aE
local by=aj and bo
local bz=b6>=-50 and b6<=50
local bA=bz and not(aj or ak)local bB=bA and not aE
local bC=bB or bt and not aU
local bD=bm and bp and be and bv
local bE=by and not aD or bt and aD
local bF=bn and bq and bu and bv
local bG=bn and br and bv
local bH=bC or aC and not(bn and br)local bI=bC or bt and be or bG
local bJ=not aC and not aD
local bK=not bo and bJ
return sr_latch(aC,bE,bI),sr_latch(aD,bG,bH),sr_latch(aE,aD and bo,bw or bJ),bD or bF or bK or bx end
local function bL(ad,aF,bM)local bj,bk=Q(aF,bM,u)local bN=(ad+(bk and 1 or 0))%21
local bO=bN-ad
return bN,not(bO>=0 and bO<=1),bj end
local function bP(aM,aL,aH,b8,am,aU,bQ)local bR=V(aH)or not aU
local bS=bR and 0 or am
return b8*0.2+aM*0.8,math.min(B(bS,aL-0.1,aL+0.02),0),T(aH,bQ)end
function core_tick(aY,az)local bT,bU,bV,bW,bX,bY,bZ,b_,c0,c1,c2,c3,c4,c5,c6=decode_state(az)local ab,aP,aQ,aR,ae,aS,aT,aU=aX(aY)local b2=aZ(ab,aQ,ae,aT)local af,aj,bm,bn,bo,bp,bq,br,bs=b1(aS,bT,b2)local am,ak,b9=b4(aR,aU)local c7,c8,b8,c9,ca,cb,cc,cd,ce=physics_tick(ab,aP,bT,ae,af,bU,bV,bW,aj,ak,c5,am,c2,c3,c4)local b6,cf,cg,a1,ay=b5(c7,c9,b8,ca,cb,b2,b9)local bv,ch,be,ci,bu,cj=ba(bU,bV,c1,b_,c0,b6)local bQ,bi,ck,bt=bd(bU,c5,bY,a1,aj,be)local aC,aD,aE,bM=bl(bU,bV,bW,aj,bm,bn,bo,bp,bq,br,bs,b6,ak,bt,aU,be,bu,bv)local ad,cl,cm=bL(bT,bX,bM)local aM,aL,aH=bP(c6,c5,bZ,cg,am,aU,bQ)local cn=put_bit(cl,0)|put_bit(aC,1)|put_bit(aD,2)|put_bit(aE,3)|put_bit(aj,4)|put_bit(ak,5)|put_bit(bi,6)local aV={b6,cf,aM,ay,cn,0,0,0}local co=encode_state(ad,aC,aD,aE,cm,ck,aH,ci,cj,ch,cc,cd,ce,aL,aM)return aV,co end
function calculateTick(aY,az)local a={az[1],az[2],i2f(az[3]),i2f(az[4]),i2f(az[5]),i2f(az[6]),i2f(az[7]),az[8]}local aV,co=core_tick(aY,a)local b={co[1],co[2],f2i(co[3]),f2i(co[4]),f2i(co[5]),f2i(co[6]),f2i(co[7]),co[8]}return aV,b end
--[[
//# sourceMappingURL=main.lua.map
]]