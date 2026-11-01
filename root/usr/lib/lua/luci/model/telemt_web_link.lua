-- Native WEB link derivation per telemt/telemt 3.5.14 runtime.rs.
-- Returns nil instead of displaying a broken link for invalid inputs.
local M = {}
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local function b64url(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = alphabet:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        out[#out + 1] = alphabet:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        if b then out[#out + 1] = alphabet:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) end
        if c then out[#out + 1] = alphabet:sub(n % 64 + 1, n % 64 + 1) end
    end
    return table.concat(out)
end
local function pct(s)
    return (s:gsub("([^A-Za-z0-9_.~-])", function(x)
        return string.format("%%%02X", x:byte())
    end))
end
function M.format(host, path, secret, mode)
    host, path, secret = tostring(host or ""), tostring(path or ""), tostring(secret or "")
    if not host:match("^[A-Za-z0-9][A-Za-z0-9.%-]*[A-Za-z0-9]$") or not host:find(".", 1, true) then return nil end
    if #secret ~= 32 or not secret:match("^[a-fA-F0-9]+$") or (mode ~= "dd" and mode ~= "plain") then return nil end
    if path == "" then
        return "tg://webproxy?server=" .. host .. "&secret=" .. (mode == "dd" and "dd" or "") .. secret:lower()
    end
    if #path > 128 or not path:match("^[A-Za-z0-9][A-Za-z0-9_/-]*$") or path:find("//", 1, true) or path:match("/$") then return nil end
    for segment in path:gmatch("[^/]+") do
        if not segment:match("^[A-Za-z0-9][A-Za-z0-9_-]*$") then return nil end
    end
    local bytes = {}
    for i = 1, #secret, 2 do bytes[#bytes + 1] = string.char(tonumber(secret:sub(i, i + 1), 16)) end
    local marker = string.char(0x70) .. (mode == "dd" and string.char(0xdd) or "")
    return "tg://webproxy?server=" .. pct(host .. "/" .. path) .. "&secret=" .. b64url(marker .. table.concat(bytes))
end
return M
