
--- `" "`
local char_sp = (" "):byte(1)
--- `"\t"`
local char_tab = ("\t"):byte(1)
--- `"\r"`
local char_cr = ("\r"):byte(1)
--- `"\n"`
local char_nl = ("\n"):byte(1)
--- `"'"`
local char_sq = ("'"):byte(1)
--- `'"'`
local char_dq = ('"'):byte(1)
--- `"\\"`
local char_bsr = ("\\"):byte(1)
--- `
local char_bq = ("`"):byte(1)
--- `"$"`
local char_dollar = ("$"):byte(1)

local function parseError(message, position, source)
    return message..", position "..tostring(position)..", source: '"..source.."'"
end

--- `[[ab 'cd ef' "gh ij"]] => {"ab", "cd ef", "gh ij"}`
---@param command string commands
---@return string[] tokens
---@return string|nil error
local function tokenize(command)
    local tokens = {}
    local position = 1
    local length = #command
    local byte = string.byte
    local sub = string.sub

    while true do

        -- 空白などを読み飛ばす
        while true do
            if length < position then break end
            local char = byte(command, position)
            if char ~= char_sp and char ~= char_tab and char ~= char_cr and char ~= char_nl then break end
            position = position + 1
        end

        if length < position then break end
        local char = byte(command, position)

        if char == char_sq or char == char_dq then
            -- 区切られた文字列の開始だった

            local quote = char
            position = position + 1

            -- 文字列の文字の開始位置を記録
            local tokenStart = position
            local tokenEnd = position

            -- 文字列の文字を読み飛ばす
            while true do
                if length < position then
                    -- コマンドが文字列の開始で終わっていたのでエラー
                    -- 例: `abc "`
                    return nil, parseError("requires '\"'", position, command)
                end

                local char = byte(command, position)

                -- 文字列の終わり
                if char == quote then tokenEnd = position break end

                -- 文字列内で特殊な意味を持つ文字
                if char == char_bsr or char == char_nl or char == char_bq or (quote == char_dq and char == char_dollar) then
                    return nil, parseError("invalid char '"..string.char(char).."'", position, command)
                end
                position = position + 1
            end

            -- トークンを切り出す
            tokens[#tokens+1] = sub(command, tokenStart, tokenEnd - 1)
            position = position + 1
        else
            local tokenStart = position
            local tokenEnd = position
            position = position + 1

            -- トークンを読み飛ばす
            while true do

                -- コマンドの終わり
                if length < position then
                    tokenEnd = position
                    break
                end

                -- 空白や文字列の開始なら終了
                local char = byte(command, position)
                if char == char_sp or char == char_tab or char == char_cr or char == char_nl then
                    tokenEnd = position
                    break
                end

                -- 特殊な意味を持つ文字
                if char == char_bsr or char == char_nl or char == char_bq or char == char_dollar then
                    return nil, parseError("invalid char '"..string.char(char).."'", position, command)
                end

                position = position + 1
            end

            -- トークンを切り出す
            tokens[#tokens+1] = sub(command, tokenStart, tokenEnd - 1)
            position = position + 1
        end
    end
    return tokens
end

local function parseNamedOption(arguments, key, shortKey, options, parseValue)
    if 0 == #arguments then return false end

    local arg = string.lower(arguments[1])
    if arg ~= "--"..key and arg ~= "-"..shortKey then return false end

    if #arguments < 2 then
        error("requires <"..key..">")
        return false
    end

    options[key] = parseValue(arguments[2])
    table.remove(arguments, 1)
    table.remove(arguments, 1)
    return true
end

return {
    parseNamedOption = parseNamedOption,
    splitCommand = tokenize,
}
