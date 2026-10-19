-- Entry smoke test with a mocked Stormworks API: `lua test/entry_smoke.lua`.
local dir = (debug.getinfo(1, "S").source:sub(2):match("(.*/)")) or "./"
local real_dofile = dofile
dofile = function(name) return real_dofile(dir .. "../src/" .. name .. ".lua") end

local ch, out, reqs = {}, {}, {}
input = { getNumber = function(n) return ch[n] or 0 end }
output = { setNumber = function(n, v) out[n] = v end }
async = { httpGet = function(port, path) reqs[#reqs + 1] = { port, path } end }

dofile("probe")
SITE_LO, SITE_HI = 0, 10000
ch[1], ch[9], ch[16], ch[17], ch[19], ch[21] = 5000, 10, 1, 0.95, 1, 1

local failed = 0
local function check(name, cond) if not cond then failed = failed + 1; print("FAIL: " .. name) end end

for _ = 1, 60 do onTick() end
check("idle heartbeat request", #reqs == 1 and reqs[1][1] == 8765 and reqs[1][2]:find("^/l%?d=0&r=60,5000.00,"))
check("slip bits 2 and 8 -> 10, aux 0", reqs[1][2]:find(",0,0,10,0%.000,0%.000$"))
check("busy: no second request before the reply", (function() for _ = 1, 60 do onTick() end return #reqs == 1 end)())

httpReply(8765, reqs[1][2], "1,0,20,0,1,0.1,0,0,0,0,0,0,0,0,0,0,0,0,0")
onTick()
check("reply starts the experiment", out[1] == 0.1)
httpReply(9999, "", "1,0,20,0,1,0.3,0,0,0,0,0,0,0,0,0,0,0,0,0")
check("other ports ignored", (function() onTick(); return out[1] == 0.1 end)())
httpReply(8765, "", "timeout")
check("error text ignored", (function() onTick(); return out[1] == 0.1 end)())

ch[16] = 0
onTick()
check("ready off aborts: motor 0, brake 1", out[1] == 0 and out[2] == 1)
-- after the abort: stop, release, then a two-segment reply runs both segments back to back
ch[16], ch[9] = 1, 0
onTick() -- the entry learns the speed on a tick
httpReply(8765, "", "2")
httpReply(8765, "", "1,0,10,0,1,0.1,0,0,0,0,0,0,0,0,0,0,0,0,0,10,0,1,0.2,0,0,0,0,0,0,0,0,0,0,0,0,0")
onTick(); local first = out[1]
for _ = 1, 10 do onTick() end
check("two-segment reply: first then second segment", first == 0.1 and out[1] == 0.2)
-- command 6 chooses the input channels recorded as aux1/aux2; command 8 cancels
ch[5], ch[7] = 1.5, 2.5
httpReply(8765, "", "6,5,7")
local n_before = #reqs
for _ = 1, 70 do onTick() end
check("aux channels are recorded", #reqs > n_before and reqs[#reqs][2]:find(",1%.500,2%.500", 1) ~= nil)
httpReply(8765, "", "1,0,100,0,1,0.1,0,0,0,0,0,0,0,0,0,0,0,0,0")
onTick()
httpReply(8765, "", "8")
onTick(); onTick()
check("command 8 cancels the program", out[1] == 0)

-- malformed replies must not raise, and the script keeps running
local bad = {"1", "4", "5,0", "5", "6", "3", "1,0", "1,5,1,2,3", "6,-3,99", "x,y", "", "5,2,500"}
local ok = pcall(function()
    for _, reply in ipairs(bad) do
        httpReply(8765, "", reply)
        for _ = 1, 100 do onTick() end
    end
end)
check("malformed replies do not raise", ok)
-- the HTTP port comes from ch24 (the microcontroller property)
ch[24] = 8766
onTick()
httpReply(8766, "", "0") -- a reply on the new port is accepted (it frees the request in flight)
local n0 = #reqs
for _ = 1, 200 do onTick() end
check("port from ch24", #reqs > n0 and reqs[#reqs][1] == 8766)
print(failed == 0 and "entry smoke ok" or (failed .. " failed"))
os.exit(failed == 0 and 0 or 1)
