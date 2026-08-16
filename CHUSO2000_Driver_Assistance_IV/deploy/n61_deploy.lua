link_tbl={nil,{2},{1},{3},{2},{5,6},nil,{5,6},{3,4},nil,{3,4},{7},{6},{8,9},{7},nil,{7},{10},{9},{11},{10},{12},{11},{13,14},{12},nil,{12},{15,16},{14},nil,{14},nil}stop_type_tbl={{5,6,7,8,9,10,11},{5,6,7,8,9,10,11},{5,6,7,8,9,10,11},{5,6,7,8,9,10,11},{5,6,7,8,9,10,11},{5,10,11},{5,6,7,11},{5,6,7,11},{5,6,10,11},{5},{5,6,9},{5,6,7,8,9,10,11},{5,6,7,8,9,10,11},{5,10,11},{5,6,7,10,11},{5,6,7,10,11}}coord_tbl={{1168,-4430},{158,-4590},{1355,-3762},{1355,-3751},{1656,-3770},{2976,-3930},{3743,-4888},{3768,-5270},{4362,-5935},{5390,-6653},{6584,-8240},{6991,-9184},{6915,-9346},{5910,-9310},{4330,-8210},{4330,-8210}}meterage={-1670,-1610,0,0,300,1635,2925,3500,4190,5570,7810,9030,9220,10370,12320,12320}not4srv={[1]=1,[5]=1,[8]=1,[13]=1}doorcut_tbl={[6]={{i=6,m=6},{m=6,o=0}},[10]={{i=6,m=6},{m=6,o=0}},[14]={{i=6,m=6},{m=6,o=0}}}function b2i(a)return a and 1 or 0 end
function find_rte(a,b,c)if not link_tbl[a*2-b2i(c)]then return end
tr,q={[a]=a},{a}for e=1,100 do for h,d in ipairs(link_tbl[q[1]*2-b2i(c)]or{})do if not tr[d]then table.insert(q,d)tr[d]=q[1]end end
table.remove(q,1)if#q==0 then break end end
if tr[b]then rte={b,inb=c,outb=not c}for e=1,100 do if b==a then break end
table.insert(rte,1,tr[b])b=tr[b]end
return rte end end
function get_rte(a,b)rte_in,rte_out=find_rte(a,b,true),find_rte(a,b)if rte_in and rte_out then return#rte_in<#rte_out and rte_in or rte_out end
return rte_in or rte_out or{}end
function is_stop(a,b,c)if b[1]==a or b[#b]==a then return true end
for e,h in ipairs(stop_type_tbl[a]or{})do if h==c then return true end end end
function len(a,b,c,e)return math.sqrt((a-c)*(a-c)+(b-e)*(b-e))end
function find_nearest_sta(a,b,c)local e=nil
for h,d in pairs(coord_tbl)do if d and len(d[1],d[2],a,b)<c then c=len(d[1],d[2],a,b)e=h end end
return e end
ROUTE=nil
OLD_CODE_A=nil
function onTick()local a,b,c,e,h,d,m,i,j,k,l
a=input.getNumber(1)b=input.getNumber(2)c=input.getNumber(3)e=math.floor(input.getNumber(4))local o,p,n=e>>6&63,e&63,e>>12&15
d=input.getBool(1)j=input.getBool(2)i=input.getBool(3)m=input.getBool(4)k=input.getBool(5)l=false
if m or j then local f=find_nearest_sta(a,b,100)if f and meterage[f]then c=meterage[f]if k or j then l=true end end end
if OLD_CODE_A~=e then ROUTE=get_rte(o,p)end
if ROUTE and ROUTE.inb then h=-1 else h=1 end
OLD_CODE_A=e
local g=stops(c,n,h,d,m,i)if g.mode==1 or g.mode==3 then output.setNumber(1,g.ns_sid)output.setNumber(2,g.nns_sid)else output.setNumber(1,g.n_sid)output.setNumber(2,g.ns_sid)end
output.setNumber(3,g.mode)output.setNumber(4,g.dir)output.setNumber(9,c)if l then output.setNumber(31,0)output.setNumber(32,c)else output.setNumber(31,1)output.setNumber(32,0)end
output.setBool(1,d)output.setBool(2,j)output.setBool(3,doorcut_tbl[g.n_sid]~=nil)output.setBool(4,g.set_ap)output.setBool(5,g.reset_ap)end
function stops(a,b,c,e,h,d)local m,i,j,k=0,0,0,0
local l=0
local o,p=false,false
if e and ROUTE then local n=0
local g=0
if h or d then g=-300 end
for f=1,#ROUTE do local r=((meterage[ROUTE[f]]or math.huge)-a)*c
if r<g then n=f end end
if n~=#ROUTE then m=ROUTE[n+1]end
for f=n+1,#ROUTE do if is_stop(ROUTE[f],ROUTE,b)then local r=ROUTE[f]if i==0 then i=r else j=r
break end end end
if i~=0 then local f=((meterage[i]or math.huge)-a)*c
if f<520 and f>=400 then d=true
o=true end
if f>520 then d=false
p=true end
k=2
if d then k=3 end
if h and f<520 then k=1 end end end
if c==-1 then l=2 end
if c==1 then l=1 end
return{mode=k,n_sid=m,ns_sid=i,nns_sid=j,dir=l,set_ap=o,reset_ap=p}end
--[[
//# sourceMappingURL=n61.lua.map
]]