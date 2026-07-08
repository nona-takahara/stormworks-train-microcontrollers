-- Minimal assertion helpers for the scenario scripts. No external test
-- framework dependency -- just `lua test/run_all.lua`.

local harness = {}

function harness.assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("expected %s, got %s%s",
            tostring(expected), tostring(actual), msg and (" -- " .. msg) or ""), 2)
    end
end

function harness.assert_near(actual, expected, eps, msg)
    eps = eps or 1e-9
    if type(actual) ~= "number" or type(expected) ~= "number" or math.abs(actual - expected) > eps then
        error(string.format("expected ~%s (eps %s), got %s%s",
            tostring(expected), tostring(eps), tostring(actual), msg and (" -- " .. msg) or ""), 2)
    end
end

function harness.assert_true(cond, msg)
    if not cond then
        error("expected true" .. (msg and (" -- " .. msg) or ""), 2)
    end
end

function harness.assert_false(cond, msg)
    if cond then
        error("expected false" .. (msg and (" -- " .. msg) or ""), 2)
    end
end

return harness
