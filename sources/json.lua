local function byte1(x) return string.byte(x, 1) end

local char_A = byte1 'A'
local char_E = byte1 'E'
local char_F = byte1 'F'
local char_a = byte1 'a'
local char_b = byte1 'b'
local char_e = byte1 'e'
local char_f = byte1 'f'
local char_n = byte1 'n'
local char_r = byte1 'r'
local char_t = byte1 't'
local char_u = byte1 'u'
local char_0 = byte1 '0'
local char_9 = byte1 '9'
--- `-`
local char_minus = byte1 '-'
--- `+`
local char_plus = byte1 '+'
--- `,`
local char_comma = byte1 ','
--- `.`
local char_dot = byte1 '.'
--- `:`
local char_colon = byte1 ':'
--- `"`
local char_dq = byte1 '\"'
--- `\`
local char_bsl = byte1 '\\'
--- `[`
local char_lsb = byte1 '['
--- `]`
local char_rsb = byte1 ']'
--- `{`
local char_lcb = byte1 '{'
--- `}`
local char_rcb = byte1 '}'
--- ` `
local char_sp = byte1 ' '
--- `\b`
local char_bs = byte1 '\b'
--- `\f`
local char_ff = byte1 '\f'
--- `\n`
local char_nl = byte1 '\n'
--- `\r`
local char_cr = byte1 '\r'
--- `\t`
local char_tab = byte1 '\t'

---@class Parser
---@field public source string
---@field public length integer
---@field public position integer
---@field private _parseValue fun(): boolean, string
local Parser = {
    source = "source",
    length = "length",
    position = "position",
}
---@param source string
local function newParser(source)
    ---@type Parser
    local p = {
        source = source,
        length = #source,
        position = 1,
    }
    setmetatable(p, { __index = Parser })
    return p
end

---@param self Parser
---@param message string
local function errorMessage(self, message)
    return message..". position: "..tostring(self.position)..", source: \""..self.source.."\""
end

---@param self Parser
local function peekChar(self)
    if self.length < self.position then
        return false
    else
        return true, string.byte(self.source, self.position)
    end
end

---@param self Parser
local function skipWhiteSpaces(self)
    while true do
        local ok, c = peekChar(self)
        if ok and (c == char_sp or c == char_nl or c == char_cr or c == char_tab) then
            self.position = self.position + 1
        else
            return
        end
    end
end

---@param self Parser
---@param code integer
local function skipChar(self, code)
    local position = self.position
    if self.length < position then return false end
    if string.byte(self.source, position) ~= code then return false end
    self.position = position + 1
    return true
end

---@param self Parser
---@return boolean success
---@return integer|string charOrError
local function readChar(self)
    if self.length < self.position then return false, errorMessage(self, "requires /./") end
    return true, string.byte(self.source, self.position)
end

---@param self Parser
---@param template string
local function skipString(self, template)
    local length = self.length
    local position = self.position
    local source = self.source

    local l = #template
    if length < position + l - 1 then return false end

    for offset = 0, l - 1 do
        if string.byte(template, offset + 1) ~= string.byte(source, position + offset) then return false end
    end

    self.position = position + l
    return true
end

---@param code integer
local function hexToInt(code)
    if char_0 <= code and code <= char_9 then
        return true, code - char_0
    elseif char_a <= code and code <= char_f then
        return true, code - char_a
    elseif char_A <= code and code <= char_F then
        return true, code - char_F
    else
        return false, 0
    end
end

---@param self Parser
local function parseUnicodeEscape(self)
    local position = self.position
    if self.length < position + 3 then return false, errorMessage(self, "requires /[\\da-fA-F]{4}/") end

    local source = self.source

    local ok1, d1 = hexToInt(string.byte(source, position))
    local ok2, d2 = hexToInt(string.byte(source, position + 1))
    local ok3, d3 = hexToInt(string.byte(source, position + 2))
    local ok4, d4 = hexToInt(string.byte(source, position + 3))
    if ok1 and ok2 and ok3 and ok4 then
        self.position = position + 4
        return true, 4096 * d1 + 256 * d2 + 16 * d3 + d4
    else
        return false, errorMessage(self, "requires /[\\da-fA-F]{4}/")
    end
end

---@param self Parser
local function parseEscape(self)
    local ok, c = readChar(self)
    if ok then
        if c == char_b then return true, char_bs
        elseif c == char_f then return true, char_ff
        elseif c == char_n then return true, char_nl
        elseif c == char_r then return true, char_cr
        elseif c == char_t then return true, char_tab
        elseif c == char_u then return parseUnicodeEscape(self)
        else return true, c
        end
    else
        return false, errorMessage(self, "requires /[bfnrtu]|[\\da-fA-F]{4}/")
    end
end

---@param self Parser
local function parseStringLiteral(self)
    if skipString(self, "\"\"") then return true, "" end

    ---@type integer[]
    local buffer = {}

    if skipChar(self, char_dq) then
        while true do
            if skipChar(self, char_dq) then
                local chars = {}
                for i = 1, #buffer do chars[#chars+1] = string.char(buffer[i]) end
                return true, table.concat(chars)

            elseif skipChar(self, char_bsl) then
                local ok, c = parseEscape(self)
                if not ok then return ok, c end

                buffer[#buffer+1] = c
            else
                local ok, c = readChar(self)
                if not ok then return false, errorMessage(self, "requires /\"|./") end
                
                buffer[#buffer+1] = c
            end
        end
    else
        return false, errorMessage(self, "requires /\"/")
    end
end

local function skipDigits1(self)
    local ok, c = peekChar(self)
    if ok and (char_0 <= c and c <= char_9) then
        self.position = self.position + 1
        while true do
            ok, c = peekChar(self)
            if ok and (char_0 <= c and c <= char_9) then
                self.position = self.position + 1
            else
                return true
            end
        end
    else
        return false
    end
end

---@param self Parser
local function skipInteger(self)
    skipChar(self, char_minus)
    return skipDigits1(self)
end

---@param self Parser
local function skipFraction(self)
    if skipChar(self, char_dot) then
        return skipDigits1(self)
    else
        return true
    end
end

local function skipExponent(self)
    if skipChar(self, char_E) or skipChar(self, char_e) then
        local _ = skipChar(self, char_plus) or skipChar(self, char_minus)
        return skipDigits1(self)
    else
        return true
    end
end

---@param self Parser
local function parseNumber(self)
    local oldPosition = self.position
    if skipInteger(self) then
        local ok, _ = skipFraction(self)
        if ok then
            if skipExponent(self) then
                return true, tonumber(self.source.sub(oldPosition, self.position - 1))
            end
        end
    end
    self.position = oldPosition
    return false, errorMessage(self, "requires number literal")
end

---@param self Parser
---@param beginChar integer
---@param endChar integer
---@param parse fun(self: Parser, result: table): boolean, string
local function parseElements(self, beginChar, endChar, parse)
    local r = {}
    if skipChar(self, beginChar) then
        skipWhiteSpaces(self)

        if skipChar(self, endChar) then
            -- \[\s*\]
            return true, r
        else
            skipWhiteSpaces(self)
            local ok, error = parse(self, r)
            if ok then

                -- \[\s*@value
                while true do
                    skipWhiteSpaces(self)
                    if skipChar(self, char_comma) then
                        -- \[\s*@value(\s*,@value)*\s*,
                        skipWhiteSpaces(self)
                        ok, error = parse(self, r)
                        if ok then
                            -- \[\s*@value(\s*,@value)*\s*,@value
                        else
                            return false, r
                        end
                    else
                        if skipChar(self, endChar) then
                            -- \[\s*@value(\s*,@value)*\]
                            return true, r
                        else
                            return false, errorMessage(self, "unexpected token")
                        end
                    end
                end
            else
                return false, error
            end
        end
    else
        return false, errorMessage(self, "requires /\\"..string.char(beginChar).."/")
    end
end

---@param self Parser
---@param r table
local function parseItem(self, r)
    local ok, value = self:_parseValue()
    if ok then r[#r+1] = value end
    return ok, value
end

---@param self Parser
local function parseArray(self)
    return parseElements(self, char_lsb, char_rsb, parseItem)
end

---@param self Parser
---@param r table
local function parseKeyValue(self, r)
    local okK, key = parseStringLiteral(self)
    if okK then
        skipWhiteSpaces(self)
        if skipChar(self, char_colon) then
            local okV, value = self:_parseValue()
            if okV then
                r[key] = value
                return true, nil
            else
                return false, value
            end
        else
            return false, errorMessage(self, "requires /:/")
        end
    else
        return false, errorMessage(self, "requires string literal")
    end
end

---@param self Parser
local function parseObject(self)
    return parseElements(self, char_lcb, char_rcb, parseKeyValue)
end

function Parser:_parseValue()
    local ok, c = peekChar(self)
    if not ok then return false, errorMessage(self, "unexpected eos") end

    if c == char_n then
        if skipString(self, "null") then
            return true, nil
        elseif skipString(self, "nan") then
            return true, 0/0
        else
            return false, errorMessage(self, "expected token: /null|nan/")
        end

    elseif c == char_t then
        if skipString(self, "true") then
            return true, true
        else
            return false, errorMessage(self, "expected token: /true/")
        end

    elseif c == char_f then
        if skipString(self, "false") then
            return true, false
        else
            return false, errorMessage(self, "expected token: /false/")
        end

    elseif c == char_dq then
        return parseStringLiteral(self)

    elseif c == char_lsb then
        return parseArray(self)

    elseif c == char_lcb then
        return parseObject(self)

    elseif c == char_minus or (char_0 <= c and c <= char_9) then
        return parseNumber(self)
    else
        return false, errorMessage(self, "expected token: any json token, actual char: '"..string.char(c, 98, 99).."'")
    end
end

---@param source string
---@return boolean success
---@return any|string valueOrError
local function parse(source)
    local parser = newParser(source)

    skipWhiteSpaces(parser)
    local ok, value = parser:_parseValue()
    if ok then
        skipWhiteSpaces(parser)
        if parser.position <= parser.length
        then return false, errorMessage(parser, "requires eos.")
        else return true, value
        end
    else
        return false, value
    end
end

---@class StringifyOptions
---@field public space integer|string

---@param value any
---@param options StringifyOptions|nil
---@return string|nil json
---@return string|nil error
local function stringify(value, options)
    ---@type string|number
    local space = " "
    if options then space = options.space end
    if type(space) ~= "string" then space = string.rep(" ", tonumber(options.space)) end

    ---@type any[] buffer
    local b = {}
    local error = ""

    ---@param s string
    local function writeStringLiteral(s)
        if s == "" then
            b[#b+1] = "\"\""
            return
        end

        b[#b+1] = "\""
        for i = 1, #s do
            local c = string.sub(s, i, i)
            if c == "\"" or c == "\\" then b[#b+1] = "\\" end
            b[#b+1] = c
        end
        b[#b+1] = "\""
    end

    local function writeSpace()
        b[#b+1] = space
    end

    ---@param v any
    ---@return boolean success
    local function writeValue(v)
        if v == nil then b[#b + 1] = "null"
        elseif v == true then b[#b + 1] = "true"
        elseif v == false then b[#b + 1] = "false"
        elseif v == false then b[#b + 1] = "false"
        else
            local t = type(v)
            if t == "number" then
                -- TODO: NaN
                if v ~= v then b[#b+1] = "nan"
                elseif v == 1 / 0 then b[#b+1] = "1e+999999"
                elseif v == -1 / 0 then b[#b+1] = "-1e+999999"
                else b[#b+1] = v end

            elseif t == "string" then
                writeStringLiteral(v)

            elseif t == "table" then
                local length = #v

                -- array
                if 0 < length then
                    b[#b+1] = "["
                    writeSpace()

                    if not writeValue(v[1]) then return false end
                    for i = 2, length do
                        b[#b+1] = ","
                        writeSpace()
                        if not writeValue(v[i]) then return false end
                    end
                    writeSpace()
                    b[#b+1] = "]"

                -- table
                else
                    b[#b+1] = "{"
                    writeSpace()

                    local i = 1
                    for tk, tv in pairs(v) do
                        if 1 < i then
                            b[#b+1] = ","
                            writeSpace()
                        end
                        writeStringLiteral(tostring(tk))
                        b[#b+1] = ":"
                        writeSpace()
                        if not writeValue(tv) then return false end
                        i = i + 1
                    end
                    writeSpace()
                    b[#b+1] = "}"
                end
            else
                error = "invalid type: "..t..", value: "..tostring(v)
                return false
            end
        end
        return true
    end

    if writeValue(value) then
        local s = ""
        for i = 1, #b do s = s..tostring(b[i]) end
        return s, nil
    else
        return "", error
    end
end

return {
    stringify = stringify,
    parse = parse,
}
