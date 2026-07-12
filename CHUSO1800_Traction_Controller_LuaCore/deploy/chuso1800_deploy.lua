function require(m,r)package=package or{loaded={}};if package.loaded[m]then return package.loaded[m]end
if m=="chuso1800_core"then r=(function() local a={}local b=12.16
local c=0.00029
local d=0.07
local e=0.85
local f=150
local g=4
local h=5.31
local i=0.86/2
local j=35*1000
local k={7.428,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334,0,2.568,1.734,1.218,0.7570,0.4110,0.1334}local l={0,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334,3.714,2.568,1.734,1.218,0.7570,0.4110,0.1334}local m=200
local n=property
if type(n)~="table"then local o={["Over Speed Th. [m/s]"]=32,["Power Limit Current [A]"]=210}n={getNumber=function(p)return o[p]end}end
local q=n.getNumber("Over Speed Th. [m/s]")local r=n.getNumber("Power Limit Current [A]")local s=4
local t=300
local u=400
local v=-0.1
local w=-0.05
local x=6
local y=12
local z=30
local A=600
local B=30
local C=A
local D=C//B
local E=1
local function F(b,G,H)if b<G then return G end
if b>H then return H end
return b end
local function I(J)return string.unpack("I4",string.pack("I4",math.floor(J or 0)&0xFFFFFFFF))end
local function K(L,M,N)return L>>M&1<<N-1 end
local function O(L,M)return L>>M&1~=0 end
local function P(J,M,N)return math.floor(J or 0)&1<<N-1<<M end
local function Q(R,M)return R and 1 or 0<<M end
local function S(T,U,V)if V then return false end
if U then return true end
return T end
local function W(X,Y)if Y then return math.min(X+1,x)end
return 0 end
local function Z(X)return X>=x end
local function _(X,Y,a0)if not Y then return 0,false end
local a1=X+1
if a1>=a0 then return 0,true end
return a1,false end
local function a2(a3,Y)if Y then return math.min(a3+D,C)end
return math.max(a3-E,0)end
local function a4(a3)return a3>=C end
local function a5(a6)return a6*c*e*f/(e*math.abs(a6)+f)end
local function a7(a6)return c*e*f*f/((e*math.abs(a6)+f)*(e*math.abs(a6)+f))end
local function a8(a9,aa,ab)return aa*a9+ab end
local function ac(a9)return a9 end
local function ad(aa,ae,a,af,a9,ab)return b*a5(a8(a9,aa,ab))*a-ae+(d+af)*aa end
local function ag(aa,ae,a,af,a9,ab)return b*a7(a8(a9,aa,ab))*ac(a9)*a+d+af end
local function ah(ae,a,af,a9,ab,ai)local j=ai
for aj=1,5 do local ak=ag(j,ae,a,af,a9,ab)if math.abs(ak)>=0.000001 then j=j-ad(j,ae,a,af,a9,ab)/ak else if ak>0 then j=j-ad(j,ae,a,af,a9,ab)elseif ak<0 then j=j+ad(j,ae,a,af,a9,ab)end end end
return j,a5(a8(a9,j,ab))end
function a.physics_tick(al,am,an,ao,ap,aq,ar,as,at,au,av,aw,ax,ay,az)local aA=al*9.55*h/i
local aB=an+1
local aC=100000
local aD=4
local ab=150
local aE=m
if not aq and not ar then am=0 end
if aq then aD=8 end
if ar and aB==1 then aD=4 end
if as then if au then local aF=ao*g*9.55*b*az*ax*h*0.99/i/j
ab=ay+(aF-av)*20
ab=ab*math.min(1,470/(b*math.abs(aA))/a5(ab+ax*0.15))else if at and ap<=3 then aE=ay end
if not at then aE=0 end
if aE==0 then aE=math.max(math.min(0,ax+20),ax-20)end
ab=ay+(ax-aE)*0.1 end else aE=ay
if ap==0 then aE=0 end
ab=ay+(ax-aE)*0.1
if ap~=0 and ab>180 then ab=180 end end
if aD==8 then aC=k[aB]end
if aD==4 then aC=l[aB]end
if ab<20 then ab=20 elseif ab>500 then ab=500 end
local j,aG=ah(am/aD,aA,aC/aD,ao*0.2,ab*ao,m)if am==0 then j=0
aG=0 end
local aH=9.55*b*aG*j
local aI=math.min(ao*g*aH*h/i/j,0)-aw
if aI<0.01 and j<0 then aI=0 end
return j,b*aG*aA,g*aH*h*0.99/i/j,am*j*g/aD*2,ab,aI,j,ab,aG end
function a.zero_state()return{0,0,0,0,0,0,0,0}end
function a.decode_state(aJ)local aK=I(aJ[1])local aL=I(aJ[2])return K(aK,0,5),O(aK,5),O(aK,6),O(aK,7),K(aK,8,4),K(aK,12,5),K(aL,0,10),K(aL,10,3),K(aL,13,3),K(aL,16,3),aJ[3],aJ[4],aJ[5],aJ[6],aJ[7]end
function a.encode_state(an,aM,aN,aO,aP,aQ,aR,aS,aT,aU,ax,ay,az,aV,aW)local aX=P(an,0,5)|Q(aM,5)|Q(aN,6)|Q(aO,7)|P(aP,8,4)|P(aQ,12,5)local aY=P(aR,0,10)|P(aS,10,3)|P(aT,13,3)|P(aU,16,3)return{aX,aY,ax or 0,ay or 0,az or 0,aV or 0,aW or 0,0}end
function a.encode_stateless_in(al,aZ,a_,b0,ao,b1,b2,b3)return{al or 0,aZ or 0,a_ or 0,b0 or 0,ao or 0,b1 or 0,b2 and 1 or 0,b3 and 1 or 0}end
function a.decode_stateless_out(b4)local b5=I(b4[5])return b4[1],b4[2],b4[3],b4[4],O(b5,0),O(b5,1),O(b5,2),O(b5,3),O(b5,4),O(b5,5),O(b5,6),O(b5,7)end
local function b6(b7)return b7[1],b7[2],b7[3],b7[4],b7[5],F(math.floor(b7[6]or 0),0,7),(b7[7]or 0)~=0,(b7[8]or 0)~=0 end
local function b8(al,a_,ao,b2)local b9=math.abs(al)>q
local ba=a_<s
return b2 or ao==0 or b9 or ba end
local function bb(b1,an,bc)local ap=b1*(bc and 0 or 1)local bd=bc and 0 or an
return ap,ap>=1 and ap<=7,ap>=2 and ap<=7,ap>=3 and ap<=7,bd>=0 and bd<=1,bd>=0 and bd<=13,bd>=14 and bd<=20,bd==14,bd~=14 end
local function be(b0,b3)local aw=-math.floor((b0-1)*2)/7.2
return aw,aw<w and b3,math.max(-aw,0)end
local function bf(bg,bh,bi,ab,aI,bc,bj)if bc then return 0,0,0,0,bj end
return bg,bh,bi,ab,aI end
local function bk(aM,aN,aU,aS,aT,bg)local bl=aN and r-20 or r
local bm=bg<bl
return Z(aU),W(aU,bm),Z(aS),W(aS,aM),Z(aT),W(aT,aN)end
local function bn(aM,aV,aQ,ab,at,bo)local bp=aM and aV<v
local bq=bp and u or t
local br=ab>t
local bs=ab>bq and not at
local bt,bu=_(aQ,bs,z)return br and bo,bs,bt,bu end
local function bv(aM,aN,aO,at,bw,bx,by,bz,bA,bB,bC,bg,au,bD,b3,bo,bE,bF)local bG=aM and at
local bH=aM and bC and aO
local bI=at and by
local bJ=bg>=-50 and bg<=50
local bK=bJ and not(at or au)local bL=bK and not aO
local bM=bL or bD and not b3
local bN=bw and bz and bo and bF
local bO=bI and not aN or bD and aN
local bP=bx and bA and bE and bF
local bQ=bx and bB and bF
local bR=bM or aM and not(bx and bB)local bS=bM or bD and bo or bQ
local bT=not aM and not aN
local bU=not by and bT
return S(aM,bO,bS),S(aN,bQ,bR),S(aO,aN and by,bG or bT),bN or bP or bU or bH end
local function bV(an,aP,bW)local bt,bu=_(aP,bW,y)local bX=(an+(bu and 1 or 0))%21
local bY=bX-an
return bX,not(bY>=0 and bY<=1),bt end
local function bZ(aW,aV,aR,bi,aw,b3,b_)local c0=a4(aR)or not b3
local c1=c0 and 0 or aw
return bi*0.2+aW*0.8,math.min(F(c1,aV-0.1,aV+0.02),0),a2(aR,b_)end
function a.calculateTick(b7,aJ)local c2,c3,c4,c5,c6,c7,c8,c9,ca,cb,cc,cd,ce,cf,cg=a.decode_state(aJ)local al,aZ,a_,b0,ao,b1,b2,b3=b6(b7)local bc=b8(al,a_,ao,b2)local ap,at,bw,bx,by,bz,bA,bB,bC=bb(b1,c2,bc)local aw,au,bj=be(b0,b3)local ch,ci,bi,cj,ck,cl,cm,cn,co=a.physics_tick(al,aZ,c2,ao,ap,c3,c4,c5,at,au,cf,aw,cc,cd,ce)local bg,cp,cq,ab,aI=bf(ch,cj,bi,ck,cl,bc,bj)local bF,cr,bo,cs,bE,ct=bk(c3,c4,cb,c9,ca,bg)local b_,bs,cu,bD=bn(c3,cf,c7,ab,at,bo)local aM,aN,aO,bW=bv(c3,c4,c5,at,bw,bx,by,bz,bA,bB,bC,bg,au,bD,b3,bo,bE,bF)local an,cv,cw=bV(c2,c6,bW)local aW,aV,aR=bZ(cg,cf,c8,cq,aw,b3,b_)local cx=Q(cv,0)|Q(aM,1)|Q(aN,2)|Q(aO,3)|Q(at,4)|Q(au,5)|Q(bs,6)local b4={bg,cp,aW,aI,cx,0,0,0}local cy=a.encode_state(an,aM,aN,aO,cw,cu,aR,cs,ct,cr,cm,cn,co,aV,aW)return b4,cy end
a.to_u32=I
a.get_bits=K
a.get_bit=O
a.put_bits=P
a.put_bit=Q
a.sr_latch=S
return a end)()end
if m=="state_sync"then r=(function() function i2f(a)local b=('f'):unpack(('I4'):pack(a&0xFFFFFFFF))return b end
function f2i(b)local a=('I4'):unpack(('f'):pack(b))return a end
s1={0,0,0,0,0,0,0,0}s2={0,0,0,0,0,0,0,0}function onTick()local c,d,e,f={},{},{},{}local g,h,i
for j=1,8 do c[j]=input.getNumber(j)d[j]=input.getNumber(j+8)e[j]=input.getNumber(j+16)f[j]=f2i(input.getNumber(j+24))end
local k=true
for j=1,8 do k=k and s2[j]==f[j]end
if not k then i,s1=calculateTick(d,f)end
g,h=calculateTick(c,s1)for j=1,8 do output.setNumber(j,e[j])output.setNumber(j+8,i2f(f[j]))output.setNumber(j+16,g[j])output.setNumber(j+24,i2f(h[j]))end
s2=s1
s1=h end end)()end
package.loaded[m]=package.loaded[m]or r or true;return package.loaded[m]end
require("state_sync")local a=require("chuso1800_core")function calculateTick(b7,aJ)local b={aJ[1],aJ[2],i2f(aJ[3]),i2f(aJ[4]),i2f(aJ[5]),i2f(aJ[6]),i2f(aJ[7]),aJ[8]}local b4,cy=a.calculateTick(b7,b)local c={cy[1],cy[2],f2i(cy[3]),f2i(cy[4]),f2i(cy[5]),f2i(cy[6]),f2i(cy[7]),cy[8]}return b4,c end
--[[
//# sourceMappingURL=main.lua.map
]]