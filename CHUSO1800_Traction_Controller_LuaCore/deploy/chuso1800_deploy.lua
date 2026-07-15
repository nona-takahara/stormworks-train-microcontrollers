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
function physics_tick(a6,a7,a8,a9,aa,ab,ac,ad,ae,af,ag,ah,ai,aj,ak)local al=a6*9.55*g/h
local am=a8+1
local an=100000
local ao=4
local ap=150
local aq=l
if not ab and not ac then a7=0 end
if ab then ao=8 end
if ac and am==1 then ao=4 end
if ad then if af then local ar=a9*f*9.55*a*ak*ai*g*0.99/h/i
ap=aj+(ar-ag)*20
ap=ap*math.min(1,470/(a*math.abs(al))/a3(ap+ai*0.15))else if ae and aa<=3 then aq=aj end
if not ae then aq=0 end
if aq==0 then aq=math.max(math.min(0,ai+20),ai-20)end
ap=aj+(ai-aq)*0.1 end else aq=aj
if aa==0 then aq=0 end
ap=aj+(ai-aq)*0.1
if aa~=0 and ap>180 then ap=180 end end
if ao==8 then an=j[am]end
if ao==4 then an=k[am]end
if ap<20 then ap=20 elseif ap>500 then ap=500 end
local as,at,au,av,aw=a7/ao,al,an/ao,a9*0.2,ap*a9
local j=l
local ax=0
for ay=1,5 do local a4=j*av+aw
ax=a3(a4)local az=a5(a4)local aA=a*az*av*at+c+au
local aB=a*ax*at-as+(c+au)*j
if math.abs(aA)>=0.000001 then j=j-aB/aA else if aA>0 then j=j-aB elseif aA<0 then j=j+aB end end end
ax=a3(j*av+aw)if a7==0 then j=0
ax=0 end
local aC=9.55*a*ax*j
local aD=math.min(a9*f*aC*g/h/i,0)-ah
if aD<0.01 and j<0 then aD=0 end
return j,a*ax*al,f*aC*g*0.99/h/i,a7*j*f/ao*2,ap,aD,j,ap,ax end
function zero_state()return{0,0,0,0,0,0,0,0}end
function decode_state(aE)local aF=to_u32(aE[1])local aG=to_u32(aE[2])return get_bits(aF,0,5),get_bit(aF,5),get_bit(aF,6),get_bit(aF,7),get_bits(aF,8,4),get_bits(aF,12,5),get_bits(aG,0,10),get_bit(aG,19),get_bits(aG,10,3),get_bits(aG,13,3),get_bits(aG,16,3),aE[3],aE[4],aE[5],aE[6],aE[7]end
function encode_state(a8,aH,aI,aJ,aK,aL,aM,aN,aO,aP,aQ,ai,aj,ak,aR,aS)local aT=put_bits(a8,0,5)|put_bit(aH,5)|put_bit(aI,6)|put_bit(aJ,7)|put_bits(aK,8,4)|put_bits(aL,12,5)local aU=put_bits(aM,0,10)|put_bits(aO,10,3)|put_bits(aP,13,3)|put_bits(aQ,16,3)|put_bit(aN,19)return{aT,aU,ai or 0,aj or 0,ak or 0,aR or 0,aS or 0,0}end
function encode_stateless_in(a6,aV,aW,aX,a9,aY,aZ,a_)return{a6 or 0,aV or 0,aW or 0,aX or 0,a9 or 0,aY or 0,aZ and 1 or 0,a_ and 1 or 0}end
function decode_stateless_out(b0)local b1=to_u32(b0[5])return b0[1],b0[2],b0[3],b0[4],get_bit(b1,0),get_bit(b1,1),get_bit(b1,2),get_bit(b1,3),get_bit(b1,4),get_bit(b1,5),get_bit(b1,6),get_bit(b1,7)end
local function b2(b3)return b3[1],b3[2],b3[3],b3[4],b3[5],B(math.floor(b3[6]or 0),0,7),(b3[7]or 0)~=0,(b3[8]or 0)~=0 end
local function b4(a6,aW,a9,aZ)local b5=math.abs(a6)>m
local b6=aW<o
return aZ or a9==0 or b5 or b6 end
local function b7(aY,a8,b8)local aa=aY*(b8 and 0 or 1)local b9=b8 and 0 or a8
return aa,aa>=1 and aa<=7,aa>=2 and aa<=7,aa>=3 and aa<=7,b9==0,b9>=0 and b9<=13,b9>=14 and b9<=20,b9==14,b9~=14 end
local function ba(aX,a_)local ah=-math.floor((aX-1)*2)/7.2
return ah,ah<s and a_,math.max(-ah,0)end
local function bb(bc,bd,be,ap,aD,b8,bf)if b8 then return 0,0,0,0,bf end
return bc,bd,be,ap,aD end
local function bg(aH,aI,aQ,aO,aP,bc)local bh=aI and n-20 or n
local bi=bc<bh
return V(aQ),S(aQ,bi),V(aO),S(aO,aH),V(aP),S(aP,aI)end
local function bj(bc)return bc>=-50 and bc<=50 end
local function bk(aH,aI,aJ,aR,aL,ap,ae,bl,bc,af,bm)local bn=aH and aR<r
local bo=bn and q or p
local bp=ap>p
local bq=ap>bo
local br=aJ and aI and not aH and bl and bj(bc)and not af
local bs=(bq or br)and not ae
local bt,bu=W(aL,bs,v)return bp and bm,bs,bt,bu end
local function bv(aH,aI,aJ,ae,bw,bx,bl,by,bz,bA,bB,bc,af,bC,a_,bm,bD,bE)local bF=aH and ae
local bG=aH and bB and aJ
local bH=ae and bl
local bI=bj(bc)and not(ae or af)local bJ=bI and not aJ
local bK=bJ or bC and not a_
local bL=bw and by and bm and bE
local bM=bH and not aI or bC and aI
local bN=bx and bz and bD and bE
local bO=bx and bA and bE
local bP=bK or aH and not(bx and bA)local bQ=bK or bC and bm or bO
local bR=not aH and not aI
local bS=not bl and bR
return sr_latch(aH,bM,bQ),sr_latch(aI,bO,bP),sr_latch(aJ,aI and bl,bF or bR),bL or bN or bS or bG end
local function bT(a8,aK,bU)local bt,bu=W(aK,bU,u)local bV=(a8+(bu and 1 or 0))%21
local bW=bV-a8
return bV,bW~=0,bt end
local function bX(aS,aR,aM,aN,be,ah,a_,bY)local bZ=aN or not a_
local b_=bZ and 0 or ah
local c0,c1=Z(aM,aN,bY)return be*0.2+aS*0.8,math.min(B(b_,aR-0.1,aR+0.02),0),c0,c1 end
function core_tick(b3,aE)local c2,c3,c4,c5,c6,c7,c8,c9,ca,cb,cc,cd,ce,cf,cg,ch=decode_state(aE)local a6,aV,aW,aX,a9,aY,aZ,a_=b2(b3)local b8=b4(a6,aW,a9,aZ)local aa,ae,bw,bx,bl,by,bz,bA,bB=b7(aY,c2,b8)local ah,af,bf=ba(aX,a_)local ci,cj,be,ck,cl,cm,cn,co,cp=physics_tick(a6,aV,c2,a9,aa,c3,c4,c5,ae,af,cg,ah,cd,ce,cf)local bc,cq,cr,ap,aD=bb(ci,ck,be,cl,cm,b8,bf)local bE,cs,bm,ct,bD,cu=bg(c3,c4,cc,ca,cb,bc)local bY,bs,cv,bC=bk(c3,c4,c5,cg,c7,ap,ae,bl,bc,af,bm)local aH,aI,aJ,bU=bv(c3,c4,c5,ae,bw,bx,bl,by,bz,bA,bB,bc,af,bC,a_,bm,bD,bE)local a8,cw,cx=bT(c2,c6,bU)local aS,aR,aM,aN=bX(ch,cg,c8,c9,cr,ah,a_,bY)local cy=put_bit(cw,0)|put_bit(aH,1)|put_bit(aI,2)|put_bit(aJ,3)|put_bit(ae,4)|put_bit(af,5)|put_bit(bs,6)local b0={bc,cq,aS,aD,cy,0,0,0}local cz=encode_state(a8,aH,aI,aJ,cx,cv,aM,aN,ct,cu,cs,cn,co,cp,aR,aS)return b0,cz end
function calculateTick(b3,aE)local a={aE[1],aE[2],i2f(aE[3]),i2f(aE[4]),i2f(aE[5]),i2f(aE[6]),i2f(aE[7]),aE[8]}local b0,cz=core_tick(b3,a)local b={cz[1],cz[2],f2i(cz[3]),f2i(cz[4]),f2i(cz[5]),f2i(cz[6]),f2i(cz[7]),cz[8]}return b0,b end
--[[
//# sourceMappingURL=main.lua.map
]]