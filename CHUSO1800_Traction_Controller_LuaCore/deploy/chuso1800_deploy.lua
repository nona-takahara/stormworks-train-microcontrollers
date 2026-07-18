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
local O=12.16
local aj=0.00029
local ak=0.07
local S=0.85
local P=150
local X=4
local Y=5.31
local Z=0.86/2
local ac=35*1000
local ay={7.428,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334,0,2.568,1.734,1.218,0.7570,0.4110,0.1334}local az={0,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334,3.714,2.568,1.734,1.218,0.7570,0.4110,0.1334}local al=200
local aA=property.getNumber("Over Speed Th. [m/s]")local ad=property.getNumber("Power Limit Current [A]")local aB=4
local am=300
local aC=400
local aD=-0.1
local aE=-0.05
local aF=3
local an=6
local aG=12
local aH=30
local aI=600
local aJ=30
local ae=aI
local aK=ae//aJ
local aL=1
local function ao(j,k,l)if j<k then return k end
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
local function af(j,k)if k then return math.min(j+1,an)end
return 0 end
local function ag(j)return j>=an end
local function ap(j,k,l)if not k then return 0,false end
local m=j+1
if m>=l then return 0,true end
return m,false end
local function aM(j,k,l)local m=l and math.min(j+aK,ae)or math.max(j-aL,0)local n=k and m>0 or m>=ae
return m,n end
local function ah(j)return j*aj*S*P/(S*math.abs(j)+P)end
local function aN(j)return aj*S*P*P/((S*math.abs(j)+P)*(S*math.abs(j)+P))end
function physics_tick(j,k,l,m,n,o,p,s,v,w,z,A,u,t,G)local E=j*9.55*Y/Z
local B=l+1
local C=100000
local x=4
local r=150
local y=al
if not o and not p then k=0 end
if o then x=8 end
if p and B==1 then x=4 end
if s then if w then local Q=m*X*9.55*O*G*u*Y*0.99/Z/ac
r=t+(Q-z)*20
r=r*math.min(1,470/(O*math.abs(E))/ah(r+u*0.15))else if v and n<=3 then y=t end
if v and n>3 then y=ad end
if not v then y=0 end
if y==0 then y=math.max(math.min(0,u+20),u-20)end
r=t+(u-y)*0.1 end else y=t
if n==0 then y=0 end
r=t+(u-y)*0.1
if n~=0 and r>180 then r=180 end end
if x==8 then C=ay[B]end
if x==4 then C=az[B]end
if r<20 then r=20 elseif r>500 then r=500 end
local T,K,R,I,J=k/x,E,C/x,m*0.2,r*m
local q=al
local D=0
for Q=1,5 do local L=q*I+J
D=ah(L)local U=aN(L)local F=O*U*I*K+ak+R
local M=O*D*K-T+(ak+R)*q
if math.abs(F)>=0.000001 then q=q-M/F else if F>0 then q=q-M elseif F<0 then q=q+M end end end
D=ah(q*I+J)if k==0 then q=0
D=0 end
local H=9.55*O*D*q
local N=math.min(m*X*H*Y/Z/ac,0)-A
if N<0.01 and q<0 then N=0 end
return q,O*D*E,X*H*Y*0.99/Z/ac,k*q*X/x*2,r,N,q,r,D end
function zero_state()return{0,0,0,0,0,0,0,0}end
function decode_state(j)local k=to_u32(j[1])local l=to_u32(j[2])return get_bits(k,0,5),get_bit(k,5),get_bit(k,6),get_bit(k,7),get_bits(k,8,4),get_bits(k,12,5),get_bits(l,0,10),get_bit(l,19),get_bits(l,10,3),get_bits(l,13,3),get_bits(l,16,3),j[3],j[4],j[5],j[6],j[7]end
function encode_state(j,k,l,m,n,o,p,s,v,w,z,A,u,t,G,E)local B=put_bits(j,0,5)|put_bit(k,5)|put_bit(l,6)|put_bit(m,7)|put_bits(n,8,4)|put_bits(o,12,5)local C=put_bits(p,0,10)|put_bits(v,10,3)|put_bits(w,13,3)|put_bits(z,16,3)|put_bit(s,19)return{B,C,A or 0,u or 0,t or 0,G or 0,E or 0,0}end
function encode_stateless_in(j,k,l,m,n,o,p,s)return{j or 0,k or 0,l or 0,m or 0,n or 0,o or 0,p and 1 or 0,s and 1 or 0}end
function decode_stateless_out(j)local k=to_u32(j[5])return j[1],j[2],j[3],j[4],get_bit(k,0),get_bit(k,1),get_bit(k,2),get_bit(k,3),get_bit(k,4),get_bit(k,5),get_bit(k,6),get_bit(k,7)end
local function aO(j)return j[1],j[2],j[3],j[4],j[5],ao(math.floor(j[6]or 0),0,7),(j[7]or 0)~=0,(j[8]or 0)~=0 end
local function aP(j,k,l,m)local n=math.abs(j)>aA
local o=k<aB
return m or l==0 or n or o end
local function aQ(j,k,l)local m=j*(l and 0 or 1)local n=l and 0 or k
return m,m>=1 and m<=7,m>=2 and m<=7,m>=3 and m<=7,n==0,n>=0 and n<=13,n>=14 and n<=20,n==14,n~=14 end
local function aR(j,k)local l=-math.floor((j-1)*2)/7.2
return l,l<aE and k,math.max(-l,0)end
local function aS(j,k,l,m,n,o,p)if o then return 0,0,0,0,p end
return j,k,l,m,n end
local function aT(j,k,l,m,n,o)local p=k and ad-20 or ad
local s=o<p
return ag(l),af(l,s),ag(m),af(m,j),ag(n),af(n,k)end
local function aU(j)return j>=-50 and j<=50 end
local function aV(j,k,l,m,n,o)local p=j and k<aD
local s=p and aC or am
local v=m>am
local w=m>s and not n
local z,A=ap(l,w,aH)return v and o,w,z,A end
local function aW(j,k,l,m,n,o,p,s,v,w,z,A,u,t,G,E,B,C,x,r)local y=j and m
local T=j and z and l
local K=m and p
local R=math.abs(x)<aF
local I=aU(A)and not(m or u)local J=I and not l
local q=J or t and not G
local D=l and k and not j and p and I and R
local H=n and s and E and C
local N=K and not k or t and k and G
local Q=o and v and B and C
local L=o and w and C
local U=not G and j and l
local F=r or U
local M=q or j and not(o and w)or D or F
local ai=q or t and E or L or F
local V=not j and not k
local W=not p and V
local _=sr_latch(j,N,ai)local aa=sr_latch(k,L,M)local aq=(j or k)and not _ and not aa
return _,aa,sr_latch(l,k and p,y or V or F),H or Q or W or T,aq end
local function aX(j,k,l)local m,n=ap(k,l,aG)local o=(j+(n and 1 or 0))%21
local p=o-j
return o,p~=0,m end
local function aY(j,k,l,m,n,o,p,s,v)local w=m or not p
local z=w and 0 or o
local A,u=aM(l,m,s)local t=v and 0 or n*0.2+j*0.8
return t,math.min(ao(z,k-0.1,k+0.02),0),A,u end
function core_tick(j,k)local l,m,n,o,p,s,v,w,z,A,u,t,G,E,B,C=decode_state(k)local x,r,y,T,K,R,I,J=aO(j)local q=aP(x,y,K,I)local D,H,N,Q,L,U,F,M,ai=aQ(R,l,q)local V,W,_=aR(T,J)local aa,aq,aZ,a_,ba,bb,bc,bd,be=physics_tick(x,r,l,K,D,m,n,o,H,W,B,V,t,G,E)local ab,ar,bf,bg,bh=aS(aa,a_,aZ,ba,bb,q,_)local bi,bj,as,bk,bl,bm=aT(m,n,u,z,A,ab)local bn,bo,bp,bq=aV(m,B,s,bg,H,as)local at,au,av,br,aw=aW(m,n,o,H,N,Q,L,U,F,M,ai,ab,W,bq,J,as,bl,bi,x,q)if aw then ab,ar=0,0 end
local bs,bt,bu=aX(l,p,br)local ax,bv,bw,bx=aY(C,B,v,w,bf,V,J,bn,q or aw)local by=put_bit(bt,0)|put_bit(at,1)|put_bit(au,2)|put_bit(av,3)|put_bit(H,4)|put_bit(W,5)|put_bit(bo,6)local bz={ab,ar,ax,bh,by,0,0,0}local bA=encode_state(bs,at,au,av,bu,bp,bw,bx,bk,bm,bj,bc,bd,be,bv,ax)return bz,bA end
function calculateTick(bD,bB)local bE={bB[1],bB[2],i2f(bB[3]),i2f(bB[4]),i2f(bB[5]),i2f(bB[6]),i2f(bB[7]),bB[8]}local bF,bC=core_tick(bD,bE)local bG={bC[1],bC[2],f2i(bC[3]),f2i(bC[4]),f2i(bC[5]),f2i(bC[6]),f2i(bC[7]),bC[8]}return bF,bG end
--[[
//# sourceMappingURL=main.lua.map
]]