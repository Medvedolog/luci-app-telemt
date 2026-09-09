-- Telemt 3.5.7 Direct relay memory-budget control for the legacy CBI model.
-- UCI stores MiB for operator convenience; core init.d converts it to bytes.

local M = {}

function M.attach(m)
    if not m then return m end

    local general = nil
    for _, child in ipairs(m.children or {}) do
        if child.section == "general" and child.sectiontype == "telemt" then
            general = child
            break
        end
    end

    if not general then return m end

    local v = general:taboption(
        "general",
        Value,
        "direct_relay_buffer_budget_max_mib",
        "Direct relay memory budget (MiB)"
    )
    v.default = "0"
    v.rmempty = false
    v.placeholder = "0"
    v.description = "Hard ceiling for Telemt Direct relay copy buffers. 0 = Auto (recommended): Telemt derives the budget from host/cgroup memory. Manual range: 16–2048 MiB. This is not a whole-process OOM/cgroup limit."

    function v.validate(self, value)
        local n = tonumber(value)
        if not n or n ~= math.floor(n) then
            return nil, "Enter an integer MiB value: 0 for Auto, or 16–2048."
        end
        if n == 0 then return "0" end
        if n < 16 or n > 2048 then
            return nil, "Manual Direct relay memory budget must be between 16 and 2048 MiB."
        end
        return tostring(n)
    end

    return m
end

return M
