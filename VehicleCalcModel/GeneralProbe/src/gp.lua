-- Stormworks entry for the general probe: composite <-> gp_*, and the HTTP poll.
-- Build input for storm-lua-minify (dofile is flattened); not pasted as-is.
dofile("gp_core")

local PORT, EVERY = 8766, 30   -- host port, poll period [ticks]
local inn, inb, res, t = {}, {}, "", 0

--@storm export
function onTick()
    for i = 1, 32 do
        inn[i] = input.getNumber(i)
        inb[i] = input.getBool(i)
    end
    local on, ob = gp_tick(inn, inb)
    for i = 1, 32 do
        output.setNumber(i, on[i])
        output.setBool(i, ob[i])
    end
    t = t + 1
    if t % EVERY == 0 then
        local aborts, _, _, id = gp_stat()
        local r = {"/p?t=", t, "&a=", aborts, "&c=", id, "&s=", res, "&m="}
        for i = 0, gp_n() - 1 do r[#r + 1] = gp_rec(i) .. "," end
        async.httpGet(PORT, table.concat(r))
        res = ""
    end
end

--@storm export
function httpReply(port, request, reply)
    for line in reply:gmatch("[^\n]+") do res = res .. gp_msg(line) .. "," end
end
