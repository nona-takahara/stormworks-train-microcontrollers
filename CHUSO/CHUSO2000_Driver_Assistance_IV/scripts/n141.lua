link_tbl={nil,{2},{1},{3},{2},{5,6},nil,{5,6},{3,4},nil,{3,4},{7},{6},{8,9},{7},nil,{7},{10},{9},{11},{10},{12},{11},{13,14},{12},nil,{12},{15,16},{14},nil,{14}}
arc_type_tbl={{3},{1},{2},nil,{min=10,max=19},{min=30,max=39},{min=50,max=59},{min=70,max=79},{min=70,max=79},{min=20,max=29},{min=40,max=49}}
arc_trk_tbl={{29},{min=20,max=28},{33},{34},{39},nil,{min=40,max=48},{49},nil,nil,nil,{min=50,max=58},{59},nil,{61},{63}}

function gI(i)
    return toint(input.getNumber(i))
end

function gN(i)
    return input.getNumber(i)
end

function gB(i)
    return input.getBool(i)
end

function toint(v)
    local _=math.modf(v)
	return _
end

function pk(intv)
	local r = ('f'):unpack(('I4'):pack(intv))
	return r
end

function b2i(f) return f and 1 or 0 end

function find_rte(from, to, inb)
	if not link_tbl[from * 2 - b2i(inb)] then return end
	tr, q = { [from] = from }, { from }
	for _ = 1, 100 do
		for _, v in ipairs(link_tbl[q[1] * 2 - b2i(inb)] or {}) do
			if not tr[v] then
				table.insert(q, v)
				tr[v] = q[1]
			end
		end
		table.remove(q, 1)
		if #q == 0 then break end
	end
	if tr[to] then
		rte = { to, inb = inb, outb = not inb }
		for _ = 1, 100 do
			if to == from then break end
			table.insert(rte, 1, tr[to])
			to = tr[to]
		end
		return rte
	end
end

function get_rte(origin, dest)
	rte_in, rte_out = find_rte(origin, dest, true), find_rte(origin, dest)
	if rte_in and rte_out then return #rte_in < #rte_out and rte_in or rte_out end
	return rte_in or rte_out or {}
end

local old_stat=0
local pending_info={}
function onTick()
    -- from drive-support.lua
    local id1,id2,mode,dir=gI(11),gI(12),gI(13),gI(14)
    local stat=5<<20 | (dir&3)<<14 | (mode&3)<<12 | (id1&63)<<6 | (id2&63)
    local en=gB(11)
    local start_ctrl=gB(12)
    local doorcut=gB(13)
    local forward=gB(14)

    -- from GUI
    local ttype,frm,dest=gI(1),gI(2),gI(3)
    local arc_teinishi=(ttype&15)<<12 | (frm&63)<<6 | (dest&63)
    local up_arc=gB(3)

    -- from GUI
    local idp_ttype,idp_togo=gI(4),gI(5)
    local idp_arc_teinishi=(idp_ttype&15)<<12 | (idp_togo&63)
    local idp_up_arc=gB(5)

    --- from GUI
    local menu=gI(6)
    local up_menu=gB(6)

    --- from GUI
    local opid=gI(8)
    local up_opid=gB(10)

    if en and ((stat ~= old_stat) or start_ctrl) then
        table.insert(pending_info, stat)
        old_stat = stat
    end

    if up_arc then
        local ROUTE = get_rte(frm, dest)
        local arc = 0
    	if ROUTE and ROUTE.inb then arc = 10000 elseif ROUTE and ROUTE.outb then arc = 20000 end
    	arc = arc + (arc_type_tbl[ttype] and (arc_type_tbl[ttype][1] or arc_type_tbl[ttype].min) or 0) * 100
    	arc = arc + (arc_trk_tbl[dest] and (arc_trk_tbl[dest][1] or arc_trk_tbl[dest].min) or 0)

        table.insert(pending_info,math.floor(arc)|(1<<20))
        table.insert(pending_info,arc_teinishi|(2<<20))
    end

    if idp_up_arc then
        table.insert(pending_info,idp_arc_teinishi|(4<<20))
    end

    if up_opid then
        table.insert(pending_info,opid)
    end

    if up_menu then
        table.insert(pending_info,menu|(6<<20))
    end

    if #pending_info ~= 0 then
        output.setNumber(1,pk(pending_info[1]))
        table.remove(pending_info,1)
    else
        output.setNumber(1,pk(1<<24))
    end
    output.setNumber(2, #pending_info)

    output.setBool(2, (not forward) and doorcut) -- Doorcut A
    output.setBool(3, forward and doorcut) -- Doorcut B
    output.setBool(4, mode==3) -- Nearby station
end
