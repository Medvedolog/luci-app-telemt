-- LuCI CBI injects Map/Value/etc. into the environment of the model file.
-- Loading CBI fragments with require() loses that environment under ucodebridge
-- (notably OpenWrt 24.10), so execute every fragment in this model's CBI env.

local cbi_env = _ENV
if setfenv and getfenv then
    cbi_env = getfenv(1)
end

local function load_cbi_fragment(path)
    local chunk, err
    if setfenv then
        chunk, err = loadfile(path)
        if not chunk then error(err) end
        setfenv(chunk, cbi_env)
    else
        chunk, err = loadfile(path, "t", cbi_env)
        if not chunk then error(err) end
    end
    return chunk()
end

local legacy = load_cbi_fragment("/usr/lib/lua/luci/model/cbi/telemt_legacy.lua")
local memory_budget = load_cbi_fragment("/usr/lib/lua/luci/model/cbi/telemt_memory_budget.lua")
local web_users = load_cbi_fragment("/usr/lib/lua/luci/model/cbi/telemt_users_web.lua")

legacy = memory_budget.attach(legacy)
return web_users.attach(legacy)
