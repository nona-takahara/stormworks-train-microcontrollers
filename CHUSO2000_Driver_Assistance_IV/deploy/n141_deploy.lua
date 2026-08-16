link_tbl={nil,{2},{1},{3},{2},{5,6},nil,{5,6},{3,4},nil,{3,4},{7},{6},{8,9},{7},nil,{7},{10},{9},{11},{10},{12},{11},{13,14},{12},nil,{12},{15,16},{14},nil,{14},nil}arc_type_tbl={{3},{1},{2},nil,{min=10,max=19},{min=30,max=39},{min=50,max=59},{min=70,max=79},{min=70,max=79},{min=20,max=29},{min=40,max=49}}arc_trk_tbl={{29},{min=20,max=28},{33},{34},{39},nil,{min=40,max=48},{49},nil,nil,nil,{min=50,max=58},{59},nil,{61},{63}}function gI(a)return toint(input.getNumber(a))end
function gN(a)return input.getNumber(a)end
function gB(a)return input.getBool(a)end
function toint(a)local b=math.modf(a)return b end
function pk(a)local b=('f'):unpack(('I4'):pack(a))return b end
function b2i(a)return a and 1 or 0 end
function find_rte(a,b,d)if not link_tbl[a*2-b2i(d)]then return end
tr,q={[a]=a},{a}for k=1,100 do for h,f in ipairs(link_tbl[q[1]*2-b2i(d)]or{})do if not tr[f]then table.insert(q,f)tr[f]=q[1]end end
table.remove(q,1)if#q==0 then break end end
if tr[b]then rte={b,inb=d,outb=not d}for k=1,100 do if b==a then break end
table.insert(rte,1,tr[b])b=tr[b]end
return rte end end
function get_rte(a,b)rte_in,rte_out=find_rte(a,b,true),find_rte(a,b)if rte_in and rte_out then return#rte_in<#rte_out and rte_in or rte_out end
return rte_in or rte_out or{}end
local l=0
local c={}function onTick()local a,b,d,k=gI(11),gI(12),gI(13),gI(14)local h=5<<20|(k&3)<<14|(d&3)<<12|(a&63)<<6|b&63
local f=gB(11)local p=gB(12)local m=gB(13)local n=gB(14)local i,o,g=gI(1),gI(2),gI(3)local r=(i&15)<<12|(o&63)<<6|g&63
local s=gB(3)local t,u=gI(4),gI(5)local v=(t&15)<<12|u&63
local w=gB(5)local x=gI(6)local y=gB(6)local z=gI(8)local A=gB(10)if f and(h~=l or p)then table.insert(c,h)l=h end
if s then local j=get_rte(o,g)local e=0
if j and j.inb then e=10000 elseif j and j.outb then e=20000 end
e=e+(arc_type_tbl[i]and(arc_type_tbl[i][1]or arc_type_tbl[i].min)or 0)*100
e=e+(arc_trk_tbl[g]and(arc_trk_tbl[g][1]or arc_trk_tbl[g].min)or 0)table.insert(c,math.floor(e)|1<<20)table.insert(c,r|2<<20)end
if w then table.insert(c,v|4<<20)end
if A then table.insert(c,z)end
if y then table.insert(c,x|6<<20)end
if#c~=0 then output.setNumber(1,pk(c[1]))table.remove(c,1)else output.setNumber(1,pk(1<<24))end
output.setNumber(2,#c)output.setBool(2,not n and m)output.setBool(3,n and m)output.setBool(4,d==3)end
--[[
//# sourceMappingURL=n141.lua.map
]]