-- Generic sw-net gate-network tick simulator.
--
-- TICK MODEL (user decision, see chat log / DESIGN_LOG for this session):
-- every inter-node signal is delayed by exactly 1 tick, uniformly, with NO
-- same-tick propagation between nodes at all -- "freeze the previous tick's
-- outputs, and use this frozen snapshot as this tick's inputs". This matches
-- storm-microcontroller-language's own bundled, "verified"-confidence
-- execution-order note ("previous tick's output values are used as this
-- tick's inputs"), which contradicts CHUSO1800_Traction_Controller/SPEC.md's
-- "only stateful gates delay" assumption (itself flagged there as never
-- confirmed against real hardware). Building this simulator is exactly how
-- we test which model actually matches reality.
--
-- Practically: at the start of tick N we have `frozen`, a full snapshot of
-- every internal signal as computed at the end of tick N-1 (default 0/false
-- for signals that have never been produced yet, e.g. before tick 1). Every
-- node's evaluate() this tick reads its inputs purely from `frozen` (for
-- wires from other nodes) or from this tick's fresh external module inputs
-- (for wires from a module input port) -- never from another node's
-- just-computed current-tick output. Because of this there is no cycle to
-- break and no topological sort needed: nodes can be evaluated in any order.
--
-- Node-intrinsic memory (SR_LATCH's q, CAPACITOR's level, BLINKER's phase,
-- PULSE's/DELTA's last-seen input) is additional per-node state carried
-- alongside the frozen snapshot; see node-behavior-notes.json (bundled with
-- storm-microcontroller-language) for the behavior each of these is based
-- on, reproduced in tools/sw-net-sim/README.md.

local expr = require("expr")

local M = {}

--------------------------------------------------------------------------
-- Declared input/output signal kinds per gate type (from
-- storm-microcontroller-language 0.9.0's definitions.json `components`
-- table), used only to pick a sane default (0 / false / empty composite)
-- for a signal that has never been produced yet (i.e. during tick 1).
--------------------------------------------------------------------------

local PORT_KINDS = {
    AND = { inputs = { a = "boolean", b = "boolean" }, outputs = { out = "boolean" } },
    OR = { inputs = { a = "boolean", b = "boolean" }, outputs = { out = "boolean" } },
    NOR = { inputs = { a = "boolean", b = "boolean" }, outputs = { out = "boolean" } },
    XOR = { inputs = { a = "boolean", b = "boolean" }, outputs = { out = "boolean" } },
    NOT = { inputs = { a = "boolean" }, outputs = { out = "boolean" } },
    CONST = { inputs = {}, outputs = { value = "number" } },
    THRESHOLD = { inputs = { value = "number" }, outputs = { out = "boolean" } },
    GREATER_THAN = { inputs = { a = "number", b = "number" }, outputs = { out = "boolean" } },
    LESS_THAN = { inputs = { a = "number", b = "number" }, outputs = { out = "boolean" } },
    EQUAL = { inputs = { a = "number", b = "number" }, outputs = { out = "boolean" } },
    SUBTRACT = { inputs = { a = "number", b = "number" }, outputs = { out = "number" } },
    ABS = { inputs = { a = "number" }, outputs = { out = "number" } },
    DELTA = { inputs = { a = "number" }, outputs = { out = "number" } },
    FUNC_NUM_1 = { inputs = { x = "number" }, outputs = { out = "number" } },
    FUNC_NUM_3 = { inputs = { x = "number", y = "number", z = "number" }, outputs = { out = "number" } },
    BOOL_FUNC_4 = { inputs = { x = "boolean", y = "boolean", z = "boolean", w = "boolean" }, outputs = { out = "boolean" } },
    BOOL_FUNC_8 = {
        inputs = { x = "boolean", y = "boolean", z = "boolean", w = "boolean", a = "boolean", b = "boolean", c = "boolean", d = "boolean" },
        outputs = { out = "boolean" },
    },
    NUM_SWITCHBOX = { inputs = { a = "number", b = "number", switch = "boolean" }, outputs = { out = "number" } },
    COMPOSITE_SWITCHBOX = { inputs = { a = "composite", b = "composite", switch = "boolean" }, outputs = { out = "composite" } },
    SR_LATCH = { inputs = { s = "boolean", r = "boolean" }, outputs = { q = "boolean", not_q = "boolean" } },
    CAPACITOR = { inputs = { enable = "boolean" }, outputs = { out = "boolean" } },
    BLINKER = { inputs = { enable = "boolean" }, outputs = { out = "boolean" } },
    PULSE = { inputs = { a = "boolean" }, outputs = { out = "boolean" } },
    PROPERTY_TOGGLE = { inputs = {}, outputs = { out = "boolean" } },
    PROPERTY_NUMBER = { inputs = {}, outputs = { out = "number" } },
    PROPERTY_DROPDOWN = { inputs = {}, outputs = { out = "number" } },
    COMPOSITE_READ_NUMBER = { inputs = { composite = "composite" }, outputs = { out = "number" } },
    COMPOSITE_READ_BOOLEAN = { inputs = { composite = "composite" }, outputs = { out = "boolean" } },
    COMPOSITE_WRITE_NUMBER = {
        inputs = { inc = "composite" }, outputs = { out = "composite" },
        dynamic_count = true, dynamic_kind = "number",
    },
    COMPOSITE_WRITE_BOOLEAN = {
        inputs = { inc = "composite" }, outputs = { out = "composite" },
        dynamic_count = true, dynamic_kind = "boolean",
    },
    LUA = { inputs = { composite = "composite" }, outputs = { composite = "composite" } },
}
M.PORT_KINDS = PORT_KINDS

