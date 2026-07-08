-- Tests chuso1800_core's own inlined pack_bits/unpack_bits (exposed as
-- core.pack_bits/core.unpack_bits/core.bool for this purpose only -- see
-- the module header comment on why these are inlined rather than a
-- separate `require`d file: Stormworks has no module loader.

local core = require("chuso1800_core")

return function(h)
    local layout = {
        { name = "a", bits = 3 },  -- 0-7
        { name = "b", bits = 1 },  -- bool
        { name = "c", bits = 10 }, -- 0-1023
        { name = "d", bits = 1 },  -- bool
    }

    -- round trip of typical values
    local packed = core.pack_bits(layout, { a = 5, b = true, c = 600, d = false })
    local out = core.unpack_bits(layout, packed)
    h.assert_eq(out.a, 5, "field a")
    h.assert_eq(out.b, 1, "field b (bool packed as 1)")
    h.assert_eq(out.c, 600, "field c")
    h.assert_eq(out.d, 0, "field d")

    -- boundary values: 0 and max representable per field width
    local packed2 = core.pack_bits(layout, { a = 0, b = false, c = 0, d = true })
    local out2 = core.unpack_bits(layout, packed2)
    h.assert_eq(out2.a, 0, "boundary a=0")
    h.assert_eq(out2.c, 0, "boundary c=0")
    h.assert_eq(out2.d, 1, "boundary d=1")

    local packed3 = core.pack_bits(layout, { a = 7, b = true, c = 1023, d = true })
    local out3 = core.unpack_bits(layout, packed3)
    h.assert_eq(out3.a, 7, "max a")
    h.assert_eq(out3.c, 1023, "max c")

    -- over-width values are clamped at pack time, not wrapped
    local packed4 = core.pack_bits(layout, { a = 99, c = 99999 })
    local out4 = core.unpack_bits(layout, packed4)
    h.assert_eq(out4.a, 7, "over-width a clamps to max")
    h.assert_eq(out4.c, 1023, "over-width c clamps to max")

    -- negative values clamp to 0
    local packed5 = core.pack_bits(layout, { a = -5 })
    local out5 = core.unpack_bits(layout, packed5)
    h.assert_eq(out5.a, 0, "negative a clamps to 0")

    -- fields don't bleed into neighbors
    local packed6 = core.pack_bits(layout, { a = 7, b = false, c = 0, d = false })
    local out6 = core.unpack_bits(layout, packed6)
    h.assert_eq(out6.b, 0, "b unaffected by max a")
    h.assert_eq(out6.c, 0, "c unaffected by max a")

    -- bool() helper
    h.assert_true(core.bool(1), "bool(1)")
    h.assert_false(core.bool(0), "bool(0)")

    -- Real layouts used by calculateTick round-trip correctly too (a
    -- regression guard on the actual production layouts, not just a
    -- synthetic one).
    for _, layout_name in ipairs({
        "STATE_LATCHES_LAYOUT", "STATE_TIMERS_LAYOUT", "STATUS_BITS_LAYOUT",
    }) do
        local real_layout = core[layout_name]
        local fields = {}
        for _, field in ipairs(real_layout) do
            fields[field.name] = (1 << field.bits) - 1 -- max value for each field
        end
        local packed_real = core.pack_bits(real_layout, fields)
        local out_real = core.unpack_bits(real_layout, packed_real)
        for _, field in ipairs(real_layout) do
            h.assert_eq(out_real[field.name], (1 << field.bits) - 1,
                layout_name .. "." .. field.name .. " round-trips at max value")
        end
    end
end
