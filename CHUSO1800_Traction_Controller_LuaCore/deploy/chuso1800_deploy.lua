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
local m=property
if type(m)~="table"then local n={["Over Speed Th. [m/s]"]=32,["Power Limit Current [A]"]=210}m={getNumber=function(o)return n[o]end}end
local p=m.getNumber("Over Speed Th. [m/s]")local q=m.getNumber("Power Limit Current [A]")local r=4
local s=300
local t=400
local u=-0.1
local v=-0.05
local w=6
local x=12
local y=30
local z=600
local A=30
local B=z
local C=B//A
local D=1
local function E(b,F,G)if b<F then return F end
if b>G then return G end
return b end
function to_u32(H)return string.unpack("I4",string.pack("I4",math.floor(H or 0)&0xFFFFFFFF))end
function get_bits(I,J,K)return I>>J&1<<K-1 end
function get_bit(I,J)return I>>J&1~=0 end
function put_bits(H,J,K)return math.floor(H or 0)&1<<K-1<<J end
function put_bit(L,J)return L and 1 or 0<<J end
function sr_latch(M,N,O)if O then return false end
if N then return true end
return M end
local function P(Q,R)if R then return math.min(Q+1,w)end
return 0 end
local function S(Q)return Q>=w end
local function T(Q,R,U)if not R then return 0,false end
local V=Q+1
if V>=U then return 0,true end
return V,false end
local function W(X,R)if R then return math.min(X+C,B)end
return math.max(X-D,0)end
local function Y(X)return X>=B end
local function Z(_)return _*b*d*e/(d*math.abs(_)+e)end
local function a0(_)return b*d*e*e/((d*math.abs(_)+e)*(d*math.abs(_)+e))end
local function a1(a2,a3,a4)return a3*a2+a4 end
local function a5(a2)return a2 end
local function a6(a3,a7,a,a8,a2,a4)return a*Z(a1(a2,a3,a4))*a-a7+(c+a8)*a3 end
local function a9(a3,a7,a,a8,a2,a4)return a*a0(a1(a2,a3,a4))*a5(a2)*a+c+a8 end
local function aa(a7,a,a8,a2,a4,ab)local j=ab
for ac=1,5 do local ad=a9(j,a7,a,a8,a2,a4)if math.abs(ad)>=0.000001 then j=j-a6(j,a7,a,a8,a2,a4)/ad else if ad>0 then j=j-a6(j,a7,a,a8,a2,a4)elseif ad<0 then j=j+a6(j,a7,a,a8,a2,a4)end end end
return j,Z(a1(a2,j,a4))end
function physics_tick(ae,af,ag,ah,ai,aj,ak,al,am,an,ao,ap,aq,ar,as)local at=ae*9.55*g/h
local au=ag+1
local av=100000
local aw=4
local a4=150
local ax=l
if not aj and not ak then af=0 end
if aj then aw=8 end
if ak and au==1 then aw=4 end
if al then if an then local ay=ah*f*9.55*a*as*aq*g*0.99/h/i
a4=ar+(ay-ao)*20
a4=a4*math.min(1,470/(a*math.abs(at))/Z(a4+aq*0.15))else if am and ai<=3 then ax=ar end
if not am then ax=0 end
if ax==0 then ax=math.max(math.min(0,aq+20),aq-20)end
a4=ar+(aq-ax)*0.1 end else ax=ar
if ai==0 then ax=0 end
a4=ar+(aq-ax)*0.1
if ai~=0 and a4>180 then a4=180 end end
if aw==8 then av=j[au]end
if aw==4 then av=k[au]end
if a4<20 then a4=20 elseif a4>500 then a4=500 end
local j,az=aa(af/aw,at,av/aw,ah*0.2,a4*ah,l)if af==0 then j=0
az=0 end
local aA=9.55*a*az*j
local aB=math.min(ah*f*aA*g/h/i,0)-ap
if aB<0.01 and j<0 then aB=0 end
return j,a*az*at,f*aA*g*0.99/h/i,af*j*f/aw*2,a4,aB,j,a4,az end
function zero_state()return{0,0,0,0,0,0,0,0}end
function decode_state(aC)local aD=to_u32(aC[1])local aE=to_u32(aC[2])return get_bits(aD,0,5),get_bit(aD,5),get_bit(aD,6),get_bit(aD,7),get_bits(aD,8,4),get_bits(aD,12,5),get_bits(aE,0,10),get_bits(aE,10,3),get_bits(aE,13,3),get_bits(aE,16,3),aC[3],aC[4],aC[5],aC[6],aC[7]end
function encode_state(ag,aF,aG,aH,aI,aJ,aK,aL,aM,aN,aq,ar,as,aO,aP)local aQ=put_bits(ag,0,5)|put_bit(aF,5)|put_bit(aG,6)|put_bit(aH,7)|put_bits(aI,8,4)|put_bits(aJ,12,5)local aR=put_bits(aK,0,10)|put_bits(aL,10,3)|put_bits(aM,13,3)|put_bits(aN,16,3)return{aQ,aR,aq or 0,ar or 0,as or 0,aO or 0,aP or 0,0}end
function encode_stateless_in(ae,aS,aT,aU,ah,aV,aW,aX)return{ae or 0,aS or 0,aT or 0,aU or 0,ah or 0,aV or 0,aW and 1 or 0,aX and 1 or 0}end
function decode_stateless_out(aY)local aZ=to_u32(aY[5])return aY[1],aY[2],aY[3],aY[4],get_bit(aZ,0),get_bit(aZ,1),get_bit(aZ,2),get_bit(aZ,3),get_bit(aZ,4),get_bit(aZ,5),get_bit(aZ,6),get_bit(aZ,7)end
local function a_(b0)return b0[1],b0[2],b0[3],b0[4],b0[5],E(math.floor(b0[6]or 0),0,7),(b0[7]or 0)~=0,(b0[8]or 0)~=0 end
local function b1(ae,aT,ah,aW)local b2=math.abs(ae)>p
local b3=aT<r
return aW or ah==0 or b2 or b3 end
local function b4(aV,ag,b5)local ai=aV*(b5 and 0 or 1)local b6=b5 and 0 or ag
return ai,ai>=1 and ai<=7,ai>=2 and ai<=7,ai>=3 and ai<=7,b6>=0 and b6<=1,b6>=0 and b6<=13,b6>=14 and b6<=20,b6==14,b6~=14 end
local function b7(aU,aX)local ap=-math.floor((aU-1)*2)/7.2
return ap,ap<v and aX,math.max(-ap,0)end
local function b8(b9,ba,bb,a4,aB,b5,bc)if b5 then return 0,0,0,0,bc end
return b9,ba,bb,a4,aB end
local function bd(aF,aG,aN,aL,aM,b9)local be=aG and q-20 or q
local bf=b9<be
return S(aN),P(aN,bf),S(aL),P(aL,aF),S(aM),P(aM,aG)end
local function bg(aF,aO,aJ,a4,am,bh)local bi=aF and aO<u
local bj=bi and t or s
local bk=a4>s
local bl=a4>bj and not am
local bm,bn=T(aJ,bl,y)return bk and bh,bl,bm,bn end
local function bo(aF,aG,aH,am,bp,bq,br,bs,bt,bu,bv,b9,an,bw,aX,bh,bx,by)local bz=aF and am
local bA=aF and bv and aH
local bB=am and br
local bC=b9>=-50 and b9<=50
local bD=bC and not(am or an)local bE=bD and not aH
local bF=bE or bw and not aX
local bG=bp and bs and bh and by
local bH=bB and not aG or bw and aG
local bI=bq and bt and bx and by
local bJ=bq and bu and by
local bK=bF or aF and not(bq and bu)local bL=bF or bw and bh or bJ
local bM=not aF and not aG
local bN=not br and bM
return sr_latch(aF,bH,bL),sr_latch(aG,bJ,bK),sr_latch(aH,aG and br,bz or bM),bG or bI or bN or bA end
local function bO(ag,aI,bP)local bm,bn=T(aI,bP,x)local bQ=(ag+(bn and 1 or 0))%21
local bR=bQ-ag
return bQ,not(bR>=0 and bR<=1),bm end
local function bS(aP,aO,aK,bb,ap,aX,bT)local bU=Y(aK)or not aX
local bV=bU and 0 or ap
return bb*0.2+aP*0.8,math.min(E(bV,aO-0.1,aO+0.02),0),W(aK,bT)end
function core_tick(b0,aC)local bW,bX,bY,bZ,b_,c0,c1,c2,c3,c4,c5,c6,c7,c8,c9=decode_state(aC)local ae,aS,aT,aU,ah,aV,aW,aX=a_(b0)local b5=b1(ae,aT,ah,aW)local ai,am,bp,bq,br,bs,bt,bu,bv=b4(aV,bW,b5)local ap,an,bc=b7(aU,aX)local ca,cb,bb,cc,cd,ce,cf,cg,ch=physics_tick(ae,aS,bW,ah,ai,bX,bY,bZ,am,an,c8,ap,c5,c6,c7)local b9,ci,cj,a4,aB=b8(ca,cc,bb,cd,ce,b5,bc)local by,ck,bh,cl,bx,cm=bd(bX,bY,c4,c2,c3,b9)local bT,bl,cn,bw=bg(bX,c8,c0,a4,am,bh)local aF,aG,aH,bP=bo(bX,bY,bZ,am,bp,bq,br,bs,bt,bu,bv,b9,an,bw,aX,bh,bx,by)local ag,co,cp=bO(bW,b_,bP)local aP,aO,aK=bS(c9,c8,c1,cj,ap,aX,bT)local cq=put_bit(co,0)|put_bit(aF,1)|put_bit(aG,2)|put_bit(aH,3)|put_bit(am,4)|put_bit(an,5)|put_bit(bl,6)local aY={b9,ci,aP,aB,cq,0,0,0}local cr=encode_state(ag,aF,aG,aH,cp,cn,aK,cl,cm,ck,cf,cg,ch,aO,aP)return aY,cr end
function calculateTick(b0,aC)local a={aC[1],aC[2],i2f(aC[3]),i2f(aC[4]),i2f(aC[5]),i2f(aC[6]),i2f(aC[7]),aC[8]}local aY,cr=core_tick(b0,a)local b={cr[1],cr[2],f2i(cr[3]),f2i(cr[4]),f2i(cr[5]),f2i(cr[6]),f2i(cr[7]),cr[8]}return aY,b end
--[[
//# sourceMappingURL=main.lua.map
]]