local function default_for_kind(kind)
    if kind == "boolean" then return false end
    if kind == "composite" then return { n = {}, b = {} } end
    return 0
end

--------------------------------------------------------------------------
-- Composite helpers (a composite bundles up to 32 number + 32 boolean
-- channels, 1-origin channel numbers per storm-mcl's
-- composite-signal-layout note)
--------------------------------------------------------------------------

local function composite_get_number(c, ch)
    if not c or c.n[ch] == nil then return 0 end
    return c.n[ch]
end

local function composite_get_bool(c, ch)
    if not c or c.b[ch] == nil then return false end
    return c.b[ch]
end

local function composite_write(inc, offset, count, values, is_bool)
    local out = { n = {}, b = {} }
    if inc then
        for k, v in pairs(inc.n) do out.n[k] = v end
        for k, v in pairs(inc.b) do out.b[k] = v end
    end
    local bucket = is_bool and out.b or out.n
    for i = 1, count do
        bucket[offset + i - 1] = values[i]
    end
    return out
end
M.composite_get_number = composite_get_number
M.composite_get_bool = composite_get_bool

--------------------------------------------------------------------------
-- Stateful node initializers / evaluators
--------------------------------------------------------------------------

local function init_state(node)
    local t = node.type
    if t == "SR_LATCH" then return { q = false } end
    if t == "CAPACITOR" then return { level = 0, active = false } end
    if t == "BLINKER" then return { phase = "off", counter = 0 } end
    if t == "PULSE" then return { lastA = false } end
    if t == "DELTA" then return { lastA = 0 } end
    return {}
end

local function eval_sr_latch(s, r, state)
    if s and r then
        state.q = false
        return false, false
    elseif s then
        state.q = true
    elseif r then
        state.q = false
    end
    return state.q, not state.q
end

local function eval_capacitor(node, enable, state)
    if not node._cap then
        local ct = node.attrs.charge_time or 1
        local dt = node.attrs.discharge_time or 1
        node._cap = {
            chargeTicks = math.max(math.floor(ct * 60 + 0.5), 1),
            dischargeTicks = math.max(math.floor(dt * 60 + 0.5), 0),
        }
    end
    local chargeTicks, dischargeTicks = node._cap.chargeTicks, node._cap.dischargeTicks
    if dischargeTicks <= 0 then
        -- discharge is instantaneous; charging is a plain 0..chargeTicks counter
        if enable then
            state.level = math.min(state.level + 1, chargeTicks)
            if state.level >= chargeTicks then state.active = true end
        else
            state.level = 0
            state.active = false
        end
    else
        local levelMax = chargeTicks * dischargeTicks
        if enable then
            state.level = math.min(state.level + dischargeTicks, levelMax)
            if state.level >= levelMax then state.active = true end
        else
            state.level = math.max(state.level - chargeTicks, 0)
            if state.level <= 0 then state.active = false end
        end
    end
    return state.active
end

local function eval_blinker(node, enable, state)
    if not node._blink then
        -- on_time/off_time are quantized to 0.1s steps == 6 ticks @ 60Hz
        -- (node-behavior-notes.json, confidence: verified)
        local onT = node.attrs.on_time or 0.5
        local offT = node.attrs.off_time or 0.5
        node._blink = {
            onTicks = math.max(math.floor((onT / 0.1) + 0.5) * 6, 1),
            offTicks = math.max(math.floor((offT / 0.1) + 0.5) * 6, 1),
        }
    end
    if not enable then
        state.phase = "off"
        state.counter = 0
        return false
    end
    state.counter = state.counter + 1
    if state.phase == "off" then
        if state.counter >= node._blink.offTicks then
            state.phase = "on"
            state.counter = 0
        end
    else
        if state.counter >= node._blink.onTicks then
            state.phase = "off"
            state.counter = 0
        end
    end
    return state.phase == "on"
end

