-- Stormworks deployment entry point for the vehicle probe (storm-lua-minify
-- build input; see LUA_CODING_GUIDE.md). Logic is in probe_core.lua; this file
-- only moves composite values and HTTP text.
--
-- Input composite : ch1-3 x/y/z, ch9 speed [m/s], ch16 ready (0 = off), ch17 battery,
--                   ch18-21 slip 1-4 (recorded only, as bits 0-3 of one integer; 0 when not wired).
-- Output composite: ch1 motor, ch2 brake.
-- Input ch24      : HTTP port (the microcontroller property "probe_port"; 0 = 8765). One probe per vehicle, one server per port.
-- HTTP (one request in flight): GET /l?d=<dropped>&r=<rec;rec;...>
--   rec = t,x,y,z,v,motor,brake,batt,state,reason,slip(bits),aux1,aux2
--   (reason is the running segment number while state = 1; aux1/aux2 = the input channels chosen by command 6)
-- The reply is one command line "cmd,args..." (0 = nothing):
--   1,delay,{len,vend,vmin, m: c0,c1,c2,ci,ct,A,f, b: c0,c1,c2,ci,ct,A,f}...  probe_set: one or more
--     17-number segments run back to back (see probe_core.lua)
--   2  probe_ack    3,dir  probe_dir    4,motor,brake,len  probe_jog
--   5,interval,batch  sampling interval while not IDLE [tick]; samples per request (default 2, 8)
--   6,ch1,ch2  input channels recorded as aux1, aux2 (0 = none)    8  probe_cancel
dofile("probe_core")
dofile("probe_site")

local port = 8765
local batch = 8
local HEARTBEAT = 60
local interval = 2
local aux1, aux2 = 0, 0
local buf, nbuf, dropped, busy, wait, lastv = {}, 0, 0, false, 0, 0

--@storm export
function onTick()
    local x, y, z, v, ready, batt = input.getNumber(1), input.getNumber(2), input.getNumber(3),
        input.getNumber(9), input.getNumber(16), input.getNumber(17)
    local slip = 0
    for i = 0, 3 do
        if input.getNumber(18 + i) ~= 0 then slip = slip | 1 << i end
    end
    lastv = v
    local p = math.floor(input.getNumber(24))
    port = p > 0 and p or 8765
    local motor, brake, st, r, t = probe_tick(x, y, v, ready)
    output.setNumber(1, motor)
    output.setNumber(2, brake)
    if (st ~= 0 and t % interval == 0) or t % HEARTBEAT == 0 then
        if nbuf < 60 then
            nbuf = nbuf + 1
            buf[nbuf] = string.format("%d,%.2f,%.1f,%.1f,%.3f,%.3f,%.3f,%.3f,%d,%d,%d,%.3f,%.3f",
                t, x, y, z, v, motor, brake, batt, st, r, slip,
                aux1 > 0 and input.getNumber(aux1) or 0, aux2 > 0 and input.getNumber(aux2) or 0)
        else
            dropped = dropped + 1
        end
    end
    wait = wait + 1
    if wait > 300 then busy = false end
    if not busy and nbuf > 0 and (nbuf >= batch or st == 0) then
        async.httpGet(port, "/l?d=" .. dropped .. "&r=" .. table.concat(buf, ";", 1, nbuf))
        buf, nbuf, dropped, busy, wait = {}, 0, 0, true, 0
    end
end

--@storm export
function httpReply(rport, request, reply)
    if rport ~= port then return end
    busy = false
    local a = {}
    for s in (reply or ""):gmatch("[^,]+") do a[#a + 1] = tonumber(s) end
    local c = a[1]
    if c == 1 then probe_set(table.unpack(a, 2, #a))
    elseif c == 2 then probe_ack(lastv)
    elseif c == 3 then probe_dir(a[2])
    elseif c == 4 then probe_jog(a[2], a[3], a[4])
    elseif c == 5 then interval, batch = math.max(1, math.floor(a[2] or 2)), math.min(40, math.max(1, math.floor(a[3] or 8)))
    elseif c == 6 then aux1, aux2 = math.min(32, math.max(0, math.floor(a[2] or 0))), math.min(32, math.max(0, math.floor(a[3] or 0)))
    elseif c == 8 then probe_cancel()
    end
end
