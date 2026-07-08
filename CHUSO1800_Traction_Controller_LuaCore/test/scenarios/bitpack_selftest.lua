local bitpack = require("bitpack")

return function(h)
    local layout = {
        { name = "a", bits = 3 },  -- 0-7
        { name = "b", bits = 1 },  -- bool
        { name = "c", bits = 10 }, -- 0-1023
        { name = "d", bits = 1 },  -- bool
    }

    -- round trip of typical values
    local packed = bitpack.pack(layout, { a = 5, b = true, c = 600, d = false })
    local out = bitpack.unpack(layout, packed)
    h.assert_eq(out.a, 5, "field a")
    h.assert_eq(out.b, 1, "field b (bool packed as 1)")
    h.assert_eq(out.c, 600, "field c")
    h.assert_eq(out.d, 0, "field d")

    -- boundary values: 0 and max representable per field width
    local packed2 = bitpack.pack(layout, { a = 0, b = false, c = 0, d = true })
    local out2 = bitpack.unpack(layout, packed2)
    h.assert_eq(out2.a, 0, "boundary a=0")
    h.assert_eq(out2.c, 0, "boundary c=0")
    h.assert_eq(out2.d, 1, "boundary d=1")

    local packed3 = bitpack.pack(layout, { a = 7, b = true, c = 1023, d = true })
    local out3 = bitpack.unpack(layout, packed3)
    h.assert_eq(out3.a, 7, "max a")
    h.assert_eq(out3.c, 1023, "max c")

    -- over-width values are clamped at pack time, not wrapped
    local packed4 = bitpack.pack(layout, { a = 99, c = 99999 })
    local out4 = bitpack.unpack(layout, packed4)
    h.assert_eq(out4.a, 7, "over-width a clamps to max")
    h.assert_eq(out4.c, 1023, "over-width c clamps to max")

    -- negative values clamp to 0
    local packed5 = bitpack.pack(layout, { a = -5 })
    local out5 = bitpack.unpack(layout, packed5)
    h.assert_eq(out5.a, 0, "negative a clamps to 0")

    -- fields don't bleed into neighbors
    local packed6 = bitpack.pack(layout, { a = 7, b = false, c = 0, d = false })
    local out6 = bitpack.unpack(layout, packed6)
    h.assert_eq(out6.b, 0, "b unaffected by max a")
    h.assert_eq(out6.c, 0, "c unaffected by max a")

    -- width() sums correctly and stays within 32 bits
    h.assert_eq(bitpack.width(layout), 15, "layout width")

    -- bool() helper
    h.assert_true(bitpack.bool(1), "bool(1)")
    h.assert_false(bitpack.bool(0), "bool(0)")
end