local function eval_pulse(node, a, state)
    local mode = node.attrs.mode or "rise"
    local out = false
    if mode == "rise" then
        out = (not state.lastA) and a
    elseif mode == "fall" then
        out = state.lastA and (not a)
    elseif mode == "both" then
        out = (a ~= state.lastA)
    else
        error("sw-net-sim: unknown PULSE mode '" .. tostring(mode) .. "'")
    end
    state.lastA = a
    return out
end

--------------------------------------------------------------------------
-- Per-type combinational + stateful evaluators.
-- Signature: fn(node, ins, state) -> outs (table keyed by output port key)
--------------------------------------------------------------------------

local EVAL = {}

EVAL.AND = function(node, ins) return { out = ins.a and ins.b } end
EVAL.OR = function(node, ins) return { out = ins.a or ins.b } end
EVAL.NOR = function(node, ins) return { out = not (ins.a or ins.b) } end
EVAL.XOR = function(node, ins) return { out = (ins.a ~= ins.b) } end
EVAL.NOT = function(node, ins) return { out = not ins.a } end

EVAL.CONST = function(node) return { value = node.attrs.value or 0 } end
EVAL.PROPERTY_NUMBER = function(node) return { out = node.attrs.value or 0 } end
EVAL.PROPERTY_TOGGLE = function(node)
    local v = node.attrs.v
    if v == nil then v = false end
    return { out = v }
end
EVAL.PROPERTY_DROPDOWN = function(node) return { out = node.attrs.value or 0 } end

EVAL.THRESHOLD = function(node, ins)
    local min, max = node.attrs.min, node.attrs.max
    return { out = (ins.value >= min) and (ins.value <= max) }
end
EVAL.GREATER_THAN = function(node, ins) return { out = ins.a > ins.b } end
EVAL.LESS_THAN = function(node, ins) return { out = ins.a < ins.b } end
EVAL.EQUAL = function(node, ins)
    local eps = node.attrs.epsilon or 0.0001
    return { out = math.abs(ins.a - ins.b) <= eps }
end
EVAL.SUBTRACT = function(node, ins) return { out = ins.a - ins.b } end
EVAL.ABS = function(node, ins) return { out = math.abs(ins.a) } end

EVAL.DELTA = function(node, ins, state)
    local out = ins.a - state.lastA
    state.lastA = ins.a
    return { out = out }
end

local function func_num_vars(node, ins)
    return {
        x = ins.x, y = ins.y, z = ins.z,
        p1 = node.attrs.p1 or 0, p2 = node.attrs.p2 or 0, p3 = node.attrs.p3 or 0,
    }
end
EVAL.FUNC_NUM_1 = function(node, ins)
    node._ast = node._ast or expr.parse_numeric(node.attrs.expression or "x")
    return { out = expr.eval_numeric(node._ast, func_num_vars(node, ins)) }
end
EVAL.FUNC_NUM_3 = EVAL.FUNC_NUM_1

local function bool_func_vars(ins)
    return { x = ins.x, y = ins.y, z = ins.z, w = ins.w, a = ins.a, b = ins.b, c = ins.c, d = ins.d }
end
EVAL.BOOL_FUNC_4 = function(node, ins)
    node._ast = node._ast or expr.parse_boolean(node.attrs.expression or "x")
    return { out = expr.eval_boolean(node._ast, bool_func_vars(ins)) }
end
EVAL.BOOL_FUNC_8 = EVAL.BOOL_FUNC_4

-- SPEC.md §2: "NUM_SWITCHBOX は switch=true で入力a、falseで入力bを選ぶ"
EVAL.NUM_SWITCHBOX = function(node, ins) return { out = ins.switch and ins.a or ins.b } end
EVAL.COMPOSITE_SWITCHBOX = function(node, ins) return { out = ins.switch and ins.a or ins.b } end

EVAL.SR_LATCH = function(node, ins, state)
    local q, not_q = eval_sr_latch(ins.s, ins.r, state)
    return { q = q, not_q = not_q }
end
EVAL.CAPACITOR = function(node, ins, state) return { out = eval_capacitor(node, ins.enable, state) } end
EVAL.BLINKER = function(node, ins, state) return { out = eval_blinker(node, ins.enable, state) } end
EVAL.PULSE = function(node, ins, state) return { out = eval_pulse(node, ins.a, state) } end

EVAL.COMPOSITE_READ_NUMBER = function(node, ins)
    local ch = node.attrs.channel or 1
    return { out = composite_get_number(ins.composite, ch) }
end
EVAL.COMPOSITE_READ_BOOLEAN = function(node, ins)
    local ch = node.attrs.channel or 1
    return { out = composite_get_bool(ins.composite, ch) }
