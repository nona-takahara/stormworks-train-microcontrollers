-- Vehicle probe core (pure logic; no Stormworks API).
--
-- Not a module: public functions are plain globals (LUA_CODING_GUIDE.md), so
-- the deploy build (dofile inlining) and plain `lua` tests see the same names.
-- Site knowledge lives outside: SITE_LO / SITE_HI (track limits [m], x axis)
-- must be defined as globals before probe_tick runs. While either is nil the
-- probe never leaves IDLE. SITE_DIR (+1/-1, optional) is the sign of the x change per
-- +motor; probe_dir overrides it.
--
-- States: 0 IDLE, 1 RUN, 2 ABORT (JOG is a mode of IDLE), 3 FALLEN.
-- ABORT reasons: 1 ready off, 2 outside area, 3 over speed. ABORT is released
-- by probe_ack once stopped.
-- FALLEN (reason 4: y dropped) means the vehicle cannot continue. It is
-- terminal: nothing releases it, and set/ack/jog are ignored. Only a person
-- can recover the vehicle.
-- "v" in every formula and check means |speed| [m/s]; tau is seconds since the segment started.

local VMAX = 55.56  -- 200 km/h
local VREC = 5      -- speed cap while JOG [m/s]
local DECEL = 3     -- assumed braking [m/s^2] for the abort distance. unconfirmed
local MIN_MARGIN = 200
local V_STOPPED = 0.1
local LIMIT = 1e6  -- output bound: only keeps the Lua node from overflowing. Saturation is left to the vehicle
local FALL = 1  -- y drop in one tick [m] taken as leaving the track. inferred

local st, reason, t = 0, 0, 0
local py = nil
local dir = 0                -- +1/-1: sign of x change per +motor. 0 = unknown
local armed, t_start = false, 0
local segs, si = {}, 0   -- program: segments run back to back; si = the running one
local t_end, ts, ve, vmin, mf, bf = 0, 0, 0, 1, {0, 0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0, 0, 0}
local jm, jb, jt = 0, 0, 0

-- NaN (0/0) would clamp to the upper bound; it becomes 0 instead
local function clamp(a, lo, hi)
    if a ~= a then return 0 end
    return math.max(lo, math.min(hi, a))
end

local function n(x) return x or 0 end -- a short or malformed command must not crash the script

-- c0 + c1*v + c2*v^2 + ci/max(v,vmin) + ct*tau + A*sin(2*pi*f*tau)
local function shape(f, v, tau)
    return f[1] + f[2] * v + f[3] * v * v + f[4] / math.max(v, vmin) + f[5] * tau
        + f[6] * math.sin(6.2831853 * f[7] * tau)
end

-- distance from each track limit at which the probe aborts [m]
function probe_margin(v)
    return math.max(MIN_MARGIN, v * v / (2 * DECEL))
end

local function in_area(x, v)
    local d = probe_margin(v)
    return SITE_LO ~= nil and SITE_HI ~= nil and x >= SITE_LO + d and x <= SITE_HI - d
end

-- Arms a program that starts `delay` ticks from now (ignored while a program is
-- running). The program is one or more segments run back to back, 17 numbers each:
--   len [tick] (the longest the segment lasts), vend [m/s], vmin [m/s],
--   motor c0 c1 c2 ci ct A f, brake c0 c1 c2 ci ct A f
-- vend > 0 ends the segment early once |v| >= vend, vend < 0 once |v| <= -vend, 0 never.
function probe_set(delay, ...)
    if st == 1 then return end -- not while running: the segment index and end time would go stale
    local a = {...}
    segs = {}
    for i = 1, #a, 17 do
        local g = {n(a[i]), n(a[i + 1]), n(a[i + 2]), {}, {}}
        for k = 0, 6 do g[4][k + 1], g[5][k + 1] = n(a[i + 3 + k]), n(a[i + 10 + k]) end
        segs[#segs + 1] = g
    end
    armed, t_start = true, t + n(delay)
end

-- segment i starts at tick `from`
local function load(i, from)
    local g = segs[i]
    si, ts, t_end, ve, vmin, mf, bf = i, from, from + g[1], g[2], math.max(g[3], 1e-3), g[4], g[5]
end

-- Cancels an armed or running program; outputs return to 0 from the next tick.
function probe_cancel()
    armed = false
    if st == 1 then st = 0 end
end

function probe_dir(d) dir = n(d) end

-- Accepted only while stopped; otherwise the brake would be released in motion.
function probe_ack(v)
    if st == 2 and math.abs(v or 1) < V_STOPPED then st, reason = 0, 0 end
end

-- Drive back toward the area. IDLE and outside the area only.
function probe_jog(motor, brake, len)
    jm, jb, jt = n(motor), n(brake), n(len)
end

-- returns motor, brake, state, reason (RUN: the running segment number), t
function probe_tick(x, y, v, ready)
    v = math.abs(v)
    t = t + 1
    local motor, brake = 0, 0
    if py and py - y > FALL then st, reason, armed = 3, 4, false end
    py = y
    if st == 0 and armed and t >= t_start then
        armed = false
        if ready ~= 0 and in_area(x, v) and #segs > 0 then st = 1; load(1, t) end
    end
    -- Not running and outside the area while fast (a program that ended at speed, a cancelled
    -- program, a reloaded script): the vehicle is coasting unprotected, so brake.
    if st == 0 and SITE_LO ~= nil and SITE_HI ~= nil and (v > VMAX or (v > 2 * VREC and not in_area(x, v))) then
        st, reason, armed = 2, v > VMAX and 3 or 2, false
    end
    if st == 1 then
        local r = (ready == 0 and 1) or (not in_area(x, v) and 2) or (v > VMAX and 3) or 0
        if r > 0 then
            st, reason, armed = 2, r, false
        else
            -- move past finished segments: out of time (the next one continues from
            -- that tick) or the speed condition met (the next one starts now)
            while st == 1 and (t >= t_end or (ve > 0 and v >= ve) or (ve < 0 and v <= -ve)) do
                if segs[si + 1] then load(si + 1, t >= t_end and t_end or t) else st = 0 end
            end
            if st == 1 then
                local tau = (t - ts) / 60
                motor = clamp(shape(mf, v, tau), -LIMIT, LIMIT)
                brake = clamp(shape(bf, v, tau), -LIMIT, LIMIT)
            end
        end
    elseif st == 0 and jt > 0 then
        local d = dir ~= 0 and dir or n(SITE_DIR)
        if SITE_LO ~= nil and SITE_HI ~= nil and d ~= 0 and not in_area(x, v) then
            -- JOG: only the toward-area direction of the motor passes
            local want = (x < SITE_LO + probe_margin(v) and 1 or -1) * d
            if jm * want > 0 and v <= VREC then motor = clamp(jm, -LIMIT, LIMIT) end
            brake = clamp(jb, -LIMIT, LIMIT)
            jt = jt - 1
        else
            jt = 0
        end
    end
    if st >= 2 then motor, brake = 0, 1 end
    return motor, brake, st, st == 1 and si or reason, t
end
