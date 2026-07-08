-- Packs/unpacks several small integer (or boolean) fields into a single
-- 32-bit slot value. The 32-bit boundary is enforced by round-tripping
-- through string.pack("I4",...)/string.unpack("I4",...) so overflow behaves
-- like real 32-bit unsigned wraparound instead of silently growing past what
-- a single Stormworks "32-bit value" slot can represent.
--
-- A layout is an ordered list of { name = string, bits = 1..32 }.
-- layout[1] occupies the lowest bits.

local bitpack = {}

function bitpack.width(layout)
    local total = 0
    for _, field in ipairs(layout) do
        total = total + field.bits
    end
    return total
end

function bitpack.pack(layout, fields)
    local acc = 0
    local shift = 0
    for _, field in ipairs(layout) do
        local width = field.bits
        local max = (1 << width) - 1
        local raw = fields[field.name] or 0
        if type(raw) == "boolean" then
            raw = raw and 1 or 0
        end
        raw = math.floor(raw)
        if raw < 0 then raw = 0 end
        if raw > max then raw = max end
        acc = acc | (raw << shift)
        shift = shift + width
    end
    if shift > 32 then
        error("bitpack.pack: layout exceeds 32 bits (" .. shift .. ")")
    end
    return string.unpack("I4", string.pack("I4", acc))
end

function bitpack.unpack(layout, value)
    local acc = string.unpack("I4", string.pack("I4", math.floor(value or 0)))
    local fields = {}
    local shift = 0
    for _, field in ipairs(layout) do
        local width = field.bits
        local mask = (1 << width) - 1
        fields[field.name] = (acc >> shift) & mask
        shift = shift + width
    end
    return fields
end

-- Convenience: treat a 1-bit unpacked field as a boolean.
function bitpack.bool(intval)
    return intval ~= 0
end

return bitpack
