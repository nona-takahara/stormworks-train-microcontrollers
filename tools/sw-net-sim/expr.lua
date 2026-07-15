-- Tiny expression evaluators for the two sw-net formula languages used by
-- FUNC_NUM_1/FUNC_NUM_3/FUNC_NUM_8 (numeric) and BOOL_FUNC_4/BOOL_FUNC_8
-- (boolean). Reference: node-behavior-notes.json entries for these gates
-- (storm-microcontroller-language 0.9.0), reproduced in
-- tools/sw-net-sim/README.md.
--
-- Each `expression` string is parsed once into an AST and cached by the
-- caller; evaluation takes a `vars` table (x/y/z/w/a/b/c/d, p1/p2/p3).

local M = {}

--------------------------------------------------------------------------
-- Shared tokenizer
--------------------------------------------------------------------------

local function tokenize(src)
    local tokens = {}
    local i, n = 1, #src
    while i <= n do
        local c = src:sub(i, i)
        if c:match("%s") then
            i = i + 1
        elseif c:match("[%d%.]") then
            local j = i
            while j <= n and src:sub(j, j):match("[%d%.eE%+%-]") do
                -- allow exponent sign only right after e/E
                local cj = src:sub(j, j)
                if (cj == "+" or cj == "-") then
                    local prev = src:sub(j - 1, j - 1)
                    if not (prev == "e" or prev == "E") then break end
                end
                j = j + 1
            end
            tokens[#tokens + 1] = { kind = "number", value = tonumber(src:sub(i, j - 1)) }
            i = j
        elseif c:match("[%a_]") then
            local j = i
            while j <= n and src:sub(j, j):match("[%w_]") do j = j + 1 end
            tokens[#tokens + 1] = { kind = "ident", value = src:sub(i, j - 1) }
            i = j
        elseif c == "," then
            tokens[#tokens + 1] = { kind = "," }
            i = i + 1
        elseif c == "(" or c == ")" then
            tokens[#tokens + 1] = { kind = c }
            i = i + 1
        elseif ("+-*/%^&|!"):find(c, 1, true) then
            tokens[#tokens + 1] = { kind = c }
            i = i + 1
        else
            error("sw-net expr: unexpected character '" .. c .. "' in: " .. src)
        end
    end
    return tokens
end

local function make_stream(tokens)
    local pos = 1
    local s = {}
    function s.peek() return tokens[pos] end
    function s.next()
        local t = tokens[pos]
        pos = pos + 1
        return t
    end
    function s.expect(kind)
        local t = s.next()
        if not t or t.kind ~= kind then
            error("sw-net expr: expected '" .. kind .. "', got " ..
                (t and (t.value or t.kind) or "<eof>"))
        end
        return t
    end
    function s.at_end() return tokens[pos] == nil end
    return s
end

--------------------------------------------------------------------------
-- Numeric expression grammar (FUNC_NUM_1/3/8)
--   expr  := term (('+'|'-') term)*
--   term  := unary (('*'|'/'|'%') unary)*
--   unary := '-' unary | power
--   power := atom ('^' unary)?
--   atom  := number | ident | ident '(' args ')' | '(' expr ')'
--------------------------------------------------------------------------

local NUM_FUNCS = {
    sin = function(a) return math.sin(a) end,
    cos = function(a) return math.cos(a) end,
    tan = function(a) return math.tan(a) end,
    asin = function(a) return math.asin(a) end,
    acos = function(a) return math.acos(a) end,
    atan = function(a) return math.atan(a) end,
    atan2 = function(a, b) return math.atan(a, b) end,
    max = function(...) return math.max(...) end,
    min = function(...) return math.min(...) end,
    ceil = function(a) return math.ceil(a) end,
    floor = function(a) return math.floor(a) end,
    round = function(a) return math.floor(a + 0.5) end,
    abs = function(a) return math.abs(a) end,
    sgn = function(a)
        if a > 0 then return 1 elseif a < 0 then return -1 else return 1 end
    end,
    sqrt = function(a) if a < 0 then return 0 end return math.sqrt(a) end,
    len = function(a) return math.abs(a) end,
    len2 = function(a, b) return math.sqrt(a * a + b * b) end,
    lerp = function(a, b, t) return a + (b - a) * t end,
    clamp = function(a, lo, hi) if a < lo then return lo elseif a > hi then return hi else return a end end,
}

local function parse_numeric(tokens)
    local s = make_stream(tokens)
    local parse_expr

    local function parse_args()
        local args = {}
        if s.peek() and s.peek().kind ~= ")" then
            args[#args + 1] = parse_expr()
            while s.peek() and s.peek().kind == "," do
                s.next()
                args[#args + 1] = parse_expr()
            end
        end
        s.expect(")")
        return args
    end

    local function parse_atom()
        local t = s.next()
        if not t then error("sw-net expr: unexpected end of numeric expression") end
        if t.kind == "number" then
            return { op = "const", value = t.value }
        elseif t.kind == "(" then
            local e = parse_expr()
            s.expect(")")
            return e
        elseif t.kind == "ident" then
            if s.peek() and s.peek().kind == "(" then
                s.next()
                local args = parse_args()
                if t.value == "pi" or t.value == "pi2" then
                    error("sw-net expr: '" .. t.value .. "' is a constant, not a function")
                end
                if not NUM_FUNCS[t.value] then
                    error("sw-net expr: unknown function '" .. t.value .. "'")
                end
                return { op = "call", name = t.value, args = args }
            end
            if t.value == "pi" then return { op = "const", value = math.pi } end
            if t.value == "pi2" then return { op = "const", value = math.pi * 2 } end
            return { op = "var", name = t.value }
        end
        error("sw-net expr: unexpected token in numeric expression: " .. tostring(t.kind))
    end

    local function parse_power()
        local base = parse_atom()
        if s.peek() and s.peek().kind == "^" then
            s.next()
            local exp = parse_unary_fwd()
            return { op = "^", a = base, b = exp }
        end
        return base
    end

    function parse_unary_fwd()
        if s.peek() and s.peek().kind == "-" then
            s.next()
            return { op = "neg", a = parse_unary_fwd() }
        end
        return parse_power()
    end

    local function parse_unary() return parse_unary_fwd() end

    local function parse_term()
        local node = parse_unary()
        while s.peek() and (s.peek().kind == "*" or s.peek().kind == "/" or s.peek().kind == "%") do
            local op = s.next().kind
            local rhs = parse_unary()
            node = { op = op, a = node, b = rhs }
        end
        return node
    end

    parse_expr = function()
        local node = parse_term()
        while s.peek() and (s.peek().kind == "+" or s.peek().kind == "-") do
            local op = s.next().kind
            local rhs = parse_term()
            node = { op = op, a = node, b = rhs }
        end
        return node
    end

    local ast = parse_expr()
    if not s.at_end() then
        error("sw-net expr: trailing tokens in numeric expression")
    end
    return ast
end

local function eval_numeric_ast(node, vars)
    local op = node.op
    if op == "const" then return node.value end
    if op == "var" then
        local v = vars[node.name]
        if v == nil then error("sw-net expr: unbound variable '" .. node.name .. "'") end
        return v
    end
    if op == "neg" then return -eval_numeric_ast(node.a, vars) end
    if op == "call" then
        local args = {}
        for i, a in ipairs(node.args) do args[i] = eval_numeric_ast(a, vars) end
        return NUM_FUNCS[node.name](table.unpack(args))
    end
    local a = eval_numeric_ast(node.a, vars)
    local b = eval_numeric_ast(node.b, vars)
    if op == "+" then return a + b end
    if op == "-" then return a - b end
    if op == "*" then return a * b end
    if op == "/" then if b == 0 then return 0 end return a / b end
    if op == "%" then if b == 0 then return 0 end return a % b end
    if op == "^" then return a ^ b end
    error("sw-net expr: unknown numeric op '" .. tostring(op) .. "'")
end

function M.parse_numeric(str)
    return parse_numeric(tokenize(str))
end

function M.eval_numeric(ast, vars)
    return eval_numeric_ast(ast, vars)
end

--------------------------------------------------------------------------
-- Boolean expression grammar (BOOL_FUNC_4/8)
--   expr    := xorexpr ('|' xorexpr)*
--   xorexpr := andexpr ('^' andexpr)*
--   andexpr := unary ('&' unary)*
--   unary   := '!' unary | postfix
--   postfix := atom '!'?          (postfix NOT, per node-behavior-notes.json)
--   atom    := 'true' | 'false' | ident | '(' expr ')'
--------------------------------------------------------------------------

local function parse_boolean(tokens)
    local s = make_stream(tokens)
    local parse_expr

    local function parse_atom()
        local t = s.next()
        if not t then error("sw-net expr: unexpected end of boolean expression") end
        if t.kind == "(" then
            local e = parse_expr()
            s.expect(")")
            return e
        elseif t.kind == "ident" then
            if t.value == "true" then return { op = "const", value = true } end
            if t.value == "false" then return { op = "const", value = false } end
            return { op = "var", name = t.value }
        end
        error("sw-net expr: unexpected token in boolean expression: " .. tostring(t.kind))
    end

    local function parse_unary()
        if s.peek() and s.peek().kind == "!" then
            s.next()
            return { op = "not", a = parse_unary() }
        end
        local node = parse_atom()
        while s.peek() and s.peek().kind == "!" do
            s.next()
            node = { op = "not", a = node }
        end
        return node
    end

    local function parse_and()
        local node = parse_unary()
        while s.peek() and s.peek().kind == "&" do
            s.next()
            node = { op = "&", a = node, b = parse_unary() }
        end
        return node
    end

    local function parse_xor()
        local node = parse_and()
        while s.peek() and s.peek().kind == "^" do
            s.next()
            node = { op = "^", a = node, b = parse_and() }
        end
        return node
    end

    parse_expr = function()
        local node = parse_xor()
        while s.peek() and s.peek().kind == "|" do
            s.next()
            node = { op = "|", a = node, b = parse_xor() }
        end
        return node
    end

    local ast = parse_expr()
    if not s.at_end() then
        error("sw-net expr: trailing tokens in boolean expression")
    end
    return ast
end

local function eval_boolean_ast(node, vars)
    local op = node.op
    if op == "const" then return node.value end
    if op == "var" then
        local v = vars[node.name]
        if v == nil then error("sw-net expr: unbound variable '" .. node.name .. "'") end
        return v
    end
    if op == "not" then return not eval_boolean_ast(node.a, vars) end
    local a = eval_boolean_ast(node.a, vars)
    local b = eval_boolean_ast(node.b, vars)
    if op == "&" then return a and b end
    if op == "|" then return a or b end
    if op == "^" then return a ~= b end
    error("sw-net expr: unknown boolean op '" .. tostring(op) .. "'")
end

function M.parse_boolean(str)
    return parse_boolean(tokenize(str))
end

function M.eval_boolean(ast, vars)
    return eval_boolean_ast(ast, vars)
end

return M
