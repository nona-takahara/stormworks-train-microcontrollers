local v,w=input,output
function c(t)local u=('f'):unpack(('I4'):pack(t&0xFFFFFFFF))return u end
function f(t)local u=('I4'):unpack(('f'):pack(t))return u end
g={0,0,0,0,0,0,0,0}k={0,0,0,0,0,0,0,0}function onTick()local t,u,A,x,B,y,C={},{},{},{}for s=1,8 do t[s]=v.getNumber(s)u[s]=v.getNumber(s+8)A[s]=v.getNumber(s+16)x[s]=f(v.getNumber(s+24))end
local z=true
for s=1,8 do z=z and k[s]==x[s]end
if not z then C,g=j(u,x)end
B,y=j(t,g)for s=1,8 do w.setNumber(s,A[s])w.setNumber(s+8,c(x[s]))w.setNumber(s+16,B[s])w.setNumber(s+24,c(y[s]))end
k=g
g=y end
local au,K,ah,aF,av,aG,aw=property,math,78.941,0.05696,400,0.12,0.30
local ax,aW=1.00-aw,390
local aH,aX,ao,ap,aq,ay,aY,aZ,aI,a_,aJ,ba,bb,aK,bc,bd,be,bf,aL,bg,bh,bi,bj=ax*aW,470,4,5.60,0.86/2,35*1000,{7.428,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334,0,2.568,1.734,1.218,0.7570,0.4110,0.1334},{0,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334,3.714,2.568,1.734,1.218,0.7570,0.4110,0.1334},200,au.getNumber("Over Speed Th. [m/s]"),au.getNumber("Power Limit Current [A]"),au.getNumber("Field Control Current [A]"),4,300,400,-0.1,-0.05,3,6,12,30,600,30
local az=bi
local bk,bl=az//bj,1
local function aM(D,E,F)if D<E then return E end
if D>F then return F end
return D end
function h(D)return string.unpack("I4",string.pack("I4",K.floor(D or 0)&0xFFFFFFFF))end
function d(D,E,F)local G,H=D>>E,1<<F
local I=H-1
return G&I end
function a(D,E)local F=D>>E
local G=F&1
return G~=0 end
function e(D,E,F)local G=1<<F
local H,I=G-1,K.floor(D or 0)local J=I&H
return J<<E end
function b(D,E)local F=D and 1 or 0
return F<<E end
function i(D,E,F)if F then return false end
if E then return true end
return D end
local function aA(D,E)if E then return K.min(D+1,aL)end
return 0 end
local function aB(D)return D>=aL end
local function aN(D,E,F)if not E then return 0,false end
local G=D+1
if G>=F then return 0,true end
return G,false end
local function bm(D,E,F)local G=F and K.min(D+bk,az)or K.max(D-bl,0)local H=E and G>0 or G>=az
return G,H end
local function aC(D)return aF*D/(av+K.abs(D))end
local function bn(D)local E=av+K.abs(D)return aF*av/(E*E)end
function l(D,E,F,G,H,I,J,O,R,S,V,W,P,N,aa)local U,X,Y,T,M,Z=D*ap/aq,F+1,100000,4,150,aI
if not I and not J then E=0 end
if I then T=8 end
if J and X==1 then T=4 end
if O then if S then local ai=G*ao*ah*aa*P*ap*0.99/aq/ay
M=N+(ai-V)*20
local ab=aC(G*(M+aw*P))if K.abs(U)>0.000001 and K.abs(ab)>0.000001 then M=M*K.min(1,aX/(ah*K.abs(U*ab)))end else if R and H<=3 then Z=N/ax end
if R and H>3 then Z=ba end
if not R then Z=0 end
if Z==0 then Z=K.max(K.min(0,P+20),P-20)end
M=N+(P-Z)*0.1 end else if H==0 then M=N+P*0.1 else M=N+(ax*P-N)*0.1
if M>aH then M=aH end end end
if T==8 then Y=aY[X]end
if T==4 then Y=aZ[X]end
if M<20 then M=20 elseif M>500 then M=500 end
local al,ae,af,ag,L,Q=E/T,Y/T,G*aw,M*G,aI,0
for ai=1,5 do local ab=L*af+ag
Q=aC(ab)local aj=bn(ab)local ad,ac=ah*aj*af*U+aG+ae,ah*Q*U-al+(aG+ae)*L
if K.abs(ad)>=0.000001 then L=L-ac/ad else if ad>0 then L=L-ac elseif ad<0 then L=L+ac end end end
Q=aC(L*af+ag)if E==0 then L=0
Q=0 end
local ak=ah*Q*L
local _=K.min(G*ao*ak*ap/aq/ay,0)-W
if _<0.01 and L<0 then _=0 end
return L,ah*Q*U,ao*ak*ap*0.99/aq/ay,E*L*ao/T*2,M,_,L,M,Q end
function p()return{0,0,0,0,0,0,0,0}end
function m(D)local E,F=h(D[1]),h(D[2])return d(E,0,5),a(E,5),a(E,6),a(E,7),d(E,8,4),d(E,12,5),d(F,0,10),a(F,19),d(F,10,3),d(F,13,3),d(F,16,3),D[3],D[4],D[5],D[6],D[7]end
function n(D,E,F,G,H,I,J,O,R,S,V,W,P,N,aa,U)local X,Y=e(D,0,5)|b(E,5)|b(F,6)|b(G,7)|e(H,8,4)|e(I,12,5),e(J,0,10)|e(R,10,3)|e(S,13,3)|e(V,16,3)|b(O,19)return{X,Y,W or 0,P or 0,N or 0,aa or 0,U or 0,0}end
function q(D,E,F,G,H,I,J,O)return{D or 0,E or 0,F or 0,G or 0,H or 0,I or 0,J and 1 or 0,O and 1 or 0}end
function r(D)local E=h(D[5])return D[1],D[2],D[3],D[4],a(E,0),a(E,1),a(E,2),a(E,3),a(E,4),a(E,5),a(E,6),a(E,7)end
local function bo(D)return D[1],D[2],D[3],D[4],D[5],aM(K.floor(D[6]or 0),0,7),(D[7]or 0)~=0,(D[8]or 0)~=0 end
local function bp(D,E,F,G)local H,I=K.abs(D)>a_,E<bb
return G or F==0 or H or I end
local function bq(D,E,F)local G,H=D*(F and 0 or 1),F and 0 or E
return G,G>=1 and G<=7,G>=2 and G<=7,G>=3 and G<=7,H==0,H>=0 and H<=13,H>=14 and H<=20,H==14,H~=14 end
local function br(D,E)local F=-K.floor((D-1)*2)/7.2
return F,F<be and E,K.max(-F,0)end
local function bs(D,E,F,G,H,I,J)if I then return 0,0,0,0,J end
return D,E,F,G,H end
local function bt(D,E,F,G,H,I)local J=E and aJ-20 or aJ
local O=I<J
return aB(F),aA(F,O),aB(G),aA(G,D),aB(H),aA(H,E)end
local function bu(D)return D>=-50 and D<=50 end
local function bv(D,E,F,G,H,I)local J=D and E<bd
local O,R=J and bc or aK,G>aK
local S=G>O and not H
local V,W=aN(F,S,bh)return R and I,S,V,W end
local function bw(D,E,F,G,H,I,J,O,R,S,V,W,P,N,aa,U,X,Y,T,M)local Z,al,ae,af,ag=D and G,D and V and F,G and J,K.abs(T)<bf,bu(W)and not(G or P)local L=ag and not F
local Q,ak,_,ai,ab,aj,ad=L or N and not aa,F and E and not D and J and ag and af,H and O and U and Y,ae and not E or N and E and aa,I and R and X and Y,I and S and Y,not aa and D and F
local ac=M or ad
local aD,aE,am=Q or D and not(I and S)or ak or ac,Q or N and U or aj or ac,not D and not E
local an,ar,as=not J and am,i(D,ai,aE),i(E,aj,aD)local aO=(D or E)and not ar and not as
return ar,as,i(F,E and J,Z or am or ac),_ or ab or an or al,aO end
local function bx(D,E,F)local G,H=aN(E,F,bg)local I=(D+(H and 1 or 0))%21
local J=I-D
return I,J~=0,G end
local function by(D,E,F,G,H,I,J,O,R)local S=G or not J
local V,W,P=S and 0 or I,bm(F,G,O)local N=R and 0 or H*0.2+D*0.8
return N,K.min(aM(V,E-0.1,E+0.02),0),W,P end
function o(D,E)local F,G,H,I,J,O,R,S,V,W,P,N,aa,U,X,Y=m(E)local T,M,Z,al,ae,af,ag,L=bo(D)local Q=bp(T,Z,ae,ag)local ak,_,ai,ab,aj,ad,ac,aD,aE=bq(af,F,Q)local am,an,ar=br(al,L)local as,aO,bz,bA,bB,bC,bD,bE,bF=l(T,M,F,ae,ak,G,H,I,_,an,X,am,N,aa,U)local at,aP,bG,bH,bI=bs(as,bA,bz,bB,bC,Q,ar)local bJ,bK,aQ,bL,bM,bN=bt(G,H,P,V,W,at)local bO,bP,bQ,bR=bv(G,X,O,bH,_,aQ)local aR,aS,aT,bS,aU=bw(G,H,I,_,ai,ab,aj,ad,ac,aD,aE,at,an,bR,L,aQ,bM,bJ,T,Q)if aU then at,aP=0,0 end
local bT,bU,bV=bx(F,J,bS)local aV,bW,bX,bY=by(Y,X,R,S,bG,am,L,bO,Q or aU)local bZ=b(bU,0)|b(aR,1)|b(aS,2)|b(aT,3)|b(_,4)|b(an,5)|b(bP,6)local b_,ca={at,aP,aV,bI,bZ,0,0,0},n(bT,aR,aS,aT,bV,bQ,bX,bY,bL,bN,bK,bD,bE,bF,bW,aV)return b_,ca end
function j(cd,cb)local ce={cb[1],cb[2],c(cb[3]),c(cb[4]),c(cb[5]),c(cb[6]),c(cb[7]),cb[8]}local cf,cc=o(cd,ce)local cg={cc[1],cc[2],f(cc[3]),f(cc[4]),f(cc[5]),f(cc[6]),f(cc[7]),cc[8]}return cf,cg end
--[[
//# sourceMappingURL=main.lua.map
]]