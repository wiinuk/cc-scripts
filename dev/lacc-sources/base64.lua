
local u6ToCharTable = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local char_A = string.byte("A", 1)
local char_Z = string.byte("Z", 1)
local char_a = string.byte("a", 1)
local char_z = string.byte("z", 1)
local char_0 = string.byte("0", 1)
local char_9 = string.byte("9", 1)
--- `/`
local char_slash = string.byte("/", 1)
--- `+`
local char_plus = string.byte("+", 1)
--- `=`
local char_eq = string.byte("=", 1)

local function bor(x, y) return x + y end
local function bsr(x, y) return math.floor(x / (2 ^ y)) end
local function bsl(x, y) return x * (2 ^ y) end

---@param source string
local function encode(source)
    local length = #source
    local resultLength = math.floor(length * 8 / 6)

    local equalsCount = 0
    if 0 < length * 8 % 6 then
        resultLength = resultLength + 1
        equalsCount = 4 - resultLength % 4
        resultLength = resultLength + equalsCount
    end

    local buffer = {}
    local position = 1
    local bufferPosition = 1
    while position <= length do
        local nextU6 = 0
        local nextIndex = 0
        while nextIndex < 3 and position <= length do
            local offset = (nextIndex + 1) * 2
            local b = bor(nextU6, bsr(string.byte(source, position), offset)) % 64
            buffer[bufferPosition] = string.byte(u6ToCharTable, b + 1)
            nextU6 = bsl(string.byte(source, position), 6 - offset) % 64
            bufferPosition = bufferPosition + 1
            nextIndex = nextIndex + 1
            position = position + 1
        end

        buffer[bufferPosition] = string.byte(u6ToCharTable, nextU6 + 1)
        bufferPosition = bufferPosition + 1
    end

    if 0 < equalsCount then
        for i = resultLength - equalsCount + 1, resultLength do
            buffer[i] = char_eq
        end
    end

    return string.char(unpack(buffer))
end


---@class BitWriter
---@field buffer integer[]
---@field bitPosition integer 0..7

---@param writer BitWriter
---@param u6 integer
local function addU6(writer, u6)
    local b = writer.buffer
    local p = writer.bitPosition
    if p == 0 then b[#b+1] = 0 end

    local l = #b
    if 3 <= p then
        b[l] = bor(b[l], bsr(u6, p - 2))
        b[l+1] = bsl(u6, 10 - p) % 256
    else
        b[l] = bor(b[l], bsl(u6, 2 - p))
    end

    writer.bitPosition = (p + 6) % 8
end

---@param w BitWriter
---@param source string
local function write(w, source)
    for i = 1, #source do
        local c = string.byte(source, i)
        if char_A <= c and c <= char_Z then addU6(w, c - char_A)
        elseif char_a <= c and c <= char_z then addU6(w, c - char_a + 26)
        elseif char_0 <= c and c <= char_9 then addU6(w, c - char_0 + 52)
        elseif char_plus == c then addU6(w, 62)
        elseif char_slash == c then addU6(w, 63)
        elseif char_eq == c then return true
        else
            local ok, result = pcall(string.char, c)
            if ok
            then result = "'"..result.."'"
            else result = "code("..tostring(c)..")"
            end
            return false, "invalid base64 char: "..result.." @"..tostring(i)
        end
    end
    return true
end

---@param source string
---@return string|nil bytes
---@return string error
local function decode(source)
    ---@type BitWriter
    local w = {
        buffer = {},
        bitPosition = 0,
    }
    local ok, reason = write(w, source)
    if not ok then return nil, reason end

    if w.bitPosition ~= 0 then table.remove(w.buffer, #w.buffer) end
    return string.char(unpack(w.buffer))
end

return {
    encode = encode,
    decode = decode,
}