end
EVAL.COMPOSITE_WRITE_NUMBER = function(node, ins)
    local count, offset = node.attrs.count or 1, node.attrs.offset or 1
    local values = {}
    for i = 1, count do values[i] = ins["in" .. i] or 0 end
    return { out = composite_write(ins.inc, offset, count, values, false) }
end
EVAL.COMPOSITE_WRITE_BOOLEAN = function(node, ins)
    local count, offset = node.attrs.count or 1, node.attrs.offset or 1
    local values = {}
    for i = 1, count do values[i] = ins["in" .. i] or false end
    return { out = composite_write(ins.inc, offset, count, values, true) }
end

EVAL.LUA = function(node, ins, state, bridge)
    if not bridge then
        error("sw-net-sim: no lua bridge registered for LUA node '" .. node.id .. "'")
    end
    return { composite = bridge(ins.composite) }
end

--------------------------------------------------------------------------
-- Simulator
--------------------------------------------------------------------------

local Sim = {}
Sim.__index = Sim

-- graph: result of dofile()-ing a tools/sw-net-sim/build.mjs output file.
-- opts.lua_bridges: optional { [nodeId] = function(compositeIn) -> compositeOut }
function M.new(graph, opts)
    opts = opts or {}
    local self = setmetatable({}, Sim)
    self.graph = graph
    self.lua_bridges = opts.lua_bridges or {}
    self.frozen = {}
    self.node_state = {}
    self.port_by_name = {}
    for _, p in ipairs(graph.ports) do self.port_by_name[p.name] = p end
    for _, n in ipairs(graph.nodes) do
        self.node_state[n.id] = init_state(n)
        local kinds = PORT_KINDS[n.type]
        if not kinds then
            error("sw-net-sim: unsupported gate type '" .. n.type .. "' (node '" .. n.id .. "')")
        end
        for portKey in pairs(n.inputs) do
            local is_dynamic = kinds.dynamic_count and portKey:match("^in%d+$")
            if not kinds.inputs[portKey] and not is_dynamic then
                error("sw-net-sim: node '" .. n.id .. "' (" .. n.type ..
                    ") wires unknown input port '" .. portKey .. "'")
            end
        end
    end
    self.tick_count = 0
    return self
end

-- Resolves one input descriptor ({sig=...}|{port=...}|{lit=...}) to a value
-- for this tick, given the declared kind of the *consuming* input port
-- (used only as a default for a signal that has never been produced yet).
function Sim:_resolve(descr, kind, module_inputs)
    if descr == nil then return default_for_kind(kind) end
    if descr.sig ~= nil then
        local v = self.frozen[descr.sig]
        if v == nil then return default_for_kind(kind) end
        return v
    end
    if descr.port ~= nil then
        local v = module_inputs[descr.port]
        if v == nil then
            error("sw-net-sim: missing external input for port '" .. descr.port .. "'")
        end
        return v
    end
    if descr.lit ~= nil then return descr.lit end
    return default_for_kind(kind)
end

-- module_inputs: table { [portName] = value } for every declared "in" port.
-- Returns module_outputs: table { [portName] = value } for every "out" port.
function Sim:step(module_inputs)
    self.tick_count = self.tick_count + 1
    local new_frozen = {}
    local module_outputs = {}

    for _, node in ipairs(self.graph.nodes) do
        local kinds = PORT_KINDS[node.type]
        local ins = {}
        -- Iterate over the gate type's *declared* input ports (not just the
        -- ones this instance happens to wire) so an unconnected input still
        -- gets its proper 0/false default instead of staying Lua `nil`.
        for portKey, kind in pairs(kinds.inputs) do
            ins[portKey] = self:_resolve(node.inputs[portKey], kind, module_inputs)
        end
        if kinds.dynamic_count then
            for i = 1, (node.attrs.count or 0) do
                local key = "in" .. i
                ins[key] = self:_resolve(node.inputs[key], kinds.dynamic_kind, module_inputs)
            end
        end
        local state = self.node_state[node.id]
        local outs
        if node.type == "LUA" then
            outs = EVAL.LUA(node, ins, state, self.lua_bridges[node.id])
        else
            outs = EVAL[node.type](node, ins, state)
        end
        for portKey, descr in pairs(node.outputs) do
            local v = outs[portKey]
            if descr.sig ~= nil then
                new_frozen[descr.sig] = v
            elseif descr.port ~= nil then
                module_outputs[descr.port] = v
                new_frozen[descr.port] = v
            end
        end
    end

    self.frozen = new_frozen
    for _, p in ipairs(self.graph.ports) do
        if p.direction == "out" and module_outputs[p.name] == nil then
            module_outputs[p.name] = default_for_kind(p.signal)
        end
    end
    return module_outputs
end

-- Debug helper: read an internal (non-port) signal's current frozen value.
function Sim:signal(name) return self.frozen[name] end

function M.empty_composite() return { n = {}, b = {} } end

return M
