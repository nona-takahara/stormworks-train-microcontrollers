-- Chuso 2000 Series Driving Support System
link_tbl={nil,{2},{1},{3},{2},{5,6},nil,{5,6},{3,4},nil,{3,4},{7},{6},{8,9},{7},nil,{7},{10},{9},{11},{10},{12},{11},{13,14},{12},nil,{12},{15},{14},{17},nil,nil,{15}}
stop_type_tbl={{5,6,7,8,9,10},{5,6,7,10},{5,6,7,8,9,10},{5,6,7,8,9,10},{5,6,7,8,9,10},{5,10},{5,6,7},{5,6,7},{5,6,10},{5},{5,6,9},{5,6,7,8,9,10},{5,6,7,8,9,10},{5,10},{5,6,7,10},nil,{5,6,7,8,9,10}}
coord_tbl={{1168,-4430},{303,-4819},{1355,-3762},{1355,-3751},{1656,-3770},{2976,-3930},{3743,-4888},{3768,-5270},{4362,-5935},{5390,-6653},{6584,-8240},{6991,-9184},{6915,-9346}}
meterage={nil,nil,0,0,300,1635,2925,3500,4190,5570,7810,9030,9220}
not4srv={[5]=1,[8]=1,[13]=1}
doorcut_tbl={[6]={{i=6,m=6},{m=6,o=0}},[10]={{i=6,m=6},{m=6,o=0}}}

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

function is_stop(id, rte, ttype)
	if rte[1] == id or rte[#rte] == id then return true end
	for _, v in ipairs(stop_type_tbl[id] or {}) do
		if v == ttype then return true end
	end
end

function len(x1, y1, x2, y2)
	return math.sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2))
end

function find_nearest_sta(px, py, l)
	local b = nil
	for i, s in pairs(coord_tbl) do
		if s and len(s[1], s[2], px, py) < l then
			l = len(s[1], s[2], px, py)
			b = i
		end
	end
	return b
end

ROUTE = nil
OLD_CODE_A = nil
function onTick()
	local px, py, kp, codeA, dr, en, dop, isap, start_ctrl, dop_start, upkp
	px = input.getNumber(1)              -- GPS X
	py = input.getNumber(2)              -- GPS Y
	kp = input.getNumber(3)              -- meterage
	codeA = math.floor(input.getNumber(4)) -- code A (Memreg2[N3])
	local frm,dest,ttype = (codeA >> 6) & 63, codeA & 63, (codeA >> 12) & 15
	en = input.getBool(1)                -- Enable
	start_ctrl = input.getBool(2)
	isap = input.getBool(3)              -- Approaching and not departure latch
	dop = input.getBool(4)               -- Door Open
	dop_start = input.getBool(5)
	upkp = false

	-- Reset meterage
	if dop or start_ctrl then
		local ix = find_nearest_sta(px, py, 100)
		if ix and meterage[ix] then
			kp = meterage[ix]
			if dop_start or start_ctrl then
				upkp = true
			end
		end
	end

	if OLD_CODE_A ~= codeA then
		ROUTE = get_rte(frm, dest)
	end
	if ROUTE and ROUTE.inb then dr = -1 else dr = 1 end
	OLD_CODE_A = codeA

	local res = stops(kp, ttype, dr, en, dop, isap)

	if res.mode == 1 or res.mode == 3 then
		output.setNumber(1, res.ns_sid)
		output.setNumber(2, res.nns_sid)
	else
		output.setNumber(1, res.n_sid)
		output.setNumber(2, res.ns_sid)
	end
	output.setNumber(3, res.mode)
	output.setNumber(4, res.dir)

	output.setNumber(9, kp) -- for debug

	if upkp then
		output.setNumber(31, 0)
		output.setNumber(32, kp)
	else
		output.setNumber(31, 1)
		output.setNumber(32, 0)
	end

	output.setBool(1, en)
	output.setBool(2, start_ctrl)
	output.setBool(3, doorcut_tbl[res.n_sid] ~= nil)
	output.setBool(4, res.set_ap)
	output.setBool(5, res.reset_ap)
end

function stops(kp, ttype, dr, en, dop, isap)
	local n_sid, ns_sid, nns_sid, mode = 0, 0, 0, 0
	local dir3000 = 0
	local set_ap, reset_ap = false, false

	if en and ROUTE then
		local pix = 0
		local ltstg = 0
		if dop or isap then ltstg = -300 end
		for i = 1, #ROUTE do
			local lts = ((meterage[ROUTE[i]] or math.huge) - kp) * dr
			if lts < ltstg then pix = i end
		end

		if pix ~= #ROUTE then
			n_sid = ROUTE[pix + 1]
		end
		for i = pix + 1, #ROUTE do
			if is_stop(ROUTE[i], ROUTE, ttype) then
				local s_sid = ROUTE[i]
				if ns_sid == 0 then
					ns_sid = s_sid
				else
					nns_sid = s_sid
					break
				end
			end
		end

		if ns_sid ~= 0 then
			local lts = ((meterage[ns_sid] or math.huge) - kp) * dr
			if lts < 520 and lts >= 400 then
				isap = true; set_ap = true
			end
			if lts > 520 then
				isap = false; reset_ap = true
			end
			mode = 2
			if isap then mode = 3 end
			if dop and lts < 520 then mode = 1 end
		end
	end
	if dr == -1 then dir3000 = 2 end
	if dr == 1 then dir3000 = 1 end
	return { mode = mode, n_sid = n_sid, ns_sid = ns_sid, nns_sid = nns_sid, dir = dir3000, set_ap = set_ap, reset_ap =
	reset_ap }
end
