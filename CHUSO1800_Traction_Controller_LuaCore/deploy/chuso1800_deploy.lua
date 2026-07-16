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
local function bk(aH,aR,aL,ap,ae,bl)local bm=aH and aR<r
local bn=bm and q or p
local bo=ap>p
local bp=ap>bn and not ae
local bq,br=W(aL,bp,v)return bo and bl,bp,bq,br end
local function bs(aH,aI,aJ,ae,bt,bu,bv,bw,bx,by,bz,bc,af,bA,a_,bl,bB,bC)local bD=aH and ae
local bE=aH and bz and aJ
local bF=ae and bv
local bG=bj(bc)and not(ae or af)local bH=bG and not aJ
local bI=bH or bA and not a_
local bJ=aJ and aI and not aH and bv and bG
local bK=bt and bw and bl and bC
local bL=bF and not aI or bA and aI
local bM=bu and bx and bB and bC
local bN=bu and by and bC
local bO=bI or aH and not(bu and by)or bJ
local bP=bI or bA and bl or bN
local bQ=not aH and not aI
local bR=not bv and bQ
return sr_latch(aH,bL,bP),sr_latch(aI,bN,bO),sr_latch(aJ,aI and bv,bD or bQ),bK or bM or bR or bE end
local function bS(a8,aK,bT)local bq,br=W(aK,bT,u)local bU=(a8+(br and 1 or 0))%21
local bV=bU-a8
return bU,bV~=0,bq end
local function bW(aS,aR,aM,aN,be,ah,a_,bX)local bY=aN or not a_
local bZ=bY and 0 or ah
local b_,c0=Z(aM,aN,bX)return be*0.2+aS*0.8,math.min(B(bZ,aR-0.1,aR+0.02),0),b_,c0 end
function core_tick(b3,aE)local c1,c2,c3,c4,c5,c6,c7,c8,c9,ca,cb,cc,cd,ce,cf,cg=decode_state(aE)local a6,aV,aW,aX,a9,aY,aZ,a_=b2(b3)local b8=b4(a6,aW,a9,aZ)local aa,ae,bt,bu,bv,bw,bx,by,bz=b7(aY,c1,b8)local ah,af,bf=ba(aX,a_)local ch,ci,be,cj,ck,cl,cm,cn,co=physics_tick(a6,aV,c1,a9,aa,c2,c3,c4,ae,af,cf,ah,cc,cd,ce)local bc,cp,cq,ap,aD=bb(ch,cj,be,ck,cl,b8,bf)local bC,cr,bl,cs,bB,ct=bg(c2,c3,cb,c9,ca,bc)local bX,bp,cu,bA=bk(c2,cf,c6,ap,ae,bl)local aH,aI,aJ,bT=bs(c2,c3,c4,ae,bt,bu,bv,bw,bx,by,bz,bc,af,bA,a_,bl,bB,bC)local a8,cv,cw=bS(c1,c5,bT)local aS,aR,aM,aN=bW(cg,cf,c7,c8,cq,ah,a_,bX)local cx=put_bit(cv,0)|put_bit(aH,1)|put_bit(aI,2)|put_bit(aJ,3)|put_bit(ae,4)|put_bit(af,5)|put_bit(bp,6)local b0={bc,cp,aS,aD,cx,0,0,0}local cy=encode_state(a8,aH,aI,aJ,cw,cu,aM,aN,cs,ct,cr,cm,cn,co,aR,aS)return b0,cy end
function calculateTick(b3,aE)local a={aE[1],aE[2],i2f(aE[3]),i2f(aE[4]),i2f(aE[5]),i2f(aE[6]),i2f(aE[7]),aE[8]}local b0,cy=core_tick(b3,a)local b={cy[1],cy[2],f2i(cy[3]),f2i(cy[4]),f2i(cy[5]),f2i(cy[6]),f2i(cy[7]),cy[8]}return b0,b end
--[[
//# sourceMappingURL=main.lua.map
]]