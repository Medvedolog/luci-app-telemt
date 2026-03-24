-- -- ==============================================================================
-- Telemt CBI Model (Configuration Binding Interface)
-- Version: 3.3.30
-- Changes from 3.3.29:
--   - Self-Stealth: mask_port and mask_host fields on General tab
--   - Shadowsocks upstream type with SIP002 URL field
--   - All version strings bumped to 3.3.30
-- Earlier: Version: 3.3.29
-- Changes from 3.3.21:
--   - Dark theme fix: replaced hardcoded color:#555/#888 with inherit/opacity
--   - Users & Upstreams tabs: "Active" column → "On" (saves width, tooltips preserved)
--   - Diagnostics: live connections counter (from Prometheus)
--   - Diagnostics: per-DC latency in Upstreams card (from /v1/runtime/upstream_quality)
--   - Diagnostics: formatted Beobachten scanner output (parsed categories)
--   - Diagnostics: Runtime Info human-readable (system/gates/events in log terminal)
--   - Users tab: IP address list tooltip on hover (from /v1/users API)
--   - Upstreams tab: runtime health badge per upstream (healthy/fails/latency)
--
--   - Built by vibing bears with tears and honey for OpenWrt (21.02 — 25.x) 🐻🍯
-- ==============================================================================

local sys = require "luci.sys"
local http = require "luci.http"
local dsp = require "luci.dispatcher"
local uci_cursor = require("luci.model.uci").cursor()

local function get_proxy_pid()
    -- Mirror init.d get_telemt_pids() logic: comm == "telemt" AND cmdline contains telemt.toml or binary path.
    -- CRITICAL: Use tr '\0' ' ' to handle null bytes in /proc/PID/cmdline (Lua 5.3 truncates at \0).
    for p in (sys.exec("pidof telemt 2>/dev/null") or ""):gmatch("%d+") do
        if (sys.exec("cat /proc/" .. p .. "/comm 2>/dev/null") or ""):gsub("%s+", "") == "telemt" then
            local cmdline = sys.exec("cat /proc/" .. p .. "/cmdline 2>/dev/null | tr '\\0' ' '") or ""
            if cmdline:match("telemt%.toml") or cmdline:match("/usr/bin/telemt") then return p end
        end
    end
    return ""
end

local function end_ajax()
    pcall(function() if dsp.context then dsp.context.dispatched = true end end)
    pcall(function() http.close() end)
end

local function has_cmd(c) return (sys.call("command -v " .. c .. " >/dev/null 2>&1") == 0) end
local fetch_bin = nil; if has_cmd("wget") then
    fetch_bin = "wget"
elseif has_cmd("uclient-fetch") then
    fetch_bin =
    "uclient-fetch"
end

local function read_file(path)
    local f = io.open(path, "r"); if not f then return "" end
    local d = f:read("*all") or ""; f:close(); return d
end

local function http_get_local(url, timeout)
    timeout = tonumber(timeout) or 2
    local res = ""
    if fetch_bin == "wget" then
        res = sys.exec(string.format("wget -q -T %d -O - %q 2>/dev/null", timeout, url)) or ""
    elseif fetch_bin == "uclient-fetch" then
        res = sys.exec(string.format("uclient-fetch -q -T %d -O - %q 2>/dev/null", timeout, url)) or ""
    end
    -- Fallback safety: do not return HTML errors meant for JSON/Prometheus parsers
    if res:sub(1, 1) == "<" then return "" end
    return res
end

local function cmp_ver(a, b)
    local a1, a2, a3 = a:match("^(%d+)%.(%d+)%.(%d+)")
    local b1, b2, b3 = b:match("^(%d+)%.(%d+)%.(%d+)")
    if not a1 then return -1 end
    if not b1 then return 1 end
    if tonumber(a1) ~= tonumber(b1) then return tonumber(a1) - tonumber(b1) end
    if tonumber(a2) ~= tonumber(b2) then return tonumber(a2) - tonumber(b2) end
    return tonumber(a3) - tonumber(b3)
end

local is_owrt25_lua = "false"
local ow_rel = sys.exec("cat /etc/openwrt_release 2>/dev/null") or ""
-- Detect OpenWrt 25+ (new LuCI JS DOM, no first column in TypedSection).
-- Matches: 25.xx.x, 25.xx.x-rcN, 26+, and bare SNAPSHOT (trunk, always ahead of latest release).
-- Does NOT match: 24.10.x, 24.10.0-rcN, 23.05.x — these have the old DOM with first column intact.
local _owrt_major = ow_rel:match("DISTRIB_RELEASE=['\"]?(%d+)")
if (_owrt_major and tonumber(_owrt_major) >= 25) or ow_rel:match("DISTRIB_RELEASE=['\"]?SNAPSHOT") then
    is_owrt25_lua = "true"
end

local _unpack = unpack or table.unpack
local _ok_url, current_url = pcall(function()
    if dsp.context and dsp.context.request then return dsp.build_url(_unpack(dsp.context.request)) end
    return nil
end)
if not _ok_url or not current_url or current_url == "" then current_url = dsp.build_url("admin", "services", "telemt") end
local safe_url = current_url:gsub('"', '\\"'):gsub('<', '&lt;'):gsub('>', '&gt;')
local qs_char = current_url:find("?", 1, true) and "&" or "?"

local function tip(txt) return string.format([[<span class="telemt-tip" title="%s">(?)</span>]], txt:gsub('"', '&quot;')) end
local is_ajax = (http.getenv("REQUEST_METHOD") == "POST" or http.formvalue("get_metrics") or http.formvalue("get_fw_status") or http.formvalue("get_scanners") or http.formvalue("get_log") or http.formvalue("get_wan_ip") or http.formvalue("get_qr") or http.formvalue("telemt_action") or http.formvalue("bot_action") or http.formvalue("get_bot_status"))

-- ==============================================================================
-- AJAX DISPATCHER
-- ==============================================================================
local is_post = (http.getenv("REQUEST_METHOD") == "POST")

-- NOTE: Server-side CSRF via http.formtoken() was removed intentionally.
-- Reason: formtoken() does not exist on many OpenWrt 21-23 LuCI builds,
-- causing "attempt to call field 'formtoken' (a nil value)" on ANY POST,
-- which breaks Save & Apply, service buttons, and all AJAX endpoints.
-- The CBI form already lives inside an authenticated LuCI session;
-- the standard sysauth session cookie provides sufficient protection.

if is_post and http.formvalue("log_ui_event") == "1" then
    local msg = http.formvalue("msg")
    if msg then
        sys.call(string.format("logger -t telemt %q",
            "WebUI: " .. msg:gsub("[%c]", " "):gsub("[^A-Za-z0-9 _.%-%:]", ""):sub(1, 128)))
    end
    http.prepare_content("text/plain"); pcall(function() http.write("ok") end); end_ajax(); return
end

if is_post and http.formvalue("telemt_action") then
    local act = http.formvalue("telemt_action")
    -- Thin wrappers: all lifecycle logic lives exclusively in /etc/init.d/telemt.
    -- The init.d script handles manual_stop flag, SIGTERM→wait→SIGKILL, save_stats, etc.
    if act == "start" then
        sys.call("logger -t telemt 'WebUI: Manual START'; /etc/init.d/telemt start >/dev/null 2>&1 &")
    elseif act == "stop" then
        sys.call("logger -t telemt 'WebUI: Manual STOP'; /etc/init.d/telemt stop >/dev/null 2>&1 &")
    elseif act == "restart" then
        sys.call("logger -t telemt 'WebUI: Manual RESTART'; /etc/init.d/telemt restart >/dev/null 2>&1 &")
    elseif act == "reset_stats" then
        sys.call("logger -t telemt 'WebUI: Reset Stats'; rm -f /tmp/telemt_stats.txt")
    end
    http.prepare_content("text/plain"); pcall(function() http.write("ok") end); end_ajax(); return
end

-- ==============================================================================
-- BOT SIDECAR AJAX HANDLERS
-- ==============================================================================
if is_post and http.formvalue("bot_action") then
    local act = http.formvalue("bot_action")
    if act == "start" then
        sys.call("logger -t telemt-bot 'WebUI: Manual START'; /etc/init.d/telemt-bot start >/dev/null 2>&1 &")
    elseif act == "stop" then
        sys.call("logger -t telemt-bot 'WebUI: Manual STOP'; /etc/init.d/telemt-bot stop >/dev/null 2>&1 &")
    elseif act == "restart" then
        sys.call("logger -t telemt-bot 'WebUI: Manual RESTART'; /etc/init.d/telemt-bot restart >/dev/null 2>&1 &")
    end
    http.prepare_content("text/plain"); pcall(function() http.write("ok") end); end_ajax(); return
end

if http.formvalue("get_bot_status") == "1" then
    -- Find telemt-bot PID (ash script, not the Rust binary)
    local pid = ""
    local raw_pids = sys.exec("pidof telemt-bot 2>/dev/null") or ""
    for p in raw_pids:gmatch("%d+") do
        local comm = (sys.exec("cat /proc/" .. p .. "/comm 2>/dev/null") or ""):gsub("%s+", "")
        if comm == "telemt-bot" or comm == "ash" or comm == "sh" then
            -- CRITICAL: tr '\0' ' ' prevents Lua 5.3 null-byte truncation
            local cmdline = sys.exec("cat /proc/" .. p .. "/cmdline 2>/dev/null | tr '\\0' ' '") or ""
            if cmdline:match("telemt%-bot") then pid = p; break end
        end
    end

    local status_json = '{"pid":"' .. pid .. '"'
    if pid ~= "" then
        local route = "unknown"
        local hf = io.open("/tmp/telemt_health_state", "r")
        if hf then
            local hdata = hf:read("*all") or ""; hf:close()
            local _, socks_st = hdata:match("^([^|]+)|([^|]+)")
            if socks_st == "reachable" then route = "socks"
            elseif socks_st == "unreachable" then route = "direct"
            elseif socks_st == "no_proxy" then route = "direct"
            elseif socks_st == "no_curl" then route = "direct"
            end
        end
        status_json = status_json .. ',"running":true,"route":"' .. route .. '"'
    else
        status_json = status_json .. ',"running":false'
    end
    status_json = status_json .. '}'
    http.prepare_content("application/json"); pcall(function() http.write(status_json) end); end_ajax(); return
end

-- RCE VULNERABILITY FIX: Strict validation of username before shell execution
if is_post and http.formvalue("auto_pause_user") then
    local u = http.formvalue("auto_pause_user"); local reason = http.formvalue("reason") or "Limit Exceeded"
    if u and u:match("^[A-Za-z0-9_]+$") then
        uci_cursor:set("telemt", u, "enabled", "0"); uci_cursor:save("telemt"); uci_cursor:commit("telemt")
        sys.call(string.format("logger -t telemt 'WebUI: Auto-paused user %q (Reason: %q)'", u, reason))
        sys.call("/etc/init.d/telemt reload >/dev/null 2>&1 &")
    end
    http.prepare_content("text/plain"); pcall(function() http.write("ok") end); end_ajax(); return
end

-- ATOMIC WRITE FIX: Write default config to tmp then atomic move to prevent 0-byte corruptions
if is_post and http.formvalue("reset_config") == "1" then
    sys.call("logger -t telemt 'WebUI: FACTORY RESET ALL SETTINGS'")
    local default_uci =
    "config telemt 'general'\n\toption enabled '0'\n\toption mode 'tls'\n\toption domain 'google.com'\n\toption port '8443'\n\toption metrics_port '9092'\n\toption api_port '9091'\n\toption extended_runtime_enabled '1'\n\toption metrics_allow_lo '1'\n\toption metrics_allow_lan '1'\n\toption log_level 'normal'\n"
    local f = io.open("/tmp/telemt_reset.tmp", "w")
    if f then
        f:write(default_uci); f:close()
        os.rename("/tmp/telemt_reset.tmp", "/etc/config/telemt")
    end
    sys.call("rm -f /tmp/etc/telemt.toml /var/etc/telemt.toml"); sys.call("/etc/init.d/telemt stop 2>/dev/null")
    http.prepare_content("text/plain"); pcall(function() http.write("ok") end); end_ajax(); return
end

if is_post and http.formvalue("export_config") == "1" then
    local conf = read_file("/tmp/etc/telemt.toml")
    if conf == "" then conf = "# telemt.toml not found or empty\n" end
    http.prepare_content("application/toml")
    http.header("Content-Disposition", "attachment; filename=\"telemt.toml\"")
    pcall(function() http.write(conf) end); end_ajax(); return
end

if http.formvalue("get_fw_status") == "1" then
    local afw = uci_cursor:get("telemt", "general", "auto_fw") or "0"
    local port = tonumber(uci_cursor:get("telemt", "general", "port")) or 8443
    local cmd = string.format(
        "/bin/sh -c \"iptables-save 2>/dev/null | grep -qiE 'Allow-Telemt-Magic|dport.*%d.*accept' || nft list ruleset 2>/dev/null | grep -qiE 'Allow-Telemt-Magic|dport.*%d.*accept'\"",
        port, port)
    local is_physically_open = (sys.call(cmd) == 0)
    local procd_check = sys.exec("ubus call service list '{\"name\":\"telemt\"}' 2>/dev/null")
    local is_procd_open = (procd_check and procd_check:match("Allow%-Telemt%-Magic") ~= nil)

    local pid = get_proxy_pid()
    local is_running = (pid ~= "")

    local status_msg, tip_msg = "<span style='color:red; font-weight:bold'>CLOSED</span>", "(Port not found in rules)"
    if is_physically_open then
        status_msg = "<span style='color:green; font-weight:bold'>OPEN (OK)</span>"; tip_msg = (afw == "0") and
            "(Auto-FW off, but port is open)" or ""
    elseif is_procd_open and is_running then
        status_msg = "<span style='color:green; font-weight:bold'>OPEN (OK)</span>"; tip_msg = "(Visible via ubus API)"
    end

    if not is_running then
        status_msg =
            "<span style='color:#d9534f; font-weight:bold'>SERVICE STOPPED</span> <span style='color:#888'>|</span> " ..
            status_msg
    end

    http.prepare_content("text/plain"); pcall(function()
        http.write(status_msg ..
            (tip_msg ~= "" and " <span style='color:#888; font-size:0.85em; margin-left:5px;'>" .. tip_msg .. "</span>" or ""))
    end); end_ajax(); return
end

-- ==============================================================================
-- ZERO-COST MULTIPLEXED METRICS & API POLLING
-- ==============================================================================
if http.formvalue("get_metrics") == "1" then
    local m_port = tonumber(uci_cursor:get("telemt", "general", "metrics_port")) or 9092
    local api_port = tonumber(uci_cursor:get("telemt", "general", "api_port")) or 9091
    local ext_rt = uci_cursor:get("telemt", "general", "extended_runtime_enabled") or "1"

    local metrics = ""
    -- Pass UCI config flags to JS for runtime_view computation
    local uci_use_mp = uci_cursor:get("telemt", "general", "use_middle_proxy") or "0"
    metrics = metrics .. "# telemt_uci_use_mp=" .. uci_use_mp .. "\n"
    -- Pass upstream types for egress badge (API may not return type field)
    local up_types = {}
    uci_cursor:foreach("telemt", "upstream", function(s)
        local en = s.enabled
        if en ~= "0" then
            table.insert(up_types, s.type or "direct")
        end
    end)
    metrics = metrics .. "# telemt_uci_upstream_types=" .. table.concat(up_types, ",") .. "\n"
    local memfile = io.open("/proc/meminfo", "r")
    if memfile then
        local memtxt = memfile:read("*all"); memfile:close()
        local avail = memtxt:match("MemAvailable:%s+(%d+)%s+kB")
        if not avail then avail = memtxt:match("MemFree:%s+(%d+)%s+kB") end
        if avail then metrics = metrics .. "# sys_mem_avail_kb=" .. avail .. "\n" end
    end

    local pid = get_proxy_pid()

    if pid ~= "" then
        metrics = metrics .. "# telemt_pid=" .. pid .. "\n"
        local statfile = io.open("/proc/" .. pid .. "/status", "r")
        if statfile then
            local stattxt = statfile:read("*all"); statfile:close()
            local rss = stattxt:match("VmRSS:%s+(%d+)%s+kB")
            if rss then metrics = metrics .. "# telemt_rss_kb=" .. rss .. "\n" end
        end
    end

    -- FIX 3.3.30: Always try Prometheus (9092) regardless of PID.
    -- Prometheus is always-on when binary runs; PID detection may temporarily fail.
    local prom_str = http_get_local("http://127.0.0.1:" .. m_port .. "/metrics", 2)
    if prom_str ~= "" then
        metrics = metrics .. "# telemt_metrics_up=1\n"
        metrics = metrics .. prom_str
    elseif pid ~= "" then
        -- PID found but metrics not ready yet — daemon is booting
        metrics = metrics .. "# telemt_state=starting\n"
    end

    -- READ RACE CONDITION FIX: Atomic copy before parsing accumulated stats
    sys.call("cp -f /tmp/telemt_stats.txt /tmp/telemt_stats_read.tmp 2>/dev/null")
    local f = io.open("/tmp/telemt_stats_read.tmp", "r")
    if f then
        metrics = metrics .. "\n# ACCUMULATED\n"
        for line in f:lines() do
            local u, tx, rx = line:match("^(%S+) (%S+) (%S+)$")
            if u then
                metrics = metrics ..
                    string.format("telemt_accumulated_tx{user=\"%s\"} %s\ntelemt_accumulated_rx{user=\"%s\"} %s\n", u, tx,
                        u,
                        rx)
            end
        end
        f:close()
    end

    -- API (9091) — gate on (pid OR metrics available) AND ext_rt enabled
    local has_runtime = (pid ~= "" or prom_str ~= "")
    if has_runtime and ext_rt == "1" then
        metrics = metrics .. "\n---TELEMT_API_JSON---\n"
        local api_json = http_get_local("http://127.0.0.1:" .. api_port .. "/v1/stats/minimal/all", 2)
        metrics = metrics .. ((api_json ~= "" and api_json) or "{}")
        -- Upstream status is a separate endpoint not included in minimal/all
        local up_json = http_get_local("http://127.0.0.1:" .. api_port .. "/v1/stats/upstreams", 1)
        metrics = metrics .. "\n---TELEMT_UPSTREAMS_JSON---\n"
        metrics = metrics .. ((up_json ~= "" and up_json) or "{}")
        -- Upstream quality with per-DC latency (3.3.22+, graceful empty on older binaries)
        local upq_json = http_get_local("http://127.0.0.1:" .. api_port .. "/v1/runtime/upstream_quality", 1)
        metrics = metrics .. "\n---TELEMT_UPSTREAM_QUALITY_JSON---\n"
        metrics = metrics .. ((upq_json ~= "" and upq_json) or "{}")
        -- User details with IP lists (for tooltip display, 3.3.15+)
        local users_json = http_get_local("http://127.0.0.1:" .. api_port .. "/v1/users", 1)
        metrics = metrics .. "\n---TELEMT_USERS_API_JSON---\n"
        metrics = metrics .. ((users_json ~= "" and users_json) or "{}")
    end

    http.prepare_content("text/plain"); pcall(function() http.write(metrics) end); end_ajax(); return
end

-- ==============================================================================
-- OTHER AJAX ENDPOINTS
-- ==============================================================================
if http.formvalue("get_scanners") == "1" then
    local m_port = tonumber(uci_cursor:get("telemt", "general", "metrics_port")) or 9092
    local res = http_get_local("http://127.0.0.1:" .. m_port .. "/beobachten", 3)
    if not res or res:gsub("%s+", "") == "" then res = "No active scanners detected or proxy is offline." end
    http.prepare_content("text/plain"); pcall(function() http.write(res) end); end_ajax(); return
end

if http.formvalue("get_log") == "1" then
    http.prepare_content("text/plain")
    local cmd = "logread -e 'telemt' | tail -n 100 2>/dev/null"
    if has_cmd("timeout") then cmd = "timeout 2 " .. cmd end
    local log_data = sys.exec(cmd)
    if not log_data or log_data:gsub("%s+", "") == "" then
        log_data = "No logs found."
    else
        log_data = log_data:gsub("\27%[%d+;?%d*m", "")
    end
    pcall(function() http.write(log_data) end); end_ajax(); return
end

if http.formvalue("get_wan_ip") == "1" then
    local ip = http_get_local("https://ipv4.internet.yandex.net/api/v0/ip", 3):gsub("%s+", ""):gsub("\"", "")
    if not ip:match("^%d+%.%d+%.%d+%.%d+$") then ip = http_get_local("https://checkip.amazonaws.com", 3):gsub("%s+", "") end
    http.prepare_content("text/plain"); pcall(function() http.write(ip:match("^%d+%.%d+%.%d+%.%d+$") and ip or "0.0.0.0") end); end_ajax(); return
end

if http.formvalue("get_qr") == "1" then
    local link = http.formvalue("link")
    if not link or link == "" or not link:match("^tg://proxy%?[a-zA-Z0-9=%%&_.-]+$") then
        http.prepare_content("text/plain"); pcall(function() http.write("error: invalid_link") end); end_ajax(); return
    end
    if not has_cmd("qrencode") then
        http.prepare_content("text/plain"); pcall(function() http.write("error: qrencode_missing") end); end_ajax(); return
    end
    local cmd = string.format("qrencode -t SVG -s 4 -m 1 -o - %q 2>/dev/null", link)
    http.prepare_content("image/svg+xml"); pcall(function() http.write(sys.exec(cmd)) end); end_ajax(); return
end

local function norm_secret(s)
    if not s then return nil end; s = s:match("secret=(%x+)") or s; local hex = s:match("(%x+)"); if not hex then return nil end; local pfx =
        hex:sub(1, 2):lower(); if pfx == "ee" or pfx == "dd" then hex = hex:sub(3) end; if #hex < 32 then return nil end; return
        hex:sub(1, 32):lower()
end

if is_post and http.formvalue("import_users") == "1" then
    local csv = http.formvalue("csv_data")
    if csv and csv ~= "" then
        local valid_users = {}; local char_cr, char_lf, bom = string.char(13), string.char(10),
            string.char(239, 187, 191)
        csv = csv:gsub("^" .. bom, ""):gsub(char_cr .. char_lf, char_lf):gsub(char_cr, char_lf)
        for line in csv:gmatch("[^" .. char_lf .. "]+") do
            if not line:match("^username,") and not line:match("^<") then
                local p = {}; for f in (line .. ","):gmatch("([^,]*),") do table.insert(p, (f:gsub("^%s*(.-)%s*$", "%1"))) end
                local u, sec, c, uips, q, exp = p[1], p[2], p[3], p[4], p[5], p[6]; local sec_clean = norm_secret(sec)
                if c and c ~= "" and c ~= "unlimited" and not c:match("^%d+$") then c = "" end
                if uips and uips ~= "" and uips ~= "unlimited" and not uips:match("^%d+$") then uips = "" end
                if q and q ~= "" and q ~= "unlimited" and not q:match("^%d+%.?%d*$") then q = "" end
                if u and u ~= "" and u:match("^[A-Za-z0-9_]+$") and #u <= 15 and sec_clean then
                    table.insert(valid_users,
                        { u = u, sec = sec_clean, c = c, uips = uips, q = q, exp = exp })
                end
            end
        end
        if #valid_users > 0 then
            if http.formvalue("import_mode") == "replace" then
                local to_delete = {}; uci_cursor:foreach("telemt", "user",
                    function(s) table.insert(to_delete, s['.name']) end); for _, name in ipairs(to_delete) do
                    uci_cursor
                        :delete("telemt", name)
                end
            end
            for _, v in ipairs(valid_users) do
                uci_cursor:set("telemt", v.u, "user"); uci_cursor:set("telemt", v.u, "secret", v.sec); uci_cursor:set(
                    "telemt", v.u, "enabled", "1")
                if v.c and v.c ~= "" then
                    uci_cursor:set("telemt", v.u, "max_tcp_conns", v.c)
                else
                    uci_cursor:delete(
                        "telemt", v.u, "max_tcp_conns")
                end
                if v.uips and v.uips ~= "" then
                    uci_cursor:set("telemt", v.u, "max_unique_ips", v.uips)
                else
                    uci_cursor
                        :delete("telemt", v.u, "max_unique_ips")
                end
                if v.q and v.q ~= "" then
                    uci_cursor:set("telemt", v.u, "data_quota", v.q)
                else
                    uci_cursor:delete(
                        "telemt", v.u, "data_quota")
                end
                if v.exp and v.exp:match("^%d%d%.%d%d%.%d%d%d%d %d%d:%d%d$") then
                    uci_cursor:set("telemt", v.u,
                        "expire_date", v.exp)
                else
                    uci_cursor:delete("telemt", v.u, "expire_date")
                end
            end
            uci_cursor:save("telemt"); uci_cursor:commit("telemt")
            sys.call("logger -t telemt \"WebUI: Successfully imported " .. #valid_users .. " users via CSV.\"")
            http.redirect(current_url .. qs_char .. "import_ok=" .. tostring(#valid_users)); return
        end
    end
    http.redirect(current_url); return
end

local clean_csv = "username,secret,max_tcp_conns,max_unique_ips,data_quota,expire_date\n"
uci_cursor:foreach("telemt", "user",
    function(s)
        clean_csv = clean_csv ..
            string.format("%s,%s,%s,%s,%s,%s\n", s['.name'] or "", s.secret or "", s.max_tcp_conns or "",
                s.max_unique_ips or "", s.data_quota or "", s.expire_date or "")
    end)
clean_csv = clean_csv:gsub("\n", "\\n"):gsub("\r", ""):gsub('"', '\\"') -- ESCAPE FIX

-- ==============================================================================
-- STATIC DASHBOARD RENDER
-- ==============================================================================
local bin_path = ""
if sys.call("test -x /usr/bin/telemt") == 0 then
    bin_path = "/usr/bin/telemt"
elseif sys.call("test -x /bin/telemt") == 0 then
    bin_path = "/bin/telemt"
end

local bin_ver = "unknown"
local comp_badge = "<span style='color:#d9534f;font-weight:bold;'>[ Not Installed ]</span>"

if bin_path ~= "" then
    local f = io.open("/tmp/etc/telemt.version", "r")
    if f then
        bin_ver = f:read("*all"):gsub("%s+", ""); f:close()
    end
    if bin_ver == "" then
        bin_ver = (sys.exec("grep -a -m 1 -ioE 'MTProxy v[0-9]+\\.[0-9]+\\.[0-9]+' " .. bin_path .. " 2>/dev/null | head -n 1 | grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+'") or "")
            :gsub("%s+", "")
    end
    if bin_ver == "" then bin_ver = "unknown" end

    if bin_ver == "unknown" then
        comp_badge = "<span style='color:#d35400;font-weight:bold;'>[ Unknown Version ]</span>"
    elseif cmp_ver(bin_ver, "3.3.15") >= 0 then
        comp_badge = "<span style='color:#00a000;font-weight:bold;'>[ Compatible ]</span>"
    else
        comp_badge = "<span style='color:#d9534f;font-weight:bold;'>[ Unsupported Version ]</span>"
    end
end

m = Map("telemt", "Telegram Proxy (MTProto)",
    [[Multi-user proxy server based on <a href="https://github.com/telemt/telemt" target="_blank" style="text-decoration:none; color:inherit; font-weight:bold; border-bottom: 1px dotted currentColor;">telemt</a>.<br><b>LuCI App Version: <a href="https://github.com/Medvedolog/luci-app-telemt" target="_blank" style="text-decoration:none; color:inherit; border-bottom: 1px dotted currentColor;">3.3.30</a></b> | <span style='color:#d35400; font-weight:bold;'>Requires telemt v3.3.15+</span>]])
m.on_commit = function(self)
    sys.call(
        "logger -t telemt 'WebUI: Config saved. Dumping stats before procd reload...'; /etc/init.d/telemt run_save_stats 2>/dev/null")
end

s = m:section(NamedSection, "general", "telemt")
s.anonymous = true

s:tab("general", "General Settings")
s:tab("advanced", "Advanced Tuning")
s:tab("upstreams", "Upstreams")
s:tab("users", "Users")
s:tab("bot", "Telegram Bot")
s:tab("log", "Diagnostics")

-- === TAB: GENERAL ===
s:taboption("general", Flag, "enabled", "Enable Service")
local ctrl = s:taboption("general", DummyValue, "_controls", "Controls")
ctrl.rawhtml = true
ctrl.default = string.format([[
<div class="btn-controls">
    <input type="button" class="cbi-button cbi-button-apply" id="btn_telemt_start" value="Start" />
    <input type="button" class="cbi-button cbi-button-reset" id="btn_telemt_stop" value="Stop" />
    <input type="button" class="cbi-button cbi-button-reload" id="btn_telemt_restart" value="Restart" />
</div>
<script>
var _actionInProgress = false;
function postAction(action) {
    if (_actionInProgress) return;
    _actionInProgress = true;

    // Visual feedback: disable buttons, show orange transitional state
    var labels = { start: 'STARTING\u2026', stop: 'STOPPING\u2026', restart: 'RESTARTING\u2026' };
    var stEl = document.getElementById('dash_status');
    if (stEl && labels[action]) { stEl.innerText = labels[action]; stEl.style.color = '#d35400'; }
    ['start', 'stop', 'restart'].forEach(function(a) {
        var b = document.getElementById('btn_telemt_' + a); if (b) { b.disabled = true; b.style.opacity = '0.5'; }
    });

    var f = new FormData(); f.append('telemt_action', action);
    var tok = null; var tn = document.querySelector('input[name="token"]');
    if (tn) tok = tn.value; else if (typeof L !== 'undefined' && L.env) tok = L.env.token || L.env.requesttoken || null;
    if (!tok) { var cm = document.cookie.match(/(?:sysauth_http|sysauth)=([^;]+)/); if (cm) tok = cm[1]; }
    if (tok) f.append('token', tok);

    fetch(lu_current_url.split('#')[0], { method: 'POST', body: f }).then(function(){
        // DON'T call fetchMetrics here — the init.d command runs async (&),
        // so the process is likely still alive. Let the 6s timeout handle the update.
    }).catch(function(err){ console.error("Action error:", err); });

    // Re-enable buttons after timeout (init.d takes up to ~8s worst case)
    setTimeout(function() {
        _actionInProgress = false;
        ['start', 'stop', 'restart'].forEach(function(a) {
            var b = document.getElementById('btn_telemt_' + a); if (b) { b.disabled = false; b.style.opacity = '1'; }
        });
        window._telemtFastPoll = true;
        if(typeof fetchMetrics !== 'undefined') fetchMetrics();
        if(typeof updateFWStatus !== 'undefined') updateFWStatus();
    }, 6000);
}
setTimeout(function(){
    ['start', 'stop', 'restart'].forEach(function(act) {
        var btn = document.getElementById('btn_telemt_' + act);
        if(btn && !btn.dataset.bound) {
            btn.dataset.bound = "1";
            btn.addEventListener('click', function(e){
                e.preventDefault(); e.stopPropagation();
                logAction('Manual ' + act); postAction(act);
            });
        }
    });
}, 500);
</script>]], current_url)

local st_html = string.format([[
<div style="font-family:monospace; background:rgba(128,128,128,0.05); border:1px solid rgba(128,128,128,0.2); border-radius:6px; padding:12px; line-height:1.6;">
    <div style="margin-bottom:4px;"><b>Service:</b> <span id="dash_status" style="color:#888;font-weight:bold;">PENDING...</span> &nbsp;<span id="dash_uptime" style="color:#666; font-size:0.9em;"></span></div>
    <div style="margin-bottom:8px;"><b>Memory :</b> Telemt RSS: <b id="dash_rss" style="color:#00a000;">--</b> &nbsp;|&nbsp; RAM Free: <b id="dash_ram" style="color:#555;">--</b></div>
    <div style="padding-top:8px; border-top:1px dashed rgba(128,128,128,0.2);">
        <b>Binary :</b> <span style="color:#555;">%s (v%s)</span> &nbsp;%s
    </div>
</div>
]], bin_path ~= "" and bin_path or "Missing", bin_ver, comp_badge)

local st = s:taboption("general", DummyValue, "_status", "System Dashboard")
st.rawhtml = true
st.value = st_html

local mode = s:taboption("general", ListValue, "mode",
    "Protocol Mode" .. tip("FakeTLS: HTTPS masking. DD: Old obfuscation. Classic: MTProto without masking."))
mode:value("tls", "FakeTLS (Recommended)"); mode:value("dd", "DD (Random Padding)"); mode:value("classic", "Classic"); mode
    :value("all", "All together (Debug)"); mode.default = "tls"

local lfmt = s:taboption("general", ListValue, "_link_fmt",
    "Link Format to Display" .. tip("Select which protocol link to show in the Users tab for copying."))
lfmt:depends("mode", "all"); lfmt:value("tls", "FakeTLS (Recommended)"); lfmt:value("dd", "Secure (DD)"); lfmt:value(
    "classic", "Classic"); lfmt.default = "tls"

local dom = s:taboption("general", Value, "domain",
    "FakeTLS Domain" .. tip("Unauthenticated DPI traffic will be routed here. Must be ASCII only."))
dom.datatype = "hostname"; dom.default = "google.com"; dom.description =
"<span class='warn-txt' style='color:#d35400; font-weight:bold;'>Warning: Change the default domain!</span>"
dom:depends("mode", "tls"); dom:depends("mode", "all")

local function validate_ip_domain(self, value)
    if value and #value > 0 then
        value = value:match("^([^%s]+)")
        if not value:match("^[a-zA-Z0-9%-%.:]+$") then return nil, "Invalid characters!" end
    end
    return value
end

local saved_ip = m.uci:get("telemt", "general", "external_ip")
if type(saved_ip) == "table" then saved_ip = saved_ip[1] or "" end; saved_ip = saved_ip or ""; if saved_ip:match("%s") then
    saved_ip =
        saved_ip:match("^([^%s]+)")
end

local myip = s:taboption("general", Value, "external_ip",
    "External IP / DynDNS" .. tip("IP address or domain used strictly for generating tg:// links in UI."))
myip.datatype = "string"; myip.default = saved_ip; myip.validate = validate_ip_domain

local p = s:taboption("general", Value, "port",
    "MTProxy Port" .. tip("The port on which the MTProxy server will listen for connections.")); p.datatype = "port"; p.rmempty = false; p.default =
"8443"
local pp = s:taboption("general", Value, "public_port",
    "Port Override for Links" ..
    tip(
        "Optional. If your router uses NAT port-mapping (e.g. external 443 → internal 8443), enter the external port here. tg:// links will use this port instead."))
pp.datatype = "port"; pp.placeholder = "same as MTProxy Port"

local afw = s:taboption("general", Flag, "auto_fw",
    "Auto-open Port (Magic)" ..
    tip(
        "Uses procd API to open port in RAM. Rule will not appear in Firewall menu. Closes automatically if proxy stops."))
afw.default = "0"; afw.description =
"<div style='margin-top:5px; padding:8px; background:rgba(128,128,128,0.1); border-left:3px solid #00a000; font-size:0.9em;'><b>Current Status:</b> <span id='fw_status_span' style='color:#888; font-style:italic;'>Checking...</span></div>"

local ll = s:taboption("general", ListValue, "log_level", "Log Level" .. tip("Verbosity of telemt daemon log output.")); ll
    :value("debug", "Debug"); ll:value("verbose", "Verbose"); ll:value("normal", "Normal (default)"); ll:value("silent",
    "Silent"); ll.default = "normal"

-- === TAB: UPSTREAMS (CASCADES) ===
local up_anchor = s:taboption("upstreams", DummyValue, "_up_anchor", ""); up_anchor.rawhtml = true; up_anchor.default =
'<div id="upstreams_tab_anchor" style="display:none"></div>'
local up_master = s:taboption("upstreams", Flag, "enable_upstreams",
    "Enable All Cascades" .. tip("Master switch for Upstream Proxies. Disabling this falls back to Direct.")); up_master.default =
"1"

s_up = m:section(TypedSection, "upstream", "Upstreams (Cascades)",
    "Chain your outgoing Telegram traffic through other servers to bypass ISP DPI.<br><span style='color:#555;'><b>Note:</b> If no upstreams are enabled, the proxy will gracefully fallback to <b>Direct Connection</b>.</span>")
s_up.addremove = true; s_up.anonymous = true

local u_lbl = s_up:option(Value, "alias", "Cascade Name" .. tip("Optional. Latin letters, numbers and spaces only."))
u_lbl.placeholder = "e.g. Frankfurt Server"
function u_lbl.validate(self, v, section)
    if not v or v == "" then return v end
    if not v:match("^[A-Za-z0-9 _]+$") then return nil, "Only Latin letters, numbers and spaces allowed!" end
    local count = 0; uci_cursor:foreach("telemt", "upstream",
        function(s) if s.alias == v and s['.name'] ~= section then count = count + 1 end end)
    if count > 0 then return nil, "Cascade name must be unique!" end; return v
end

local uen = s_up:option(Flag, "enabled", "On"); uen.default = "1"; uen.rmempty = false
local ut = s_up:option(ListValue, "type", "Protocol")
ut:value("direct", "Direct"); ut:value("socks4", "SOCKS4"); ut:value("socks5", "SOCKS5")
ut:value("shadowsocks", "Shadowsocks"); ut.default = "socks5"

local ua = s_up:option(Value, "address", "Address" .. tip("Format: IP:PORT or HOST:PORT."))
ua.datatype = "hostport"; ua:depends("type", "socks4"); ua:depends("type", "socks5")
ua.placeholder = "192.168.1.1:1080"
function ua.validate(self, v)
    if v and v ~= "" and not v:match("^[A-Za-z0-9%.%:%-]+$") then return nil, "Invalid characters!" end
    return v
end

-- PATCH 3.3.30: Shadowsocks URL field (SIP002 format: ss://method:key@host:port)
-- Requires use_middle_proxy = false. Binary fails fast if ME mode is enabled.
local uss = s_up:option(Value, "url",
    "Shadowsocks URL" .. tip("SIP002 format: ss://method:key@host:port. Requires Middle Proxy OFF."))
uss:depends("type", "shadowsocks"); uss.placeholder = "ss://2022-blake3-aes-256-gcm:BASE64KEY@1.2.3.4:8388"

local uint = s_up:option(Value, "interface",
    "Interface / Bind IP" .. tip("Optional. Bind outgoing traffic to specific local IP."))
uint:depends("type", "direct")
function uint.validate(self, v)
    if v and v ~= "" and not v:match("^[A-Za-z0-9%.%:%-%_]+$") then return nil, "Invalid characters!" end
    return v
end

local uu = s_up:option(Value, "username", "Username" .. tip("Optional. Latin letters and numbers only, no hyphens."))
uu:depends("type", "socks5"); function uu.validate(self, v)
    if v and v ~= "" and not v:match("^[A-Za-z0-9_]+$") then
        return nil,
            "Only Latin letters, numbers and underscores allowed!"
    end
    return v
end

local up = s_up:option(Value, "password", "Password" .. tip("Optional. Password for SOCKS. Latin only, no hyphens.")); up.password = true
up:depends("type", "socks5"); function up.validate(self, v)
    if v and v ~= "" and not v:match("^[A-Za-z0-9_]+$") then
        return nil,
            "Only Latin letters, numbers and underscores allowed!"
    end
    return v
end

local uw = s_up:option(Value, "weight", "Weight" .. tip("Routing priority weight. Default: 10.")); uw.datatype =
"uinteger"; uw.default = "10"; uw.placeholder = "10"

local usc = s_up:option(Value, "scopes",
    "Scopes" .. tip("Optional. Comma-separated scopes (e.g. 'premium,me'). Leave empty for all."))
usc.placeholder = "premium,me"; function usc.validate(self, v)
    if v and v ~= "" and not v:match("^[A-Za-z0-9_,]+$") then
        return nil,
            "Only Latin letters, numbers, underscores and commas allowed!"
    end
    return v
end

-- === TAB: ADVANCED ===
local hnet = s:taboption("advanced", DummyValue, "_head_net"); hnet.rawhtml = true; hnet.default =
"<h3>Network Listeners</h3>"
s:taboption("advanced", Flag, "listen_ipv4", "Enable IPv4 Listener" .. tip("Listen for incoming IPv4 connections on 0.0.0.0")).default =
"1"
s:taboption("advanced", Flag, "listen_ipv6", "Enable IPv6 Listener (::)" .. tip("Listen for incoming IPv6 connections on ::")).default =
"0"
local pref_ip = s:taboption("advanced", ListValue, "prefer_ip",
    "Preferred IP Protocol" .. tip("Which protocol to prefer when connecting to Telegram DC.")); pref_ip:value("4",
    "IPv4"); pref_ip:value("6", "IPv6"); pref_ip.default = "4"

local hme = s:taboption("advanced", DummyValue, "_head_me"); hme.rawhtml = true; hme.default =
"<h3 style='margin-top:20px;'>Middle-End Proxy</h3>"
local mp = s:taboption("advanced", Flag, "use_middle_proxy",
    "Use ME Proxy" .. tip("Allows Media/CDN (DC=203) to work correctly.")); mp.default = "0"; mp.description =
"<span style='color:#d35400; font-weight:bold;'>Requires public IP on interface OR NAT 1:1 with STUN enabled.</span>"
local stun = s:taboption("advanced", Flag, "use_stun",
    "Enable STUN-probing" .. tip("Leave enabled if your server is behind NAT. Required for ME proxy on standard setups.")); stun
    :depends("use_middle_proxy", "1"); stun.default = "0"
local meps = s:taboption("advanced", Value, "me_pool_size",
    "ME Pool Size" .. tip("Desired number of concurrent ME writers in pool. Default: 16.")); meps.datatype = "uinteger"; meps
    :depends("use_middle_proxy", "1")

local h_me_adv = s:taboption("advanced", DummyValue, "_head_me_adv")
h_me_adv.rawhtml = true
h_me_adv.default =
[[<div style="display:block; width:100%;"><details id="telemt_me_opts_details" style="display:block; width:100%; box-sizing:border-box; margin-top:15px; padding:10px; background:rgba(128,128,128,0.05); border:1px solid rgba(128,128,128,0.3); border-radius:6px; cursor:pointer;"><summary style="font-weight:bold; font-size:1.05em; outline:none; cursor:pointer; color:inherit;">Deep ME Tuning (Click to expand)</summary><p style="font-size:0.85em; opacity:0.8; margin-top:5px; margin-bottom:0;">Advanced Adaptive Pool and Recovery parameters. Edit only if you understand the runtime model.</p></details></div>]]
h_me_adv:depends("use_middle_proxy", "1")

-- ME Pool — only fields that are actually written to TOML by init.d
local mwsb = s:taboption("advanced", Value, "me_warm_standby",
    "ME Warm Standby" .. tip("Pre-initialized connections kept idle. Default: 8.")); mwsb.datatype = "uinteger"; mwsb
    :depends("use_middle_proxy", "1")
s:taboption("advanced", Flag, "hardswap", "ME Pool Hardswap" .. tip("Enable C-like hard-swap for ME pool generations."))
    :depends("use_middle_proxy", "1")
local mdt = s:taboption("advanced", Value, "me_drain_ttl",
    "ME Drain TTL (sec)" .. tip("Drain-TTL in seconds for stale ME writers. Default: 90.")); mdt.datatype = "uinteger"; mdt
    :depends("use_middle_proxy", "1")
local adeg = s:taboption("advanced", Flag, "auto_degradation",
    "Auto-Degradation (Fallback)" .. tip("Enable auto-degradation from ME to Direct-DC if ME fails. Default: enabled.")); adeg.default =
"1"; adeg:depends("use_middle_proxy", "1")
local dmdc = s:taboption("advanced", Value, "degradation_min_dc",
    "Degradation Min DC" .. tip("Minimum unavailable ME DC groups before degrading. Default: 2.")); dmdc.datatype =
"uinteger"; dmdc:depends({ use_middle_proxy = "1", auto_degradation = "1" })

local hadv = s:taboption("advanced", DummyValue, "_head_adv"); hadv.rawhtml = true
hadv.default =
[[<div style="display:block; width:100%;"><details id="telemt_adv_opts_details" style="display:block; width:100%; box-sizing:border-box; margin-top:20px; padding:10px; background:rgba(128,128,128,0.05); border:1px solid rgba(128,128,128,0.3); border-radius:6px; cursor:pointer;"><summary style="font-weight:bold; font-size:1.05em; outline:none; cursor:pointer;">Additional Options (Click to expand)</summary><p style="font-size:0.85em; opacity:0.8; margin-top:5px; margin-bottom:0;">Extra proxy settings and overrides.</p></details></div>]]
s:taboption("advanced", Flag, "desync_all_full", "Full Crypto-Desync Logs" .. tip("Emit full forensic logs for every event. Default: disabled (false).")).default =
"0"
-- PATCH 3.3.30: Self-Stealth — mask_port and mask_host allow redirecting DPI scanners
-- to a local web server (e.g. uhttpd) instead of the real tls_domain.
local mpt = s:taboption("advanced", Value, "mask_port",
    "Mask Port" .. tip("TCP port where TLS probers are relayed. Default 443 = same as tls_domain. Set e.g. 4433 to redirect scanners to a local web server (uhttpd, nginx).")); mpt.datatype =
"port"; mpt.default = "443"; mpt.placeholder = "443"
local mht = s:taboption("advanced", Value, "mask_host",
    "Mask Host" .. tip("IP or hostname where TLS probers are relayed. Leave empty = use tls_domain. Set '127.0.0.1' to redirect scanners to localhost (Self-Stealth).")); mht.datatype =
"string"; mht.placeholder = "127.0.0.1"
local mpp = s:taboption("advanced", ListValue, "mask_proxy_protocol",
    "Mask Proxy Protocol" .. tip("Send PROXY protocol header to mask_host (if behind HAProxy/Nginx).")); mpp:value("0",
    "0 (Off)"); mpp:value("1", "1 (v1 - Text)"); mpp:value("2", "2 (v2 - Binary)"); mpp.default = "0"
local aip = s:taboption("advanced", Value, "announce_ip",
    "Announce Address" .. tip("Optional. Public IP or Domain for tg:// links. Overrides 'External IP' if set.")); aip.datatype =
"string"; aip.validate = validate_ip_domain
local ad = s:taboption("advanced", Value, "ad_tag", "Ad Tag" .. tip("Get your 32-hex promotion tag from @mtproxybot.")); ad.datatype =
"hexstring"
local fcl = s:taboption("advanced", Value, "fake_cert_len",
    "Fake Cert Length" .. tip("Size of the generated fake TLS certificate in bytes. Default: 2048.")); fcl.datatype =
"uinteger"
local ttlc = s:taboption("advanced", Value, "tls_full_cert_ttl_secs",
    "TLS Full Cert TTL (sec)" .. tip("Time-to-Live for the full certificate chain per client IP. Default: 90.")); ttlc.datatype =
"uinteger"
s:taboption("advanced", Flag, "ignore_time_skew", "Ignore Time Skew" .. tip("Disable strict time checks. Useful if clients have desynced clocks.")).default =
"0"

local htm = s:taboption("advanced", DummyValue, "_head_tm"); htm.rawhtml = true
htm.default =
[[<div style="display:block; width:100%;"><details id="telemt_timeouts_details" style="display:block; width:100%; box-sizing:border-box; margin-top:20px; padding:10px; background:rgba(128,128,128,0.05); border:1px solid rgba(128,128,128,0.3); border-radius:6px; cursor:pointer;"><summary style="font-weight:bold; font-size:1.05em; outline:none; cursor:pointer;">Timeouts & Replay Protection (Click to expand)</summary><p style="font-size:0.85em; opacity:0.8; margin-top:5px; margin-bottom:0;">Adjust connection timeouts and replay window. Leave defaults if unsure.</p></details></div>]]
local tm_h = s:taboption("advanced", Value, "tm_handshake", "Handshake" .. tip("Client handshake timeout in seconds.")); tm_h.datatype =
"uinteger"; tm_h.default = "15"
local tm_c = s:taboption("advanced", Value, "tm_connect", "Connect" .. tip("Telegram DC connect timeout in seconds.")); tm_c.datatype =
"uinteger"; tm_c.default = "10"
local tm_k = s:taboption("advanced", Value, "tm_keepalive", "Keepalive" .. tip("Client keepalive interval in seconds.")); tm_k.datatype =
"uinteger"; tm_k.default = "60"
local tm_a = s:taboption("advanced", Value, "tm_ack", "ACK" .. tip("Client ACK timeout in seconds.")); tm_a.datatype =
"uinteger"; tm_a.default = "300"
local rw_s = s:taboption("advanced", Value, "replay_window_secs",
    "Replay Window (sec)" .. tip("Time window for replay attack protection. Default: 1800.")); rw_s.datatype = "uinteger"; rw_s.default =
"1800"

local hmet = s:taboption("advanced", DummyValue, "_head_met"); hmet.rawhtml = true; hmet.default =
"<h3 style='margin-top:20px;'>Metrics & Control API</h3>"
local api_chk = s:taboption("advanced", Flag, "extended_runtime_enabled",
    "Enable Control API & Extended Runtime" ..
    tip("Unified switch. Required for detailed UI diagnostics, Live Traffic stats, and the autonomous Telegram Bot."))
api_chk.default = "1"
api_chk.rmempty = false
local mport = s:taboption("advanced", Value, "metrics_port",
    "Prometheus Port" .. tip("Port for internal Prometheus exporter. Default: 9092.")); mport.datatype = "port"; mport.default =
"9092"
local aport = s:taboption("advanced", Value, "api_port",
    "Control API Port" .. tip("Port for the REST API (v1). Default: 9091.")); aport.datatype = "port"; aport.default =
"9091"
s:taboption("advanced", Flag, "metrics_allow_lo", "Allow Localhost" .. tip("Auto-allow 127.0.0.1 and ::1. Required for Live Traffic stats.")).default =
"1"
s:taboption("advanced", Flag, "metrics_allow_lan", "Allow LAN Subnet" .. tip("Auto-detect and allow your router's local network.")).default =
"1"

local mwl = s:taboption("advanced", Value, "metrics_whitelist",
    "Additional Whitelist" .. tip("Optional. Comma separated CIDRs for external access.")); mwl.placeholder =
"e.g. 10.8.0.0/24"
function mwl.validate(self, v)
    if not v or v == "" then return v end
    for cidr in v:gmatch("([^,]+)") do
        cidr = cidr:gsub("^%s*(.-)%s*$", "%1")
        if not cidr:match("^[0-9a-fA-F%.:]+/%d+$") then return nil, "Invalid CIDR format! Use IP/Mask like 10.8.0.0/24" end
    end
    return v
end

local cur_m_port = tonumber(m.uci:get("telemt", "general", "metrics_port")) or 9092
local mlink = s:taboption("advanced", DummyValue, "_mlink",
    "Prometheus Endpoint" .. tip("Click to open in a new tab, or copy for Grafana.")); mlink.rawhtml = true
mlink.default = string.format(
    [[<a id="prom_link" href="#" target="_blank" class="telemt-prom-link" style="font-family: monospace; color: #00a000; padding: 4px; background: rgba(0,0,0,0.05); border-radius: 4px; text-decoration: none; border: 1px solid rgba(0,160,0,0.2);">http://&lt;router_ip&gt;:%d/metrics</a><script>setTimeout(function(){ var a = document.getElementById('prom_link'); if(a) { a.href = window.location.protocol + '//' + window.location.hostname + ':%d/metrics'; } }, 500);</script>]],
    cur_m_port, cur_m_port)

-- === TAB: TELEGRAM BOT ===
local hbot = s:taboption("bot", DummyValue, "_head_bot", ""); hbot.rawhtml = true; hbot.default =
"<div style='margin-bottom:15px; padding-top:10px;'><h3 style='margin-top:0;'>Autonomous Telegram Bot (Sidecar)</h3><p style='opacity:0.8; margin-top:5px; margin-bottom:0;'>Configure the autonomous local bot to monitor Telemt status, manage users via Telegram, and receive crash alerts. <a href='https://github.com/Medvedolog/telemt-bot' target='_blank' style='text-decoration:none; border-bottom:1px dotted;'>telemt-bot repo</a></p></div>"

s:taboption("bot", Flag, "bot_enabled", "Enable Bot Sidecar" .. tip("Start the autonomous monitoring script via procd.")).default =
"0"

local bt = s:taboption("bot", Value, "bot_token", "Bot Token" .. tip("Get it from @BotFather.")); bt.password = true; bt
    :depends("bot_enabled", "1")
function bt.validate(self, v)
    if v and v ~= "" and not v:match("^[0-9]+:[a-zA-Z0-9_%-]+$") then return nil, "Invalid Telegram Bot Token format!" end
    return v
end

local bc = s:taboption("bot", Value, "bot_chat_id", "Admin Chat ID" .. tip("Your personal or group Chat ID for alerts.")); bc
    :depends("bot_enabled", "1")
function bc.validate(self, v)
    if v and v ~= "" and not v:match("^%-?[0-9]+$") then return nil, "Invalid Chat ID! Must be a numeric ID." end
    return v
end

-- Bot Service Dashboard (status + controls)
local bot_dash = s:taboption("bot", DummyValue, "_bot_dashboard", "Bot Service"); bot_dash.rawhtml = true
bot_dash.default = string.format([[
<div id="telemt_bot_dash" style="font-family:monospace; background:rgba(128,128,128,0.05); border:1px solid rgba(128,128,128,0.2); border-radius:6px; padding:12px; line-height:1.8; margin-bottom:15px;">
    <div style="margin-bottom:4px;">
        <b>Service:</b> <span id="bot_dash_status" style="color:#888; font-weight:bold;">CHECKING...</span>
        &nbsp;<span id="bot_dash_pid" style="color:#666; font-size:0.9em;"></span>
    </div>
    <div style="margin-bottom:8px;">
        <b>Route:</b> <span id="bot_dash_route" style="font-weight:bold;">--</span>
        <span id="bot_dash_route_hint" style="font-size:0.8em; color:#888; margin-left:6px;"></span>
    </div>
    <div class="btn-controls" style="display:flex; gap:8px; flex-wrap:wrap;">
        <input type="button" class="cbi-button cbi-button-apply" id="btn_bot_start" value="Start Bot" />
        <input type="button" class="cbi-button cbi-button-reset" id="btn_bot_stop" value="Stop Bot" />
        <input type="button" class="cbi-button cbi-button-reload" id="btn_bot_restart" value="Restart Bot" />
    </div>
</div>
<script>
(function(){
    var lu_url = %q;
    var _botActionBusy = false;
    var _botPollTimer = null;

    function getToken() {
        var tok = null;
        var tn = document.querySelector('input[name="token"]');
        if (tn) tok = tn.value;
        else if (typeof L !== 'undefined' && L.env) tok = L.env.token || L.env.requesttoken || null;
        if (!tok) { var cm = document.cookie.match(/(?:sysauth_http|sysauth)=([^;]+)/); if (cm) tok = cm[1]; }
        return tok;
    }

    function postBotAction(action) {
        if (_botActionBusy) return;
        _botActionBusy = true;
        var labels = { start: 'STARTING\u2026', stop: 'STOPPING\u2026', restart: 'RESTARTING\u2026' };
        var stEl = document.getElementById('bot_dash_status');
        if (stEl && labels[action]) { stEl.innerText = labels[action]; stEl.style.color = '#d35400'; }
        ['start', 'stop', 'restart'].forEach(function(a) {
            var b = document.getElementById('btn_bot_' + a); if (b) { b.disabled = true; b.style.opacity = '0.5'; }
        });

        var f = new FormData(); f.append('bot_action', action);
        var tok = getToken(); if (tok) f.append('token', tok);

        fetch(lu_url.split('#')[0], { method: 'POST', body: f }).catch(function(err){ console.error("Bot action error:", err); });

        setTimeout(function() {
            _botActionBusy = false;
            ['start', 'stop', 'restart'].forEach(function(a) {
                var b = document.getElementById('btn_bot_' + a); if (b) { b.disabled = false; b.style.opacity = '1'; }
            });
            fetchBotStatus();
        }, 4000);
    }

    function fetchBotStatus() {
        var baseUrl = lu_url.split('#')[0];
        var sep = baseUrl.indexOf('?') > -1 ? '&' : '?';
        fetch(baseUrl + sep + 'get_bot_status=1&_t=' + Date.now())
        .then(function(r){ return r.json(); })
        .then(function(d){
            var stEl = document.getElementById('bot_dash_status');
            var pidEl = document.getElementById('bot_dash_pid');
            var routeEl = document.getElementById('bot_dash_route');
            var hintEl = document.getElementById('bot_dash_route_hint');

            if (d.running) {
                if (stEl) { stEl.innerText = 'RUNNING'; stEl.style.color = '#00a000'; }
                if (pidEl) pidEl.innerText = '(PID: ' + d.pid + ')';

                var routeColor = '#00a000';
                var routeText = d.route || 'unknown';
                var hint = '';
                if (routeText === 'socks') { routeColor = '#00a000'; hint = 'via SOCKS upstream'; }
                else if (routeText === 'direct') { routeColor = '#d35400'; hint = 'WAN direct / no SOCKS'; }
                else { routeColor = '#888'; hint = 'waiting for health check'; }
                if (routeEl) { routeEl.innerText = routeText.toUpperCase(); routeEl.style.color = routeColor; }
                if (hintEl) hintEl.innerText = hint;
            } else {
                if (stEl) { stEl.innerText = 'STOPPED'; stEl.style.color = '#d9534f'; }
                if (pidEl) pidEl.innerText = '';
                if (routeEl) { routeEl.innerText = '--'; routeEl.style.color = '#888'; }
                if (hintEl) hintEl.innerText = '';
            }
        })
        .catch(function(err){ console.error("Bot status fetch error:", err); });
    }

    setTimeout(function(){
        ['start', 'stop', 'restart'].forEach(function(act) {
            var btn = document.getElementById('btn_bot_' + act);
            if (btn && !btn.dataset.bound) {
                btn.dataset.bound = "1";
                btn.addEventListener('click', function(e){
                    e.preventDefault(); e.stopPropagation();
                    postBotAction(act);
                });
            }
        });
        fetchBotStatus();
        _botPollTimer = setInterval(fetchBotStatus, 10000);
    }, 500);

    document.addEventListener('visibilitychange', function(){
        if (document.hidden) { if (_botPollTimer) { clearInterval(_botPollTimer); _botPollTimer = null; } }
        else { fetchBotStatus(); if (!_botPollTimer) _botPollTimer = setInterval(fetchBotStatus, 10000); }
    });
})();
</script>]], safe_url)

-- === TAB: DIAGNOSTICS ===
local diag = s:taboption("log", DummyValue, "_diag")
diag.rawhtml = true
diag.default = [[
<div class="telemt-panel" style="display:block; width:100% !important; max-width:none !important; clear:both; box-sizing:border-box;">
    <div id="telemt_health_summary" style="margin-bottom:20px;">
        <h3 style="margin-top:0; border-bottom:2px solid var(--border-color, #ccc); padding-bottom:5px;">Health Summary</h3>

        <div style="display:flex; flex-wrap:wrap; gap:10px; margin-bottom:15px;" id="diag_gates">
            <span style="color:#888;">Fetching Runtime Status...</span>
        </div>

        <!-- Live connections counter (updated from Prometheus on each poll) -->
        <div id="diag_live_conns" style="margin-bottom:12px; padding:8px 12px; background:rgba(0,160,0,0.05); border:1px solid rgba(0,160,0,0.15); border-radius:5px; font-size:0.95em; display:none;"></div>

        <div style="display:flex; flex-wrap:wrap; gap:15px; width:100%;">
            <div style="flex:1 1 300px; background:rgba(128,128,128,0.03); border:1px solid rgba(128,128,128,0.2); border-radius:6px; padding:15px; box-sizing:border-box;">
                <h4 style="margin-top:0; color:#0069d6; border-bottom:1px dashed #ccc; padding-bottom:5px;">Upstreams Status</h4>
                <div id="diag_upstreams" style="max-height:250px; overflow-y:auto; overflow-x:hidden;">Loading...</div>
            </div>
            <div style="flex:1 1 300px; background:rgba(128,128,128,0.03); border:1px solid rgba(128,128,128,0.2); border-radius:6px; padding:15px; box-sizing:border-box;">
                <h4 id="diag_dcs_title" style="margin-top:0; color:#0069d6; border-bottom:1px dashed #ccc; padding-bottom:5px;">Datacenters</h4>
                <div id="diag_dcs" style="max-height:250px; overflow-y:auto; overflow-x:hidden;">Loading...</div>
            </div>
        </div>
    </div>

    <div class="telemt-dash-top-row" style="margin-top:20px; margin-bottom:15px; padding:15px; background:rgba(128,128,128,0.05); border:1px solid rgba(128,128,128,0.2); border-radius:6px; display:flex; justify-content:flex-start; align-items:center; flex-wrap:wrap; gap:15px;">
        <div style="font-weight:bold; font-size:1.1em; opacity:0.8; margin-right:15px;">Maintenance</div>
        <div style="display:flex; gap:10px; flex-wrap:wrap;">
            <input type="button" class="cbi-button cbi-button-action" id="btn_export_config" value="Export Active Config" style="background:#4a90e2; color:#fff; border:1px solid #357abd;" />
            <input type="button" class="cbi-button cbi-button-remove" id="btn_reset_config" value="Reset to defaults" />
        </div>
    </div>

    <div style="width:100%; box-sizing:border-box; height:350px; font-family:monospace; font-size:12px; padding:12px; background:#1e1e1e; color:#d4d4d4; border:1px solid #333; border-radius:4px; overflow-y:auto; overflow-x:auto; white-space:pre;" id="telemt_log_container">Click a button below to load data.</div>
    <div style="margin-top:10px; display:flex; gap:10px; flex-wrap:wrap;">
        <input type="button" class="cbi-button cbi-button-apply" id="btn_load_log" value="System Log" />
        <input type="button" class="cbi-button cbi-button-reset" id="btn_load_scanners" value="Show Active Scanners" />
        <input type="button" class="cbi-button cbi-button-neutral" id="btn_runtime_info" value="Runtime Info" />
        <input type="button" class="cbi-button cbi-button-action" id="btn_copy_log" value="Copy Output" />
    </div>
</div>

<script>
setTimeout(function(){
    document.getElementById('btn_load_log').addEventListener('click', loadLog);
    document.getElementById('btn_load_scanners').addEventListener('click', loadScanners);
    document.getElementById('btn_copy_log').addEventListener('click', function(){ copyLogContent(this); });
    var rtBtn = document.getElementById('btn_runtime_info');
    if (rtBtn) rtBtn.addEventListener('click', loadRuntimeInfo);

    document.getElementById('btn_export_config').addEventListener('click', function() {
        var fd = new FormData(); fd.append('export_config', '1');
        var tok = null; var tn = document.querySelector('input[name="token"]');
        if (tn) tok = tn.value; else if (typeof L !== 'undefined' && L.env) tok = L.env.token || L.env.requesttoken || null;
        if (!tok) { var cm = document.cookie.match(/(?:sysauth_http|sysauth)=([^;]+)/); if (cm) tok = cm[1]; }
        if (tok) fd.append('token', tok);
        fetch(lu_current_url.split('#')[0], {method: 'POST', body: fd}).then(r => r.text()).then(txt => {
            txt = cleanResponse(txt);
            var blob = new Blob([txt], {type: 'application/toml'});
            var a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'telemt.toml';
            document.body.appendChild(a); a.click(); document.body.removeChild(a);
        });
    });

    document.getElementById('btn_reset_config').addEventListener('click', function() {
        if(confirm('Are you sure you want to RESET ALL Telemt settings to defaults? This will completely erase all users, cascades, and custom settings!')) {
            var fd = new FormData(); fd.append('reset_config', '1');
            var tok = null; var tn = document.querySelector('input[name="token"]');
            if (tn) tok = tn.value; else if (typeof L !== 'undefined' && L.env) tok = L.env.token || L.env.requesttoken || null;
            if (!tok) { var cm = document.cookie.match(/(?:sysauth_http|sysauth)=([^;]+)/); if (cm) tok = cm[1]; }
            if (tok) fd.append('token', tok);
            fetch(lu_current_url.split('#')[0], {method: 'POST', body: fd}).then(() => { window.location.reload(); });
        }
    });
}, 500);
</script>
]]

-- === TAB: USERS ===
local anchor = s:taboption("users", DummyValue, "_users_anchor", ""); anchor.rawhtml = true; anchor.default =
'<div id="users_tab_anchor" style="display:none"></div>'
local myip_u = s:taboption("users", DummyValue, "_ip_display",
    "External IP / DynDNS" .. tip("IP address or domain used for generating tg:// links.")); myip_u.rawhtml = true; myip_u.default =
    string.format([[<input type="text" class="cbi-input-text" style="width:250px;" id="telemt_mirror_ip" value="%s">]],
        saved_ip)

s2 = m:section(TypedSection, "user", "")
s2.template = "cbi/tblsection"; s2.addremove = true; s2.anonymous = false
s2.create = function(self, section)
    if not section or not section:match("^[A-Za-z0-9_]+$") or #section > 15 then return nil end; sys.call(string.format(
        "logger -t telemt 'WebUI: Added new user -> %s'", section)); return TypedSection.create(self, section)
end
s2.remove = function(self, section)
    sys.call(string.format("logger -t telemt 'WebUI: Deleted user -> %s'", section)); return TypedSection.remove(self,
        section)
end

local sec = s2:option(Value, "secret", "Secret (32 hex)" .. tip("Leave empty to auto-generate.")); sec.rmempty = false; sec.datatype =
"hexstring"; function sec.validate(self, value)
    if not value or value:gsub("%s+", "") == "" then
        value = (sys.exec("cat /proc/sys/kernel/random/uuid") or ""):gsub(
            "%-", ""):gsub("%s+", ""):sub(1, 32)
    end; if #value ~= 32 or not value:match("^[0-9a-fA-F]+$") then
        return nil,
            "Secret must be exactly 32 hex chars!"
    end; return value
end

local u_en = s2:option(Flag, "enabled", "On" .. tip("Uncheck to manually pause this user.")); u_en.default = "1"; u_en.rmempty = false
local t_con = s2:option(Value, "max_tcp_conns", "TCP Conns" .. tip("Limit sessions (e.g. 50)")); t_con.datatype =
"uinteger"; t_con.placeholder = "unlimited"
function t_con.validate(self, v) if v and v ~= "" then local n = tonumber(v); if not n or n < 1 or n > 100000 then return nil, "1-100000 or empty" end end; return v end
local t_uips = s2:option(Value, "max_unique_ips", "Max IPs" .. tip("Max unique client IPs.")); t_uips.datatype =
"uinteger"; t_uips.placeholder = "unlimited"
function t_uips.validate(self, v) if v and v ~= "" then local n = tonumber(v); if not n or n < 1 or n > 1000 then return nil, "1-1000 or empty" end end; return v end
local t_qta = s2:option(Value, "data_quota", "Quota (GB)" .. tip("E.g. 1.5 or 0.5")); t_qta.datatype = "ufloat"; t_qta.placeholder =
"unlimited"
function t_qta.validate(self, v) if v and v ~= "" then local n = tonumber(v); if not n or n <= 0 or n > 999999 then return nil, "0.01-999999 GB or empty" end end; return v end
local t_exp = s2:option(Value, "expire_date", "Expire Date" .. tip("Format: DD.MM.YYYY HH:MM")); t_exp.datatype =
"string"; t_exp.placeholder = "DD.MM.YYYY HH:MM"; function t_exp.validate(self, value)
    if not value then return "" end
    value = value:match("^%s*(.-)%s*$"); if value == "" or value == "unlimited" then return "" end
    if not value:match("^%d%d%.%d%d%.%d%d%d%d %d%d:%d%d$") then return nil, "Format: DD.MM.YYYY HH:MM" end
    return value
end

local lst = s2:option(DummyValue, "_stat", "Status and Stats" .. tip("Accumulated usage & sessions")); lst.rawhtml = true
function lst.cfgvalue(self, section)
    local q = self.map:get(section, "data_quota") or ""; local e = self.map:get(section, "expire_date") or ""; local en =
        self.map:get(section, "enabled") or "1"
    return string.format(
        '<div class="user-flat-stat" data-user="%s" data-q="%s" data-e="%s" data-en="%s"><span style="color:#888;">No Data</span></div>',
        section:gsub("[<>&\"']", ""),
        q:gsub("[<>&\"']", ""), e:gsub("[<>&\"']", ""), en:gsub("[<>&\"']", ""))
end

local lnk = s2:option(DummyValue, "_link", "Ready-to-use link" .. tip("Click the link to copy it.")); lnk.rawhtml = true; function lnk.cfgvalue(
    self, section)
    return
    [[<div class="link-wrapper"><input type="text" class="cbi-input-text user-link-out" readonly onclick="this.select()"></div>]]
end

m.description = [[
<style>
.cbi-value-helpicon, img[src*="help.gif"], img[src*="help.png"], .cbi-tooltip-container, .cbi-tooltip { display: none !important; }
.cbi-value-description::before, .cbi-value-description img { display: none !important; content: none !important; margin: 0 !important; padding: 0 !important; width: 0 !important; height: 0 !important; }
#cbi-telemt-user .cbi-section-table-descr { display: none !important; width: 0 !important; height: 0 !important; visibility: hidden !important; }
#cbi-telemt-user .cbi-row-template, #cbi-telemt-user [id*="-template"] { display: none !important; visibility: hidden !important; height: 0 !important; overflow: hidden !important; pointer-events: none !important; }
html body #cbi-telemt-user .cbi-button-add, html body #cbi-telemt-upstream .cbi-button-add { color: #00a000 !important; background-color: transparent !important; border: 1px solid #00a000 !important; transition: all 0.2s ease !important; padding: 0 16px !important; height: 32px !important; line-height: 30px !important; border-radius: 4px !important; font-weight: bold !important; }
html body #cbi-telemt-user .cbi-button-add:hover, html body #cbi-telemt-upstream .cbi-button-add:hover,
html body #cbi-telemt-user input.cbi-button-add:hover, html body #cbi-telemt-upstream input.cbi-button-add:hover,
html body #cbi-telemt-user input[type="submit"].cbi-button-add:hover, html body #cbi-telemt-upstream input[type="submit"].cbi-button-add:hover,
html body #cbi-telemt-user .cbi-button-add:focus, html body #cbi-telemt-upstream .cbi-button-add:focus {
    background-color: #00a000 !important; background-image: none !important; color: #ffffff !important;
    -webkit-text-fill-color: #ffffff !important; text-shadow: 0 0 0 #ffffff !important;
    opacity: 1 !important; border-color: #00a000 !important;
}
#cbi-telemt-user .cbi-section-table td:first-child { vertical-align: middle !important; }
#cbi-telemt-upstream .cbi-section-node-row, #cbi-telemt-upstream > div:not([id$="-template"]) { display: flex !important; flex-direction: column !important; background: rgba(128,128,128,0.03) !important; border: 1px solid var(--border-color, rgba(128,128,128,0.2)) !important; border-radius: 8px !important; padding: 15px !important; margin-bottom: 20px !important; transition: all 0.3s ease; }
#cbi-telemt-upstream > div:not([id$="-template"]) > .cbi-section-remove, #cbi-telemt-upstream .cbi-section-node > .cbi-section-remove { order: 99 !important; align-self: flex-start !important; margin-top: 15px !important; padding-top: 15px !important; border-top: 1px dashed var(--border-color, rgba(128,128,128,0.3)) !important; width: 100% !important; text-align: left !important; }
html body #cbi-telemt-upstream .cbi-button-remove { display: inline-block !important; float: left !important; margin: 0 !important; color: #d9534f !important; background-color: transparent !important; border: 1px solid #d9534f !important; padding: 0 12px !important; height: 30px !important; line-height: 28px !important; font-weight: normal !important; transition: all 0.2s ease !important; }
html body #cbi-telemt-upstream .cbi-button-remove:hover { background-color: #d9534f !important; color: #ffffff !important; -webkit-text-fill-color: #ffffff !important; }
div[id^="cbi-telemt-advanced-_head_adv"] .cbi-value-title, div[id^="cbi-telemt-advanced-_head_tm"] .cbi-value-title, div[id^="cbi-telemt-advanced-_head_me_adv"] .cbi-value-title { display: none !important; }
div[id^="cbi-telemt-advanced-_head_adv"] .cbi-value-field, div[id^="cbi-telemt-advanced-_head_tm"] .cbi-value-field, div[id^="cbi-telemt-advanced-_head_me_adv"] .cbi-value-field { width: 100% !important; padding: 0 !important; margin: 0 !important; float: none !important; }
.cbi-value-description { margin: -8px 0 0 0 !important; padding: 0 !important; font-size: 0.85em !important; opacity: 0.8; white-space: normal !important; }
.telemt-tip { display: inline-block !important; vertical-align: middle !important; white-space: nowrap !important; cursor: help !important; opacity: 0.5 !important; font-size: 0.85em !important; border-bottom: 1px dotted currentColor !important; margin-left: 4px !important; margin-top: -2px !important; }
#cbi-telemt-user .cbi-section-table th { white-space: nowrap !important; vertical-align: middle !important; }
#cbi-telemt-user .cbi-section-table { table-layout: auto !important; }
[data-name="external_ip"] .cbi-value-field, #cbi-telemt-general-external_ip .cbi-value-field { display: flex !important; align-items: center !important; }
#telemt_mirror_ip, input[name*="cbid.telemt.general.external_ip"] { flex: 0 1 250px !important; width: 250px !important; max-width: 250px !important; box-sizing: border-box !important; }
.telemt-sec-wrap { display: flex; flex-direction: column; width: 100%; position: relative; gap: 4px; }
.telemt-sec-btns { display: flex; }
.telemt-sec-btns input.cbi-button, .link-btn-group input.cbi-button { flex: 1; height: 20px !important; min-height: 20px !important; line-height: 18px !important; padding: 0 8px !important; font-size: 11px !important; margin-right: 4px; }
.telemt-sec-btns input:last-child { margin-right: 0; }
.telemt-num-wrap { display: flex !important; align-items: center !important; width: 100% !important; box-sizing: border-box !important; gap: 4px; height: 32px; }
.telemt-num-wrap > input:not([type="button"]) { flex: 1 1 auto !important; width: 100% !important; min-width: 40px !important; box-sizing: border-box !important; margin: 0 !important; height: 100% !important; }
.telemt-btn-cross { flex: 0 0 24px !important; width: 24px !important; min-width: 24px !important; height: 24px !important; min-height: 24px !important; padding: 0 !important; margin: 0 !important; cursor: pointer !important; background-color: transparent !important; background-image: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23666666' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cline x1='18' y1='6' x2='6' y2='18'/%3E%3Cline x1='6' y1='6' x2='18' y2='18'/%3E%3C/svg%3E") !important; background-repeat: no-repeat !important; background-position: center !important; background-size: 14px !important; border: none !important; box-shadow: none !important; opacity: 1 !important; transition: all 0.2s ease !important; }
.telemt-btn-cross:hover { background-color: rgba(217, 83, 79, 0.1) !important; border-radius: 4px; background-image: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23d9534f' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cline x1='18' y1='6' x2='6' y2='18'/%3E%3Cline x1='6' y1='6' x2='18' y2='18'/%3E%3C/svg%3E") !important; }
.telemt-cal-wrap { position: relative; display: flex; flex: 0 0 24px; width: 24px; height: 24px; margin: 0; }
.telemt-btn-cal { width: 100% !important; height: 100% !important; padding: 0 !important; margin: 0 !important; cursor: pointer !important; background-color: transparent !important; background-image: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23666666' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Crect x='3' y='4' width='18' height='18' rx='2' ry='2'/%3E%3Cline x1='16' y1='2' x2='16' y2='6'/%3E%3Cline x1='8' y1='2' x2='8' y2='6'/%3E%3Cline x1='3' y1='10' x2='21' y2='10'/%3E%3C/svg%3E") !important; background-repeat: no-repeat !important; background-position: center !important; background-size: 14px !important; border: none !important; }
.telemt-cal-wrap:hover .telemt-btn-cal { background-color: rgba(0, 160, 0, 0.1) !important; border-radius: 4px; background-image: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2300a000' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Crect x='3' y='4' width='18' height='18' rx='2' ry='2'/%3E%3Cline x1='16' y1='2' x2='16' y2='6'/%3E%3Cline x1='8' y1='2' x2='8' y2='6'/%3E%3Cline x1='3' y1='10' x2='21' y2='10'/%3E%3C/svg%3E") !important; }
.telemt-cal-picker { position: absolute; top: 0; left: 0; width: 100%; height: 100%; opacity: 0; cursor: pointer; color-scheme: light dark; z-index:2; }
@media (prefers-color-scheme: dark) { .telemt-btn-cross { background-image: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23cccccc' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cline x1='18' y1='6' x2='6' y2='18'/%3E%3Cline x1='6' y1='6' x2='18' y2='18'/%3E%3C/svg%3E") !important; } .telemt-btn-cal { background-image: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23cccccc' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Crect x='3' y='4' width='18' height='18' rx='2' ry='2'/%3E%3Cline x1='16' y1='2' x2='16' y2='6'/%3E%3Cline x1='8' y1='2' x2='8' y2='6'/%3E%3Cline x1='3' y1='10' x2='21' y2='10'/%3E%3C/svg%3E") !important; } }
#cbi-telemt-user .user-link-out { height: 32px !important; line-height: 32px !important; width: 100%; font-family: monospace; font-size: 11px; background: transparent !important; color: inherit !important; border: 1px solid var(--border-color, rgba(128,128,128,0.5)) !important; box-sizing: border-box; margin: 0; cursor: pointer; }
.user-link-err { color: #d9534f !important; font-weight: bold; border-color: #d9534f !important; }
.user-flat-stat { display: flex; flex-wrap: wrap; align-items: center; line-height: 1.4; font-size: 0.95em; }
.user-flat-stat > * { margin-right: 4px; }
.user-flat-stat > *:last-child { margin-right: 0; }
.stat-divider, .sum-divider { color: #ccc; margin: 0 4px; }
.sum-row { display: inline; }
.sum-row::after { content: ' | '; color: #ccc; }
.sum-row:last-child::after { content: ''; }
.telemt-dash-summary { line-height: 1.6; }
.btn-controls input { width: auto; margin-right: 5px; }
.link-btn-group { display: flex; margin-top: 4px; }
.telemt-conns-bold { font-weight: bold; }

@media screen and (min-width: 769px) { #cbi-telemt-user .cbi-section-table { width: 100% !important; table-layout: auto !important; } #cbi-telemt-user .cbi-section-table td { padding: 6px 8px !important; white-space: nowrap !important; vertical-align: middle !important; } .user-flat-stat, .user-flat-stat > div { flex-wrap: nowrap !important; white-space: nowrap !important; } td[data-name="_stat"] { min-width: 180px !important; } td[data-name="max_tcp_conns"] .telemt-num-wrap, td[data-name="max_unique_ips"] .telemt-num-wrap, td[data-name="data_quota"] .telemt-num-wrap { max-width: 95px !important; } td[data-name="expire_date"] { min-width: 155px !important; } td[data-name="expire_date"] .telemt-num-wrap { min-width: 155px !important; width: 100% !important; } td[data-name="_link"] .link-wrapper { min-width: 160px !important; } td[data-name="secret"] .telemt-sec-wrap { min-width: 160px !important; } .telemt-action-btns { display: flex !important; align-items: center !important; justify-content: flex-start !important; gap: 10px !important; flex-wrap: wrap; padding: 10px 12px; background: rgba(128,128,128,0.04); border: 1px solid rgba(128,128,128,0.15); border-radius: 6px; margin-bottom: 15px; } .telemt-action-btns input.cbi-button { float: none !important; margin: 0 !important; display: inline-block !important; position: static !important; } .telemt-dash-top-row { display:flex; align-items:center; padding:12px; background:rgba(0,160,0,0.05); border:1px solid rgba(0,160,0,0.2); border-radius:6px; margin-bottom:10px; flex-wrap:wrap; gap:15px; } .telemt-dash-bot-row { display:flex; flex-direction:column; justify-content:center; align-items:center; gap:10px; margin-bottom:15px; text-align:center; width:100%; } .telemt-dash-warn { font-size:1em; color:#d35400; font-weight:bold; text-align:center; } }
@media screen and (max-width: 768px) { #telemt_mirror_ip, input[name*="cbid.telemt.general.external_ip"] { flex: 1 1 100% !important; width: 100% !important; max-width: 100% !important; } #cbi-telemt-user .cbi-section-table .cbi-section-table-row { display: flex !important; flex-direction: column !important; margin-bottom: 15px !important; border: 1px solid var(--border-color, #ddd) !important; padding: 10px !important; border-radius: 6px !important; } #cbi-telemt-user .cbi-section-table td { display: block !important; width: 100% !important; box-sizing: border-box !important; padding: 6px 0 !important; border: none !important; white-space: normal !important; } #cbi-telemt-user .cbi-section-table td[data-title]::before { content: attr(data-title) !important; display: block !important; font-weight: bold !important; margin-bottom: 4px !important; color: var(--text-color, #555) !important; } #cbi-telemt-user .cbi-section-actions .cbi-button::before, #cbi-telemt-user td .cbi-button::before { display: none !important; content: none !important; } #cbi-telemt-user .cbi-section-actions, #cbi-telemt-user td.cbi-section-actions, #cbi-telemt-user .cbi-section-table td:last-child { display: block !important; visibility: visible !important; opacity: 1 !important; padding: 10px 0 0 0 !important; overflow: visible !important; width: 100% !important; } html body #cbi-telemt-user .cbi-section-actions .cbi-button-remove:not(.telemt-btn-cross), html body #cbi-telemt-user td.cbi-section-actions .cbi-button-remove:not(.telemt-btn-cross) { display: flex !important; width: 100% !important; height: 44px !important; line-height: 44px !important; align-items: center !important; justify-content: center !important; } .user-flat-stat, .user-flat-stat > div { flex-direction: column; align-items: flex-start; flex-wrap: wrap !important; } .stat-divider, .sum-divider { display: none !important; } .sum-row { display: block !important; padding: 1px 0; } .sum-row::after { display: none !important; } .telemt-dash-summary { line-height: 1.8 !important; font-size: 0.92em !important; } .telemt-dash-btns, .telemt-action-btns { flex-direction: row; flex-wrap: wrap; width: 100%; gap: 8px !important; margin-top:0; padding: 10px; background: rgba(128,128,128,0.04); border: 1px solid rgba(128,128,128,0.15); border-radius: 6px; margin-bottom: 15px; box-sizing: border-box; } .telemt-dash-btns input.cbi-button, .telemt-action-btns input.cbi-button { flex: 1 1 calc(50% - 4px) !important; height: 36px !important; } .link-btn-group { flex-direction: row !important; width: 100%; display: flex; margin-top: 5px; } .telemt-sec-btns input.cbi-button, .link-btn-group input.cbi-button { height: 32px !important; min-height: 32px !important; line-height: 30px !important; font-size: 13px !important; margin-right: 5px; } .telemt-dash-top-row { display:flex; padding:12px; background:rgba(0,160,0,0.05); border:1px solid rgba(0,160,0,0.2); border-radius:6px; margin-bottom:10px; } .telemt-dash-bot-row { display:flex; flex-direction:column; margin-bottom:15px; gap:15px; text-align:center; } }
.qr-modal-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 2147483647 !important; display: flex; align-items: center; justify-content: center; opacity: 0; pointer-events: none; transition: opacity 0.2s; }
.qr-modal-overlay.active { opacity: 1; pointer-events: auto; }
.custom-modal-content { background-color: #1e1e1e !important; color: #dddddd !important; padding: 20px; border-radius: 8px; box-shadow: 0 10px 30px rgba(0,0,0,0.8); border: 1px solid #444 !important; text-align: center; max-width: 450px; width: 90%; }
.custom-modal-content p, .custom-modal-content h3, .custom-modal-content label, .custom-modal-content span { color: #dddddd !important; }
.custom-modal-content svg { max-width: 100%; height: auto; display: block; margin: 0 auto; }
#csv_text_area { background-color: #121212 !important; color: #00ff00 !important; width: 100%; height: 120px; font-family: monospace; font-size: 11px; margin-bottom: 10px; box-sizing: border-box; padding: 5px; resize: vertical; border: 1px solid #555 !important; }
.badge { display:inline-block; padding:4px 8px; border-radius:4px; font-weight:bold; font-size:0.85em; text-transform:uppercase; margin-right:5px; margin-bottom:5px; }
.badge-ok { background:rgba(0,160,0,0.1); color:#00a000; border:1px solid rgba(0,160,0,0.3); }
.badge-err { background:rgba(217,83,79,0.1); color:#d9534f; border:1px solid rgba(217,83,79,0.3); }
.badge-gray { background:rgba(128,128,128,0.1); color:#888; border:1px solid rgba(128,128,128,0.3); }
.badge-info { background:rgba(0,105,214,0.1); color:#0069d6; border:1px solid rgba(0,105,214,0.3); }
.badge-warn { background:rgba(240,173,78,0.15); color:#b07d00; border:1px solid rgba(240,173,78,0.4); }
#cbi-telemt-log-_diag .cbi-value-title { display: none !important; }
#cbi-telemt-log-_diag .cbi-value-field { width: 100% !important; padding: 0 !important; margin: 0 !important; float: none !important; }
</style>

<script type="text/javascript">
var lu_current_url = "]] .. safe_url .. [[";
var is_owrt25 = ]] .. is_owrt25_lua .. [[;

function logAction(msg, data) { console.log("[Telemt UI] " + msg); }
function escHTML(s) { return String(s).replace(/[&<>'"]/g, function(c) { return '&#' + c.charCodeAt(0) + ';'; }); }
function formatMB(bytes) { if(!bytes || bytes === 0) return '0.00 MB'; var mb = bytes / 1048576; if (mb >= 1024) return (mb / 1024).toFixed(2) + ' GB'; return mb.toFixed(2) + ' MB'; }
function formatUptime(secs) { if(!secs) return '0s'; var d = Math.floor(secs/86400), h = Math.floor((secs%86400)/3600), m = Math.floor((secs%3600)/60), s = Math.floor(secs%60); var str = ""; if(d>0) str += d+"d "; if(h>0 || d>0) str += h+"h "; str += m+"m "+s+"s"; return str; }

// ONLY use cleanResponse for Prometheus parsing. Log content bypasses this to preserve HTTP artifacts.
function cleanResponse(txt) { if (!txt) return ''; var cut = txt.search(/<(!DOCTYPE|html[\s>])/i); if (cut > 0) return txt.substring(0, cut).trim(); return txt; }

// -----------------------------------------------------------------------------
// DEBOUNCED SPOILER REPACKER
// -----------------------------------------------------------------------------
var isRepacking = false;
var repackTimer = null;

function repackAllSpoilers() {
    isRepacking = true;
    var spoilerMaps = {
        // Only fields that are actually written to TOML by init.d are listed here.
        'telemt_me_opts_details': ['me_warm_standby', 'hardswap', 'me_drain_ttl', 'auto_degradation', 'degradation_min_dc'],
        'telemt_adv_opts_details': ['desync_all_full', 'mask_port', 'mask_host', 'mask_proxy_protocol', 'announce_ip', 'ad_tag', 'fake_cert_len', 'tls_full_cert_ttl_secs', 'ignore_time_skew'],
        'telemt_timeouts_details': ['tm_handshake', 'tm_connect', 'tm_keepalive', 'tm_ack', 'replay_window_secs']
    };

    for (var detailsId in spoilerMaps) {
        var detailsNode = document.getElementById(detailsId);
        if (!detailsNode) continue;
        spoilerMaps[detailsId].forEach(function(fieldName) {
            var el = document.querySelector('.cbi-value[data-name="' + fieldName + '"]') || document.getElementById('cbi-telemt-general-' + fieldName) || document.querySelector('[id$="-' + fieldName + '"]');
            if (el && el.parentNode !== detailsNode) { el.style.paddingLeft = '15px'; detailsNode.appendChild(el); }
        });
    }
    setTimeout(function() { isRepacking = false; }, 50);
}

function scheduleRepack() {
    if (isRepacking) return;
    if (repackTimer) clearTimeout(repackTimer);
    repackTimer = setTimeout(repackAllSpoilers, 80);
}

document.addEventListener('change', function(e) {
    if (e.target && (e.target.name && (e.target.name.indexOf('use_middle_proxy') > -1 || e.target.name.indexOf('me_floor_mode') > -1 || e.target.name.indexOf('auto_degradation') > -1))) {
        scheduleRepack();
    }
});

function updateCascadesState() {
    var upRows = document.querySelectorAll('#cbi-telemt-upstream .cbi-section-node:not([id*="-template"])');
    var masterSwitch = document.querySelector('input[type="checkbox"][name*="enable_upstreams"]');
    if (masterSwitch) {
        if (upRows.length === 0) { masterSwitch.disabled = true; masterSwitch.checked = false; masterSwitch.title = "No cascades configured"; }
        else { masterSwitch.disabled = false; masterSwitch.title = ""; }
        upRows.forEach(function(row) {
            if (!masterSwitch.checked) { row.style.opacity = '0.4'; row.style.filter = 'grayscale(1)'; row.style.pointerEvents = 'none'; }
            else { row.style.opacity = '1'; row.style.filter = ''; row.style.pointerEvents = 'auto'; }
        });
        if (!masterSwitch.dataset.injected) { masterSwitch.dataset.injected = "1"; masterSwitch.addEventListener('change', updateCascadesState); }
    }
}

// Inject runtime health badges into Upstream Proxies tab rows
function renderUpstreamBadges(upData) {
    if (!upData || !upData.ok || !upData.data || !Array.isArray(upData.data.upstreams)) return;
    var ups = upData.data.upstreams;
    // Build address -> status lookup
    var lookup = {};
    for (var i = 0; i < ups.length; i++) {
        if (ups[i].address) lookup[ups[i].address] = ups[i];
    }
    // Find upstream config rows and inject badges
    var rows = document.querySelectorAll('#cbi-telemt-upstream .cbi-section-node:not([id*="-template"])');
    rows.forEach(function(row) {
        var addrInput = row.querySelector('input[name*="address"]');
        if (!addrInput) return;
        var addr = addrInput.value.trim();
        var info = lookup[addr];
        // Remove old badge if exists
        var old = row.querySelector('.up-health-badge');
        if (old) old.remove();
        if (!info) return;
        var badge = document.createElement('div');
        badge.className = 'up-health-badge';
        badge.style.cssText = 'margin:4px 0 8px 0;padding:5px 10px;border-radius:4px;font-size:0.85em;background:rgba(128,128,128,0.05);border:1px solid rgba(128,128,128,0.15);';
        var hIcon = info.healthy ? '<span style="color:#00a000;">&#10003; healthy</span>' : '<span style="color:#d9534f;">&#10007; unhealthy</span>';
        var latStr = (info.effective_latency_ms != null) ? parseFloat(info.effective_latency_ms).toFixed(1) + 'ms' : '—';
        badge.innerHTML = hIcon + ' &nbsp;|&nbsp; fails: ' + (info.fails || 0) + ' &nbsp;|&nbsp; lat: ' + latStr;
        // Insert BEFORE the first field — positions badge right under the cascade title
        var firstVal = row.querySelector('.cbi-value');
        if (firstVal) firstVal.parentNode.insertBefore(badge, firstVal);
        else row.appendChild(badge);
    });
}

function setOfflineState() {
    var sEl = document.getElementById('dash_status'); if(sEl) { sEl.innerText = 'STOPPED'; sEl.style.color = '#d9534f'; }
    var rEl = document.getElementById('dash_rss'); if(rEl) { rEl.innerText = '0 MB'; rEl.style.color = '#888'; }
    // Don't blank user stats — fetchMetrics renders grayed-out accumulated data per user.

    var sumEl = document.getElementById('telemt_users_summary_inner');
    if (sumEl) sumEl.innerHTML = "<span style='color:#d9534f; font-weight:bold;'>Status: Daemon Stopped</span>";

    var dg = document.getElementById('diag_gates');
    if(dg) dg.innerHTML = '<span class="badge badge-err">Daemon Stopped</span>';
    var dUp = document.getElementById('diag_upstreams'), dDc = document.getElementById('diag_dcs');
    if(dUp) dUp.innerHTML = '<span style="opacity:0.6">Offline</span>';
    if(dDc) dDc.innerHTML = '<span style="opacity:0.6">Offline</span>';
    var liveEl = document.getElementById('diag_live_conns');
    if(liveEl) liveEl.style.display = 'none';

    window._telemtLastTime = 0;
    window._telemtLastTotalRx = 0;
    window._telemtLastTotalTx = 0;
}

// FIX: Unified Universal API Parser for both Users Summary and Health Grid
function parseApiResponse(apiData) {
    var result = { ok: false, runtime: null, stats: null, reason: '' };
    if (!apiData || typeof apiData !== 'object') return result;

    if (apiData.runtime || apiData.stats) {
        result.ok = true;
        result.runtime = apiData.runtime || {};
        result.stats = apiData.stats || {};
    } else if (apiData.ok && apiData.data) {
        result.ok = true;
        result.reason = apiData.data.reason || '';
        result.stats = apiData.data.data || {};
        var meW = result.stats.me_writers || {};
        result.runtime = {
            route_mode: meW.middle_proxy_enabled ? 'middle' : 'direct',
            me_runtime_ready: !!meW.middle_proxy_enabled,
            me2dc_fallback_enabled: !!(result.stats.fallback_active || meW.fallback_enabled),
            reroute_active: !!(result.stats.reroute_active),
            accepting_new_connections: !!apiData.data.enabled
        };
    }
    return result;
}

function renderHealthGrid(apiData, promText, upData, upqData) {
    var dg = document.getElementById('diag_gates');
    var dUp = document.getElementById('diag_upstreams');
    var dDc = document.getElementById('diag_dcs');

    var probesMatch = promText.match(/telemt_desync_total\s+([0-9\.]+)/);
    var probes = probesMatch ? parseInt(probesMatch[1], 10) : 0;

    var badMatch1 = promText.match(/telemt_connections_bad_total\s+([0-9\.]+)/);
    var badMatch2 = promText.match(/telemt_me_handshake_reject_total\s+([0-9\.]+)/);
    var scans = (badMatch1 ? parseInt(badMatch1[1], 10) : 0) + (badMatch2 ? parseInt(badMatch2[1], 10) : 0);

    var upActiveMatch  = promText.match(/telemt_user_connections_current\{/g);
    var upFailMatch    = promText.match(/telemt_upstream_connect_fail_total\s+([0-9\.]+)/);
    var upAttemptMatch = promText.match(/telemt_upstream_connect_attempt_total\s+([0-9\.]+)/);
    var upSuccessMatch = promText.match(/telemt_upstream_connect_success_total\s+([0-9\.]+)/);
    var _upAttempts   = upAttemptMatch ? parseInt(upAttemptMatch[1], 10) : 0;
    var _upSuccesses  = upSuccessMatch ? parseInt(upSuccessMatch[1], 10) : 0;
    var _upFails      = upFailMatch ? parseInt(upFailMatch[1], 10) : 0;
    var _upSuccessRate = (_upAttempts > 0) ? Math.round(_upSuccesses / _upAttempts * 100) + '%' : null;

    // DPI and rejection badges
    var promBadges =
        '<span class="badge ' + (probes > 0 ? 'badge-err' : 'badge-gray') + '" title="DPI traffic tampering events (crypto desync). 0 means ISP is not modifying encrypted streams.">DPI Tamper: ' + probes + '</span>' +
        '<span class="badge ' + (scans > 0 ? 'badge-err' : 'badge-gray') + '" title="Total rejected connections: port scanners, bots, invalid handshakes, bad keys.">Rejected: ' + scans + '</span>';

    // Live connections counter + active users + unique IPs (from Prometheus)
    var liveEl = document.getElementById('diag_live_conns');
    if (liveEl) {
        var ccMatch = promText.match(/^telemt_connections_current\s+([0-9\.]+)/m);
        var cdMatch = promText.match(/^telemt_connections_direct_current\s+([0-9\.]+)/m);
        var cmMatch = promText.match(/^telemt_connections_me_current\s+([0-9\.]+)/m);
        var cc = ccMatch ? parseInt(ccMatch[1], 10) : 0;
        var cd = cdMatch ? parseInt(cdMatch[1], 10) : 0;
        var cm = cmMatch ? parseInt(cmMatch[1], 10) : 0;
        // Count active users (conns > 0) and total unique IPs from per-user Prometheus gauges
        var _activeUsers = 0, _totalIPs = 0;
        var _ucRe = /telemt_user_connections_current\{[^}]*\}\s+([0-9\.]+)/g;
        var _uiRe = /telemt_user_unique_ips_current\{[^}]*\}\s+([0-9\.]+)/g;
        var _ucM; while ((_ucM = _ucRe.exec(promText)) !== null) { if (parseInt(_ucM[1], 10) > 0) _activeUsers++; }
        var _uiM; while ((_uiM = _uiRe.exec(promText)) !== null) { _totalIPs += parseInt(_uiM[1], 10); }
        if (cc > 0 || promText.indexOf('telemt_connections_current') > -1) {
            var liveStr = '<b>Live connections:</b> <span style="font-size:1.1em;font-weight:bold;color:#00a000;">' + cc + '</span>';
            if (cm > 0) liveStr += ' &nbsp;(direct: ' + cd + ', ME: ' + cm + ')';
            liveStr += ' &nbsp;<b style="opacity:0.7;">|</b>&nbsp; <b>Users online:</b> ' + _activeUsers;
            if (_totalIPs > 0) liveStr += ' &nbsp;<b style="opacity:0.7;">|</b>&nbsp; <b>Unique IPs:</b> ' + _totalIPs;
            liveEl.innerHTML = liveStr;
            liveEl.style.display = '';
        } else {
            liveEl.style.display = 'none';
        }
    }

    var parsed = parseApiResponse(apiData);
    var rt = parsed.runtime;
    var st = parsed.stats;
    var apiOk = parsed.ok;

    // Compute egress type from UCI upstream config (passed through metrics)
    var _uciUseMp = promText.match(/# telemt_uci_use_mp=(\d)/);
    var uciMpEnabled = _uciUseMp ? (_uciUseMp[1] === '1') : false;
    var _uciUpTypes = promText.match(/# telemt_uci_upstream_types=([^\n]*)/);
    var uciUpstreamTypes = _uciUpTypes ? _uciUpTypes[1].split(',').filter(function(t) { return t; }) : [];

    function computeEgress(upData) {
        // Primary source: UCI types (always available via metrics pass-through)
        var total = uciUpstreamTypes.length;
        if (total === 0) return { type: 'Direct', ok: 0, total: 0 };
        var types = {};
        uciUpstreamTypes.forEach(function(t) { types[t] = true; });
        var keys = Object.keys(types);
        var label = keys.length > 1 ? 'Mixed' : (keys[0] || 'direct');
        // Normalize
        if (label === 'socks5') label = 'SOCKS5';
        else if (label === 'socks4') label = 'SOCKS4';
        else if (label === 'direct') label = 'Direct';
        // Get health from API if available
        var ups = (upData && upData.ok && upData.data && Array.isArray(upData.data.upstreams)) ? upData.data.upstreams : [];
        var healthy = ups.length > 0 ? ups.filter(function(u) { return u && u.healthy; }).length : total;
        return { type: label, ok: healthy, total: Math.max(total, ups.length) };
    }

    if (!apiOk || !rt) {
        var hasAnyProm = promText.indexOf('telemt_') > -1;
        var uptimeM = promText.match(/telemt_uptime_seconds\s+([0-9\.]+)/);
        var connM   = promText.match(/telemt_connections_total\s+([0-9\.]+)/);
        var uptimeTxt = uptimeM ? ' &nbsp;<b>Uptime:</b> ' + formatUptime(parseFloat(uptimeM[1])) : '';
        var connTxt   = connM   ? ' &nbsp;<b>Total conns:</b> ' + parseInt(connM[1], 10) : '';
        var apiMsg = hasAnyProm
            ? '<span class="badge badge-gray" title="Control API is disabled or not responding. Prometheus metrics are shown.">API: Off</span>'
            : '<span class="badge badge-err" title="No telemt metrics received. Daemon may be stopped or in early boot.">No Metrics</span>';
        var promSummary = hasAnyProm
            ? '<div style="margin-top:8px; font-size:0.9em; opacity:0.8;">' + uptimeTxt + connTxt +
              ' &nbsp;<b>Connects:</b> ' + _upSuccesses +
              ' &nbsp;<b>Fails:</b> ' + _upFails +
              (_upSuccessRate ? ' &nbsp;<b>Success:</b> ' + _upSuccessRate : '') + '</div>'
            : '';
        if(dg) dg.innerHTML = apiMsg + promBadges + promSummary;
        if(dUp) dUp.innerHTML = '<div style="opacity:0.7; padding:10px;">Upstream table requires Control API.<br><br>' +
            '<b>Connects:</b> ' + _upSuccesses + ' &nbsp;|&nbsp; <b>Fails:</b> ' + _upFails +
            (_upSuccessRate ? ' &nbsp;|&nbsp; <b>Success:</b> ' + _upSuccessRate : '') +
            (_upAttempts > 0 ? ' &nbsp;(' + _upSuccesses + '/' + _upAttempts + ')' : '') +
            '</div>';
        if(dDc) dDc.innerHTML = '<div style="opacity:0.7; padding:10px;">Runtime details require Control API.</div>';
        return;
    }

    // Compute runtime view
    var mode = rt.route_mode || 'direct';
    var _meWr = (st && st.me_writers && Array.isArray(st.me_writers.writers)) ? st.me_writers.writers : [];
    var _hasDegraded = _meWr.some(function(w){ return w && w.degraded; });
    var egress = computeEgress(upData);

    // TG PATH badge
    var tgPath, tgPathCls;
    if (rt.me_runtime_ready) { tgPath = 'ME'; tgPathCls = 'badge-ok'; }
    else if (uciMpEnabled && !rt.me_runtime_ready) { tgPath = 'Fallback'; tgPathCls = 'badge-warn'; }
    else { tgPath = 'Direct-DC'; tgPathCls = 'badge-info'; }
    var tgPathBadge = '<span class="badge ' + tgPathCls + '" title="Telegram transport path: how traffic reaches Telegram DCs. ME = Middle-End pool, Direct-DC = TCP to DC, Fallback = ME configured but not ready.">TG Path: ' + tgPath + '</span>';

    // EGRESS badge
    var egressCls = egress.type === 'Direct' ? 'badge-info' : 'badge-ok';
    var egressBadge = '<span class="badge ' + egressCls + '" title="Outbound egress method from proxy to Internet. Direct = no upstream proxy, SOCKS4/5 = via upstream.">Egress: ' + egress.type + '</span>';

    // Accepting badge
    var acc = rt.accepting_new_connections
        ? '<span class="badge badge-ok" title="Proxy is accepting new client connections normally.">Accepting</span>'
        : '<span class="badge badge-err" title="Proxy is NOT accepting new connections! Check logs.">Rejecting!</span>';

    // ME badge
    var meRdy = rt.me_runtime_ready
        ? '<span class="badge badge-ok" title="Middle-End proxy pool active. Media/CDN routes through ME.">ME: Ready</span>'
        : '<span class="badge badge-gray" title="Middle-End disabled. Traffic goes directly to DCs.">ME: Off</span>';

    // ME writer pool badge (only when ME active)
    var meWriterBadge = '';
    if (mode === 'middle' && _meWr.length > 0) {
        var _wrAlive = _meWr.filter(function(w){ return w && !w.degraded; }).length;
        var _wrCls = _wrAlive === _meWr.length ? 'badge-ok' : (_wrAlive > 0 ? 'badge-warn' : 'badge-err');
        var _wrPct = Math.round(_wrAlive / _meWr.length * 100);
        meWriterBadge = '<span class="badge ' + _wrCls + '" title="ME writer pool health: alive / total (' + _wrPct + '%)">Writers: ' + _wrAlive + '/' + _meWr.length + '</span>';
    }

    // Conditional badges: show only when active
    var fb = _hasDegraded
        ? '<span class="badge badge-err" title="ME endpoints failed, falling back to Direct-DC.">Fallback: Active</span>' : '';
    var rroute = rt.reroute_active
        ? '<span class="badge badge-err" title="Traffic rerouted to alternative DCs due to failures.">Reroute: On</span>' : '';

    // Upstream health badge
    var upBadge = '';
    if (egress.total > 0) {
        var _upCls = egress.ok === egress.total ? 'badge-ok' : (egress.ok > 0 ? 'badge-warn' : 'badge-err');
        upBadge = '<span class="badge ' + _upCls + '" title="Upstream proxy health: healthy / configured.">Upstream: ' + egress.ok + '/' + egress.total + ' OK</span>';
    }

    // DC count badge (ME mode only)
    var dcsCount = 0;
    if (st && st.dcs && typeof st.dcs === 'object' && Array.isArray(st.dcs.dcs)) { dcsCount = st.dcs.dcs.length; }
    else if (st && Array.isArray(st.dcs)) { dcsCount = st.dcs.length; }
    var dcsBadge = (mode === 'middle' && dcsCount > 0) ? '<span class="badge badge-ok" title="Telegram DCs in ME pool.">DCs: ' + dcsCount + '</span>' : '';

    // Network path badge
    var npBadge = '';
    if (st && Array.isArray(st.network_path) && st.network_path.length > 0) {
        npBadge = '<span class="badge badge-ok" title="Upstream proxy chain hops.">Hops: ' + st.network_path.length + '</span>';
    }

    // Assemble badge row
    if(dg) dg.innerHTML = tgPathBadge + acc + egressBadge + meRdy + meWriterBadge + upBadge + dcsBadge + npBadge + fb + rroute + promBadges;

    if (dUp) {
        var upRendered = false;
        // Prefer dedicated /v1/stats/upstreams response; fall back to minimal/all embedded data
        var upsFromApi = (upData && upData.ok && upData.data && Array.isArray(upData.data.upstreams) && upData.data.upstreams.length > 0)
            ? upData.data.upstreams
            : (st && st.upstreams && Array.isArray(st.upstreams) && st.upstreams.length > 0 ? st.upstreams : null);
        if (upsFromApi) {
            var ups = upsFromApi;
            // Build address->quality lookup from upstream_quality API (3.3.22+)
            var upqLookup = {};
            if (upqData && upqData.ok && upqData.data && Array.isArray(upqData.data.upstreams)) {
                for (var qi=0; qi<upqData.data.upstreams.length; qi++) {
                    var qu = upqData.data.upstreams[qi];
                    if (qu && qu.address) upqLookup[qu.address] = qu;
                }
            }
            var uHtml = '<div style="display:flex; justify-content:space-between; font-weight:bold; opacity:0.7; border-bottom:1px solid rgba(128,128,128,0.3); padding-bottom:4px; margin-bottom:4px;"><div style="flex:1">Address</div><div style="flex:0 0 60px; text-align:right;">Status</div><div style="flex:0 0 50px; text-align:right;">Fails</div><div style="flex:0 0 75px; text-align:right;">Lat</div></div>';
            for (var i=0; i<ups.length; i++) {
                var up = ups[i] || {};
                var stCol = up.healthy ? '<span style="color:#00a000">OK</span>' : '<span style="color:#d9534f">FAIL</span>';
                var latStr = (up.effective_latency_ms != null) ? parseFloat(up.effective_latency_ms).toFixed(1) + 'ms' : '—';
                uHtml += '<div style="display:flex; justify-content:space-between; padding:6px 0; border-bottom:1px dashed rgba(128,128,128,0.15);"><div style="flex:1; word-break:break-all; padding-right:5px;">' + escHTML(up.address || '-') + '</div><div style="flex:0 0 60px; text-align:right;">' + stCol + '</div><div style="flex:0 0 50px; text-align:right;">' + (up.fails || 0) + '</div><div style="flex:0 0 75px; text-align:right;">' + latStr + '</div></div>';
                // Per-DC latency sub-rows from upstream_quality (if available)
                var qEntry = upqLookup[up.address];
                if (qEntry && Array.isArray(qEntry.dc) && qEntry.dc.length > 0) {
                    var dcParts = [];
                    for (var d=0; d<qEntry.dc.length && d<6; d++) {
                        var dcR = qEntry.dc[d];
                        var dcLat = (dcR.latency_ema_ms != null) ? parseFloat(dcR.latency_ema_ms).toFixed(0) + 'ms' : '—';
                        dcParts.push('DC' + dcR.dc + ':' + dcLat);
                    }
                    uHtml += '<div style="padding:2px 0 4px 12px; font-size:0.85em; opacity:0.7;">' + dcParts.join(' &nbsp; ') + '</div>';
                }
            }
            dUp.innerHTML = uHtml; upRendered = true;
        }
        if (!upRendered && st && Array.isArray(st.network_path) && st.network_path.length > 0) {
            var npHtml = '<div style="display:flex; justify-content:space-between; font-weight:bold; opacity:0.7; border-bottom:1px solid rgba(128,128,128,0.3); padding-bottom:4px; margin-bottom:4px;"><div style="flex:1">Hop</div><div style="flex:0 0 80px; text-align:right;">Type</div><div style="flex:0 0 60px; text-align:right;">Status</div></div>';
            for (var np=0; np < st.network_path.length; np++) {
                var hop = st.network_path[np] || {};
                var hopAddr = hop.address || hop.addr || ('-');
                var hopType = hop.type || hop.protocol || 'proxy';
                var hopOk = (hop.healthy !== false) ? '<span style="color:#00a000">OK</span>' : '<span style="color:#d9534f">FAIL</span>';
                npHtml += '<div style="display:flex; justify-content:space-between; padding:6px 0; border-bottom:1px dashed rgba(128,128,128,0.15);"><div style="flex:1; word-break:break-all;">' + escHTML(String(hopAddr)) + '</div><div style="flex:0 0 80px; text-align:right;">' + escHTML(String(hopType)) + '</div><div style="flex:0 0 60px; text-align:right;">' + hopOk + '</div></div>';
            }
            dUp.innerHTML = npHtml + '<div style="margin-top:6px; color:#888; font-size:0.9em; opacity:0.8;"><b>Connects:</b> ' + _upSuccesses + ' | <b>Fails:</b> ' + _upFails + '</div>';
        } else if (!upRendered && parsed.reason === 'source_unavailable') {
            dUp.innerHTML = '<div style="opacity:0.7; padding:10px;">Direct routing active or detailed upstream info unavailable.<br><br><b>Connects:</b> ' + _upSuccesses + ' | <b>Fails:</b> ' + _upFails + '</div>';
        } else if (!upRendered) {
            dUp.innerHTML = '<div style="opacity:0.7; text-align:center; padding:10px;">Direct routing active<br><br><b>Connects:</b> ' + _upSuccesses + ' | <b>Fails:</b> ' + _upFails + '</div>';
        }
    }

    if (dDc) {
        // Dynamic card title
        var dcTitle = document.getElementById('diag_dcs_title');
        if (dcTitle) dcTitle.textContent = (mode === 'middle') ? 'Datacenters (ME)' : 'Telegram Path';

        var dcs = [];
        if (st && Array.isArray(st.dcs)) {
            dcs = st.dcs;
        } else if (st && st.dcs && Array.isArray(st.dcs.dcs)) {
            dcs = st.dcs.dcs;
        } else if (st && st.dcs && typeof st.dcs === 'object' && Object.keys(st.dcs).length > 0) {
            dcs = Object.values(st.dcs);
        }

        if (dcs.length > 0) {
            // Mode A: ME active with DC table
            var dHtml = '<div style="display:flex; justify-content:space-between; font-weight:bold; color:#888; border-bottom:1px solid rgba(128,128,128,0.3); padding-bottom:4px; margin-bottom:4px;"><div style="flex:1">DC ID</div><div style="flex:0 0 100px; text-align:right;">Writers (A/R)</div><div style="flex:0 0 70px; text-align:right;">Coverage</div><div style="flex:0 0 60px; text-align:right;">RTT</div></div>';
            for (var k=0; k<dcs.length; k++) {
                var dc = dcs[k] || {};
                var coverage = Number(dc.coverage_pct || 0);
                var covCol = coverage >= 100 ? '<span style="color:#00a000">' + coverage + '%</span>' : '<span style="color:#d9534f">' + coverage + '%</span>';
                dHtml += '<div style="display:flex; justify-content:space-between; padding:6px 0; border-bottom:1px dashed rgba(128,128,128,0.15);"><div style="flex:1">DC ' + escHTML(String(dc.dc || '-')) + '</div><div style="flex:0 0 100px; text-align:right;">' + (dc.alive_writers || 0) + ' / ' + (dc.required_writers || 0) + '</div><div style="flex:0 0 70px; text-align:right;">' + covCol + '</div><div style="flex:0 0 60px; text-align:right;">' + (dc.rtt_ema_ms || 0) + 'ms</div></div>';
            }
            dDc.innerHTML = dHtml;
        } else if (rt && rt.me_runtime_ready) {
            dDc.innerHTML = '<div style="text-align:center; color:#d35400; padding:10px;">ME initializing, waiting for DC connections...</div>';
        } else {
            // Mode B: Direct-DC path (possibly via upstream)
            var pathParts = [];
            pathParts.push('<b>TG Path:</b> Direct-DC' + (egress.type !== 'Direct' ? ' over ' + egress.type : ''));
            if (egress.total > 0) {
                pathParts.push('<b>Upstream:</b> ' + egress.ok + '/' + egress.total + ' healthy');
            }
            pathParts.push('<b>Connects:</b> ' + _upSuccesses + ' &nbsp;|&nbsp; <b>Fails:</b> ' + _upFails + (_upSuccessRate ? ' &nbsp;|&nbsp; <b>Success:</b> ' + _upSuccessRate : ''));
            if (uciMpEnabled) {
                pathParts.push('<span style="color:#d35400;">ME is configured but not ready. Traffic uses Direct-DC as fallback.</span>');
            }
            dDc.innerHTML = '<div style="color:inherit; padding:10px; line-height:1.8;">' + pathParts.join('<br>') + '</div>';
        }
    }
}

function fetchMetrics() {
    // FIX 3.3.30: Don't stopTimers() on missing DOM — page may still be rendering.
    // Polling will retry on next cycle; visibilitychange handler manages real stop.
    if (!document.getElementById('cbi-telemt-general') && !document.getElementById('cbi-telemt-user') && !document.getElementById('diag_gates')) { return Promise.resolve(); }
    if (window._telemtFetching) return Promise.resolve();
    window._telemtFetching = true;

    var controller = window.AbortController ? new AbortController() : null;
    var signal = controller ? controller.signal : null;
    if (controller) { setTimeout(function() { controller.abort(); }, 8000); }

    return fetch(lu_current_url.split('#')[0] + (lu_current_url.indexOf('?') > -1 ? '&' : '?') + 'get_metrics=1&_t=' + Date.now(), signal ? { signal: signal } : {})
    .then(r => {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.text();
    }).then(txt => {
        window._telemtFetching = false;
        txt = txt || "";

        var parts = txt.split('---TELEMT_API_JSON---');
        var promText = cleanResponse(parts[0] || "");
        var rest = (parts[1] || "");
        var apiParts = rest.split('---TELEMT_UPSTREAMS_JSON---');
        var apiJsonStr = (apiParts[0] || "").trim();
        var upRest     = (apiParts[1] || "");
        // Split upstream quality (3.3.22+) from basic upstreams data
        var upQParts   = upRest.split('---TELEMT_UPSTREAM_QUALITY_JSON---');
        var upJsonStr  = (upQParts[0] || "").trim();
        var upqRest    = (upQParts[1] || "");
        // Split users API (3.3.30+) from upstream quality
        var usrParts   = upqRest.split('---TELEMT_USERS_API_JSON---');
        var upqJsonStr = (usrParts[0] || "").trim();
        // FIX: Replace regex s-flag (ES2018) with [\s\S]* for older browser compat
        var usrJsonStr = (usrParts[1] || "").replace(/<(!DOCTYPE|html[\s\S]*)$/i, '').trim();

        var apiData = null;
        if (apiJsonStr !== "") {
            try { apiData = JSON.parse(apiJsonStr); } catch(e) { apiData = null; }
        }
        var upData = null;
        if (upJsonStr !== "" && upJsonStr !== "{}") {
            try { upData = JSON.parse(upJsonStr); } catch(e) { upData = null; }
        }
        var upqData = null;
        if (upqJsonStr !== "" && upqJsonStr !== "{}") {
            try { upqData = JSON.parse(upqJsonStr); } catch(e) { upqData = null; }
        }
        // Users API data: build username -> IP list lookup for tooltips
        var usersApiData = null;
        window._telemtUserIPs = {};
        if (usrJsonStr !== "" && usrJsonStr !== "{}") {
            try {
                usersApiData = JSON.parse(usrJsonStr);
                if (usersApiData && usersApiData.ok && Array.isArray(usersApiData.data)) {
                    usersApiData.data.forEach(function(u) {
                        if (u.username && Array.isArray(u.active_unique_ips_list)) {
                            window._telemtUserIPs[u.username] = u.active_unique_ips_list;
                        }
                    });
                }
            } catch(e) { usersApiData = null; }
        }

        var pidMatch = promText.match(/# telemt_pid=(\d+)/);
        var rssMatch = promText.match(/# telemt_rss_kb=(\d+)/);
        var ramMatch = promText.match(/# sys_mem_avail_kb=(\d+)/);

        if (ramMatch) {
            var ramEl = document.getElementById('dash_ram');
            if (ramEl) {
                var ramMB = parseInt(ramMatch[1], 10) / 1024;
                ramEl.innerText = ramMB.toFixed(1) + ' MB';
                ramEl.style.color = ramMB < 100 ? '#d9534f' : '#555';
            }
        }

        if (rssMatch) {
            var rssEl = document.getElementById('dash_rss');
            if (rssEl) {
                var rssMB = parseInt(rssMatch[1], 10) / 1024;
                rssEl.innerText = rssMB.toFixed(1) + ' MB';
                rssEl.style.color = rssMB > 25 ? '#d9534f' : (rssMB > 15 ? '#d35400' : '#00a000');
            }
        }

        // FIX 3.3.30: isOffline only when BOTH PID and metrics are absent.
        // Prometheus (9092) is always-on; PID detection may temporarily fail.
        var metricsUpMatch = promText.match(/# telemt_metrics_up=1/);
        var isOffline = !pidMatch && !metricsUpMatch;
        var startingMatch = promText.match(/# telemt_state=starting/);

        var stEl = document.getElementById('dash_status');
        var utEl = document.getElementById('dash_uptime');

        // While a button action is in progress, don't overwrite the transitional status
        // (STOPPING.../STARTING.../RESTARTING...) — let it stay orange until the action completes.
        if (!_actionInProgress) {
            if (isOffline) {
                setOfflineState();
                if (utEl) utEl.innerText = '';
                if (window._telemtFastPoll) {
                    window._telemtFastPoll = false;
                    if (metricsTimer !== null) { clearTimeout(metricsTimer); metricsTimer = setTimeout(schedulePoll, 2500); }
                }
            } else if (startingMatch) {
                window._telemtFastPoll = true;
                var pidStr = pidMatch ? pidMatch[1] : '?';
                if (stEl) { stEl.innerText = 'STARTING\u2026 (PID: ' + pidStr + ')'; stEl.style.color = '#d35400'; }
                if (utEl) utEl.innerText = '';
            } else if (pidMatch) {
                if (stEl) { stEl.innerText = 'RUNNING (PID: ' + pidMatch[1] + ')'; stEl.style.color = '#00a000'; }
                if (window._telemtFastPoll) {
                    window._telemtFastPoll = false;
                    if (metricsTimer !== null) { clearTimeout(metricsTimer); metricsTimer = setTimeout(schedulePoll, 2500); }
                }
            } else {
                // Metrics available but PID not found — process is alive
                if (stEl) { stEl.innerText = 'RUNNING / PID UNKNOWN'; stEl.style.color = '#d35400'; }
            }
        }

        var userStats = {}; var allUserRows = document.querySelectorAll('.user-flat-stat');
        allUserRows.forEach(function(statEl) { var u = statEl.getAttribute('data-user'); if(u) userStats[u] = { live_rx: 0, live_tx: 0, acc_rx: 0, acc_tx: 0, conns: 0, ips: 0, ips_limit: 0 }; });

        var globalStatsObj = { uptime: 0 }; var totalLiveRx = 0, totalLiveTx = 0, totalAccRx = 0, totalAccTx = 0;
        var lines = promText.split('\n');
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim(); if (line.indexOf('#') === 0 || line === "") continue;
            if (/^telemt_uptime_seconds(\s|$)/.test(line)) { var m = line.match(/\s+([0-9\.eE\+\-]+)/); if(m) globalStatsObj.uptime = parseFloat(m[1]); continue; }
            var userMatch = line.match(/user="([^"]+)"/);
            if (userMatch) {
                var u = userMatch[1]; if (!userStats[u]) userStats[u] = { live_rx: 0, live_tx: 0, acc_rx: 0, acc_tx: 0, conns: 0, ips: 0, ips_limit: 0 };
                var valMatch = line.match(/\}\s+([0-9\.eE\+\-]+)/);
                if (valMatch) {
                    var val = parseFloat(valMatch[1]);
                    if (line.indexOf('telemt_user_octets_from_client') > -1) { userStats[u].live_rx = val; totalLiveRx += val; }
                    else if (line.indexOf('telemt_user_octets_to_client') > -1) { userStats[u].live_tx = val; totalLiveTx += val; }
                    else if (line.indexOf('telemt_user_connections_current') > -1) { userStats[u].conns = val; }
                    else if (line.indexOf('telemt_user_unique_ips_current') > -1) { userStats[u].ips = val; }
                    else if (line.indexOf('telemt_user_unique_ips_limit') > -1) { userStats[u].ips_limit = val; }
                    else if (line.indexOf('telemt_accumulated_rx') > -1) { userStats[u].acc_rx = val; totalAccRx += val; }
                    else if (line.indexOf('telemt_accumulated_tx') > -1) { userStats[u].acc_tx = val; totalAccTx += val; }
                }
            }
        }

        var totalRx = totalLiveRx + totalAccRx; var totalTx = totalLiveTx + totalAccTx;
        window._telemtLastStats = userStats;
        if (utEl && globalStatsObj.uptime > 0) { utEl.innerText = '| Uptime: ' + formatUptime(globalStatsObj.uptime); }
        var totalConfiguredUsers = allUserRows.length; var usersOnline = 0;

        allUserRows.forEach(function(statEl) {
            var u = statEl.getAttribute('data-user'); var stat = userStats[u] || { live_rx: 0, live_tx: 0, acc_rx: 0, acc_tx: 0, conns: 0, ips: 0, ips_limit: 0 };
            var finalTx = stat.live_tx + stat.acc_tx; var finalRx = stat.live_rx + stat.acc_rx; if (stat.conns > 0) usersOnline++;

            var qStr = statEl.getAttribute('data-q'); var eStr = statEl.getAttribute('data-e'); var isEn = statEl.getAttribute('data-en');
            var cb = document.querySelector('input[name*="cbid.telemt.' + u + '.enabled"]');

            var isExpired = false;
            if (eStr) { var p = eStr.split(' '); if(p.length==2) { var d=p[0].split('.'); var t=p[1].split(':'); if(d.length==3 && t.length==2) { if (Date.now() > new Date(d[2], d[1]-1, d[0], t[0], t[1]).getTime()) isExpired = true; } } }
            var isOverQuota = false;
            if (qStr) { var qGB = parseFloat(qStr); if (!isNaN(qGB) && qGB > 0) { if ((finalTx + finalRx) >= (qGB * 1073741824)) isOverQuota = true; } }

            if (isExpired) { statEl.innerHTML = "<span style='color:#d9534f; font-weight:bold;'>[ EXPIRED ]</span>"; return; }
            if (isOverQuota) { statEl.innerHTML = "<span style='color:#d9534f; font-weight:bold;'>[ QUOTA ]</span>"; return; }
            if (isEn === "0" || (cb && !cb.checked)) { statEl.innerHTML = "<span style='color:#888; font-weight:bold;'>[ PAUSED ]</span>"; return; }

            var c_col = stat.conns > 0 ? "#00a000" : "#888";
            var dotUser = "<svg width='10' height='10' style='vertical-align:middle;'><circle cx='5' cy='5' r='5' fill='" + c_col + "'/></svg>";
            var ipStr = '';
            if (stat.ips > 0 || stat.ips_limit > 0) {
                var ip_col = '#555';
                // Build IP address tooltip from API data (if available)
                var ipTip = 'Unique active IPs';
                var ipAddrs = (window._telemtUserIPs && window._telemtUserIPs[u]) ? window._telemtUserIPs[u] : [];
                if (ipAddrs.length > 0) ipTip = ipAddrs.join(', ');
                if (stat.ips_limit > 0) {
                    ip_col = (stat.ips >= stat.ips_limit) ? '#d9534f' : 'inherit';
                    ipStr = " <span style='color:" + ip_col + ";margin-left:3px;cursor:help;' title='" + escHTML(ipTip) + "'>IP " + stat.ips + "/" + stat.ips_limit + "</span>";
                } else {
                    ipStr = " <span style='opacity:0.7;margin-left:3px;cursor:help;' title='" + escHTML(ipTip) + "'>IP " + stat.ips + "</span>";
                }
            }
            var statHtml = "<div style='display:flex; align-items:center; gap:4px; margin-bottom:2px; flex-wrap:wrap;'><span style='color:#00a000;' title='Total Download (Live + Accumulated)'>&darr; " + formatMB(finalTx) + "</span> <span class='stat-divider'>/</span> <span style='color:#d35400;' title='Total Upload (Live + Accumulated)'>&uarr; " + formatMB(finalRx) + "</span> <span class='stat-divider'>|</span> <span style='color:" + c_col + ";' title='Active TCP connections'>" + dotUser + "&nbsp;" + stat.conns + "</span>" + ipStr + "</div>";
            if (isOffline) { statEl.innerHTML = "<div style='opacity: 0.6; filter: grayscale(1);' title='Daemon is offline, showing accumulated stats'>" + statHtml + "</div>"; return; }
            statEl.innerHTML = statHtml;
        });

        var now = Date.now(); var speedDL = 0, speedUL = 0;
        if (!window._telemtLastTime) { window._telemtLastTime = now; window._telemtLastTotalRx = totalRx; window._telemtLastTotalTx = totalTx; }
        else { var diffSec = (now - window._telemtLastTime) / 1000.0; if (diffSec > 0) { var dRx = totalRx - window._telemtLastTotalRx; var dTx = totalTx - window._telemtLastTotalTx; if (dRx >= 0) speedUL = (dRx * 8) / 1048576 / diffSec; if (dTx >= 0) speedDL = (dTx * 8) / 1048576 / diffSec; } window._telemtLastTime = now; window._telemtLastTotalRx = totalRx; window._telemtLastTotalTx = totalTx; }

        var sumEl = document.getElementById('telemt_users_summary_inner');
        if (sumEl && !isOffline) {
            var statStr = "<div class='sum-row'><b>Uptime:</b> <span style='color:#666;'>" + formatUptime(globalStatsObj.uptime) + "</span></div>" +
                "<div class='sum-row'><b style='color:#555;'>Total DL:</b> <span style='color:#00a000;'>&darr; " + formatMB(totalTx) + "</span></div>" +
                "<div class='sum-row'><b style='color:#555;'>Total UL:</b> <span style='color:#d35400;'>&uarr; " + formatMB(totalRx) + "</span></div>" +
                "<div class='sum-row'><b style='color:#555;'>BW:</b> <span style='color:#00a000;'>&darr; " + speedDL.toFixed(2) + "</span> <span style='color:#d35400;'>&uarr; " + speedUL.toFixed(2) + "</span> <small>Mbps</small></div>" +
                "<div class='sum-row'><b style='color:#555;'>Online:</b> <b style='color:#00a000;'>" + usersOnline + "</b> / " + totalConfiguredUsers + "</div>";
            sumEl.innerHTML = statStr;
        }

        if (document.getElementById('diag_gates') && !isOffline) {
            renderHealthGrid(apiData, promText, upData, upqData);
        }
        // Inject health badges into Upstream Proxies tab (if visible)
        if (upData && !isOffline) { renderUpstreamBadges(upData); }

    }).catch(err => {
        window._telemtFetching = false;
        if (err && err.name === 'AbortError') { console.warn('[Telemt] Metrics fetch timeout, skipping update'); return; }
        setOfflineState();
        var sEl = document.getElementById('dash_status');
        if (sEl) { sEl.innerText = 'STOPPED / CONNECTION LOST'; sEl.style.color = '#d9534f'; }
    }).finally(() => {
        window._telemtFetching = false;
    });
}

function getEffectiveIP() { var m1 = document.querySelector('input[name*="cbid.telemt.general.external_ip"]'); var m2 = document.getElementById('telemt_mirror_ip'); if (m2 && m2.offsetParent !== null) return m2.value.trim(); if (m1) return m1.value.trim(); return "0.0.0.0"; }

function updateLinks() {
    var d = document.querySelector('input[name*="domain"]'); var p = document.querySelector('input[name*="cbid.telemt.general.port"]'); var modeSelect = document.querySelector('select[name*="mode"]'); var fmtSelect = document.querySelector('select[name*="_link_fmt"]');
    var ppField = document.querySelector('input[name*="cbid.telemt.general.public_port"]');
    var ip = getEffectiveIP(); var port = p ? p.value.trim() : "8443"; var domain = d ? d.value.trim() : ""; var mode = modeSelect ? modeSelect.value : "tls";
    if (ppField && ppField.value.trim() !== '') { port = ppField.value.trim(); }
    var effectiveFmt = mode; if (mode === 'all' && fmtSelect) effectiveFmt = fmtSelect.value;
    if(!ip || !port) return;
    var hd = ""; if (domain && (effectiveFmt === 'tls' || effectiveFmt === 'all')) { for(var n=0; n<domain.length; n++) { var hex = domain.charCodeAt(n).toString(16); if (hex.length < 2) hex = "0" + hex; hd += hex; } }
    document.querySelectorAll('#cbi-telemt-user .cbi-section-table-row:not(.cbi-row-template), #cbi-telemt-user tr.cbi-row:not(.cbi-row-template), #cbi-telemt-user div.cbi-row:not(.cbi-row-template)').forEach(function(row) {
        var secInp = row.querySelector('input[name*="secret"]'); var linkOut = row.querySelector('.user-link-out');
        if(secInp && linkOut) { var val = secInp.value.trim(); if(/^[0-9a-fA-F]{32}$/.test(val)) { var finalSecret = (effectiveFmt === 'tls' || effectiveFmt === 'all') ? "ee" + val + hd : ((effectiveFmt === 'dd') ? "dd" + val : val); linkOut.value = "tg://proxy?server=" + ip + "&port=" + port + "&secret=" + finalSecret; linkOut.classList.remove('user-link-err'); } else { linkOut.value = "Error: 32 hex chars required!"; linkOut.classList.add('user-link-err'); } }
    });
    updateCascadesState();
}

function fallbackCopy(text, btn) {
    var ta = document.createElement('textarea');
    ta.value = text; ta.style.position = 'fixed'; ta.style.left = '-9999px';
    document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); btn.value = 'Copied!'; setTimeout(function(){ btn.value = 'Copy'; }, 1500); }
    catch(e) { btn.value = 'Copy failed'; }
    document.body.removeChild(ta);
}

function copyProxyLink(btn) {
    var row = btn.closest('.cbi-section-table-row') || btn.closest('.cbi-row'); if (!row) return;
    var input = row.querySelector('.user-link-out');
    if (input && !input.classList.contains('user-link-err')) {
        var textToCopy = input.value;
        fetch(lu_current_url.split('#')[0], { method: 'POST', body: (function(){var f=new FormData(); f.append('log_ui_event', '1'); f.append('msg', 'Proxy link copied'); return f;})() });
        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(textToCopy).then(function() { var oldVal = btn.value; btn.value = '✔'; setTimeout(function(){ btn.value = oldVal; }, 1500); }).catch(function() { fallbackCopy(textToCopy, btn); });
        } else { fallbackCopy(textToCopy, btn); }
    }
}

function genRandHex() { var arr = new Uint8Array(16); (window.crypto || window.msCrypto).getRandomValues(arr); var h = ""; for(var i=0; i<16; i++) { var hex = arr[i].toString(16); if(hex.length < 2) hex = "0" + hex; h += hex; } return h; }

function fetchIPViaWget(btn) { var oldVal = btn.value; btn.value = '...'; fetch(lu_current_url.split('#')[0] + (lu_current_url.indexOf('?') > -1 ? '&' : '?') + 'get_wan_ip=1&_t=' + Date.now()).then(r => r.text()).then(txt => { txt = cleanResponse(txt); var match = txt.match(/\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b/); if (match) { var master = document.querySelector('input[name*="cbid.telemt.general.external_ip"]'); var mirror = document.getElementById('telemt_mirror_ip'); if(master) master.value = match[0]; if(mirror) mirror.value = match[0]; updateLinks(); } btn.value = oldVal; }).catch(() => { btn.value = oldVal; }); }

function loadLog() {
    var btn = document.getElementById('btn_load_log'); if(!btn) return;
    btn.value = 'Loading...'; btn.disabled = true;
    fetch(lu_current_url.split('#')[0] + (lu_current_url.indexOf('?') > -1 ? '&' : '?') + 'get_log=1&_t=' + Date.now())
    .then(r => r.text()).then(txt => {
        txt = txt || '';
        var htmlTail = txt.lastIndexOf('<!DOCTYPE');
        if (htmlTail > 0 && htmlTail > txt.length * 0.8) { txt = txt.substring(0, htmlTail).trim(); }
        // Strip binary ISO timestamp (e.g. "2026-03-16T11:13:16.717471Z ") — logread already prefixes date+time
        txt = txt.replace(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\s*/g, '');
        document.getElementById('telemt_log_container').textContent = txt || 'No logs found.';
        btn.value = 'Update Log';
    }).catch(() => {
        document.getElementById('telemt_log_container').textContent = 'Error: Could not fetch log. Check LuCI connection.';
        btn.value = 'Update Log (retry)';
    }).finally(() => { btn.disabled = false; });
}

function loadScanners() {
    var btn = document.getElementById('btn_load_scanners'); if(!btn) return;
    btn.value = 'Loading...'; btn.disabled = true;
    fetch(lu_current_url.split('#')[0] + (lu_current_url.indexOf('?') > -1 ? '&' : '?') + 'get_scanners=1&_t=' + Date.now())
    .then(r => r.text()).then(txt => {
        txt = (txt || '').replace(/<(!DOCTYPE|html[\s\S]*)$/i, '').trim();
        var logEl = document.getElementById('telemt_log_container');
        if (!txt || txt.indexOf('[') === -1) {
            logEl.textContent = "=== [ ACTIVE DPI SCANNERS ] ===\n\nNo scanner activity detected.";
        } else {
            // Parse [category] ip-count format into formatted output
            var out = "=== [ ACTIVE DPI SCANNERS ] ===\n\n";
            // FIX: Use String.fromCharCode to build bracket regex safely for Lua long string embedding.
            // Use String.fromCharCode(91)='[' and (93)=']' to keep Lua parser safe.
            var _ob = String.fromCharCode(91), _cb = String.fromCharCode(93);
            var parts = txt.split(new RegExp('(' + _ob + '[^' + _cb + ']+' + _cb + ')'));
            for (var p=0; p<parts.length; p++) {
                var chunk = parts[p].trim();
                if (!chunk) continue;
                if (chunk.charAt(0) === _ob) {
                    out += "--- " + chunk.replace(/\[/g, '').replace(/\]/g, '').replace(/-/g, ' ').toUpperCase() + " ---\n";
                } else {
                    var entries = chunk.trim().split(/\s+/);
                    for (var e=0; e<entries.length; e++) {
                        var m = entries[e].match(/^([0-9a-f.:]+)-(\d+)$/i);
                        if (m) { out += "  " + m[1] + "  \u2014  " + m[2] + " hits\n"; }
                    }
                    out += "\n";
                }
            }
            logEl.textContent = out;
        }
        btn.value = 'Refresh Scanners';
    }).catch(() => {
        document.getElementById('telemt_log_container').textContent = 'Error fetching scanners data.';
        btn.value = 'Error';
    }).finally(() => { btn.disabled = false; });
}

function loadRuntimeInfo() {
    var btn = document.getElementById('btn_runtime_info'); if(!btn) return;
    var logEl = document.getElementById('telemt_log_container'); if(!logEl) return;
    btn.value = 'Loading...'; btn.disabled = true;
    var baseUrl = lu_current_url.split('#')[0];
    var sep = (baseUrl.indexOf('?') > -1) ? '&' : '?';
    Promise.all([
        fetch(baseUrl + sep + 'get_metrics=1&_t=' + Date.now()).then(function(r){ return r.text(); }).catch(function(){ return ''; })
    ]).then(function(results) {
        var raw = results[0] || '';
        var apiParts = raw.split('---TELEMT_API_JSON---');
        var promPart = apiParts[0] || raw;
        var apiJson = '{}', upJson = '{}', upqJson = '{}';
        if (apiParts.length > 1) {
            var rest = apiParts[1];
            var upParts = rest.split('---TELEMT_UPSTREAMS_JSON---');
            apiJson = (upParts[0] || '{}').trim();
            var upRest = upParts[1] || '{}';
            var upqParts = upRest.split('---TELEMT_UPSTREAM_QUALITY_JSON---');
            upJson = (upqParts[0] || '{}').trim();
            upqJson = (upqParts[1] || '{}').replace(/<(!DOCTYPE|html[\s\S]*)$/i, '').trim();
        }
        var out = '=== [ RUNTIME INFO ] ===\n\n';

        // Prometheus key metrics (human-readable)
        out += '--- Proxy Health ---\n';
        var prom = {};
        var pkeys = ['telemt_uptime_seconds', 'telemt_connections_total', 'telemt_connections_bad_total',
            'telemt_connections_current', 'telemt_connections_direct_current', 'telemt_connections_me_current',
            'telemt_handshake_timeouts_total', 'telemt_upstream_connect_attempt_total',
            'telemt_upstream_connect_success_total', 'telemt_upstream_connect_fail_total',
            'telemt_desync_total', 'telemt_secure_padding_invalid_total', 'telemt_reconnect_evict_total',
            'telemt_me_reconnect_attempts_total', 'telemt_me_reconnect_success_total',
            'telemt_me_handshake_reject_total', 'telemt_me_crc_mismatch_total',
            'telemt_me_writers_active_current', 'telemt_me_writers_warm_current',
            'telemt_me_keepalive_timeout_total', 'telemt_me_kdf_drift_total'];
        for (var i = 0; i < pkeys.length; i++) {
            var re = new RegExp('^' + pkeys[i] + '\\s+([0-9\\.eE\\+\\-]+)', 'm');
            var mv = promPart.match(re); if (mv) { var pk = pkeys[i]; prom[pk] = parseFloat(mv[1]); }
        }
        var upt = prom['telemt_uptime_seconds'] || 0;
        var uptD = Math.floor(upt / 86400), uptH = Math.floor((upt % 86400) / 3600), uptM = Math.floor((upt % 3600) / 60);
        out += 'Uptime:              ' + uptD + 'd ' + uptH + 'h ' + uptM + 'm\n';
        out += 'Live connections:    ' + (prom['telemt_connections_current'] || 0);
        if (prom['telemt_connections_me_current'] > 0) out += ' (direct: ' + (prom['telemt_connections_direct_current'] || 0) + ', ME: ' + (prom['telemt_connections_me_current'] || 0) + ')';
        out += '\n';
        out += 'Connections total:   ' + (prom['telemt_connections_total'] || 0) + '\n';
        out += 'Rejected:            ' + (prom['telemt_connections_bad_total'] || 0) + '\n';
        out += 'Handshake timeouts:  ' + (prom['telemt_handshake_timeouts_total'] || 0) + '\n';
        out += 'DPI tamper (desync): ' + (prom['telemt_desync_total'] || 0) + '\n';
        if (prom['telemt_secure_padding_invalid_total'] > 0) out += 'Invalid padding:     ' + prom['telemt_secure_padding_invalid_total'] + '\n';
        if (prom['telemt_reconnect_evict_total'] > 0) out += 'Evicted sessions:    ' + prom['telemt_reconnect_evict_total'] + '\n';

        var attempts = prom['telemt_upstream_connect_attempt_total'] || 0;
        var success = prom['telemt_upstream_connect_success_total'] || 0;
        var fail = prom['telemt_upstream_connect_fail_total'] || 0;
        var rate = attempts > 0 ? Math.round(success / attempts * 100) : 100;
        out += '\n--- Upstream Connect ---\n';
        out += 'Attempts:  ' + attempts + '\n';
        out += 'Success:   ' + success + '\n';
        out += 'Fails:     ' + fail + '\n';
        out += 'Rate:      ' + rate + '%\n';

        // UCI config flags
        var mpMatch = promPart.match(/# telemt_uci_use_mp=(\d)/);
        var upTypesMatch = promPart.match(/# telemt_uci_upstream_types=([^\n]*)/);
        out += '\n--- Config ---\n';
        out += 'ME enabled (UCI):    ' + (mpMatch ? (mpMatch[1] === '1' ? 'yes' : 'no') : 'unknown') + '\n';
        out += 'Upstream types:      ' + (upTypesMatch ? (upTypesMatch[1] || 'none') : 'none') + '\n';

        // ME writers from Prometheus
        if (prom['telemt_me_writers_active_current'] > 0 || (mpMatch && mpMatch[1] === '1')) {
            out += '\n--- ME Writers ---\n';
            out += 'Active:     ' + (prom['telemt_me_writers_active_current'] || 0) + '\n';
            out += 'Warm:       ' + (prom['telemt_me_writers_warm_current'] || 0) + '\n';
            out += 'KDF drift:  ' + (prom['telemt_me_kdf_drift_total'] || 0) + '\n';
            out += 'Reconnect:  ' + (prom['telemt_me_reconnect_success_total'] || 0) + '/' + (prom['telemt_me_reconnect_attempts_total'] || 0) + '\n';
            if (prom['telemt_me_keepalive_timeout_total'] > 0) out += 'KA timeout: ' + prom['telemt_me_keepalive_timeout_total'] + '\n';
        }

        // API: ME details (minimal/all)
        try {
            var api = JSON.parse(apiJson);
            if (api.ok && api.data && api.data.data) {
                var d = api.data.data;
                if (d.dcs && d.dcs.dcs && d.dcs.dcs.length > 0) {
                    out += '\n--- DCs ---\n';
                    d.dcs.dcs.forEach(function(dc) {
                        out += 'DC ' + (dc.dc || '?') + ':  writers ' + (dc.alive_writers || 0) + '/' + (dc.required_writers || 0) +
                            ', coverage ' + (dc.coverage_pct || 0) + '%, RTT ' + (dc.rtt_ema_ms || 0) + 'ms\n';
                    });
                }
            }
        } catch(e) { /* API not available, skip */ }

        // API: Upstreams with per-DC latency
        try {
            var upq = JSON.parse(upqJson);
            if (upq.ok && upq.data && Array.isArray(upq.data.upstreams) && upq.data.upstreams.length > 0) {
                out += '\n--- Upstreams (detailed) ---\n';
                upq.data.upstreams.forEach(function(u, idx) {
                    out += '#' + (idx + 1) + ': ' + (u.route_kind || '?') + '://' + (u.address || 'direct') +
                        ' w:' + (u.weight || 1) + ' | ' + (u.healthy ? 'OK' : 'FAIL') +
                        ' | fails=' + (u.fails || 0) +
                        ' | lat=' + (u.effective_latency_ms != null ? parseFloat(u.effective_latency_ms).toFixed(1) + 'ms' : '-') + '\n';
                    if (Array.isArray(u.dc)) {
                        u.dc.forEach(function(d) {
                            var dcLat = (d.latency_ema_ms != null) ? parseFloat(d.latency_ema_ms).toFixed(0) + 'ms' : '-';
                            out += '   DC' + d.dc + ': ' + dcLat + '\n';
                        });
                    }
                });
            } else {
                // Fallback: basic upstreams
                var up = JSON.parse(upJson);
                if (up.ok && up.data && up.data.upstreams && up.data.upstreams.length > 0) {
                    out += '\n--- Upstreams ---\n';
                    up.data.upstreams.forEach(function(u, idx) {
                        out += '#' + (idx + 1) + ': ' + (u.address || 'direct') +
                            ' | ' + (u.healthy ? 'OK' : 'FAIL') +
                            ' | fails=' + (u.fails || 0) +
                            ' | lat=' + (u.effective_latency_ms != null ? u.effective_latency_ms + 'ms' : '-') + '\n';
                    });
                }
            }
        } catch(e) { /* Upstream API not available, skip */ }

        // Per-user stats
        if (window._telemtLastStats) {
            out += '\n--- User Stats ---\n';
            for (var u in window._telemtLastStats) {
                if (!window._telemtLastStats.hasOwnProperty(u)) continue;
                var st = window._telemtLastStats[u];
                var tx = ((st.live_tx || 0) + (st.acc_tx || 0)) / 1048576;
                var rx = ((st.live_rx || 0) + (st.acc_rx || 0)) / 1048576;
                var ipStr = (st.ips > 0 || st.ips_limit > 0) ? '  IP:' + st.ips + (st.ips_limit > 0 ? '/' + st.ips_limit : '') : '';
                out += u + ':  DL ' + tx.toFixed(1) + ' MB, UL ' + rx.toFixed(1) + ' MB, conns=' + (st.conns || 0) + ipStr;
                // Append actual IP addresses from API (if available)
                var uIPs = (window._telemtUserIPs && window._telemtUserIPs[u]) ? window._telemtUserIPs[u] : null;
                if (uIPs && uIPs.length > 0) out += '  [' + uIPs.join(', ') + ']';
                out += '\n';
            }
        }

        logEl.textContent = out;
        btn.value = 'Refresh Info';
    }).catch(function() {
        logEl.textContent = 'Error fetching runtime data.';
        btn.value = 'Error';
    }).finally(function() { btn.disabled = false; });
}

function copyLogContent(btn) {
    var logText = document.getElementById('telemt_log_container').textContent; if(!logText) return;
    if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(logText).then(function() {
            var oldVal = btn.value; btn.value = 'Copied!'; setTimeout(function(){ btn.value = oldVal; }, 1500);
        }).catch(function() { fallbackCopy(logText, btn); });
    } else { fallbackCopy(logText, btn); }
}

function updateFWStatus() { if (!document.getElementById('cbi-telemt-general')) return; var fwSpan = document.getElementById('fw_status_span'); if (!fwSpan) return; fetch(lu_current_url.split('#')[0] + (lu_current_url.indexOf('?') > -1 ? '&' : '?') + 'get_fw_status=1&_t=' + Date.now()).then(r => r.text()).then(txt => { txt = cleanResponse(txt); if(txt.indexOf('OPEN') > -1 || txt.indexOf('CLOSED') > -1 || txt.indexOf('STOPPED') > -1) fwSpan.innerHTML = txt; }).catch(()=>{}); }

function closeModals() { document.querySelectorAll('.qr-modal-overlay').forEach(function(m) { m.classList.remove('active'); }); document.body.classList.remove('qr-modal-open'); }
function showQRModal(link) { if (!link || link.indexOf('Error') === 0) return; var overlay = document.getElementById('qr-modal'); if (!overlay) { overlay = document.createElement('div'); overlay.id = 'qr-modal'; overlay.className = 'qr-modal-overlay'; var content = document.createElement('div'); content.className = 'custom-modal-content'; var body = document.createElement('div'); body.id = 'qr-modal-body'; content.appendChild(body); var clsBtn = document.createElement('button'); clsBtn.className = 'cbi-button cbi-button-reset'; clsBtn.style.cssText = 'margin-top:15px; width:100%;'; clsBtn.innerText = 'Close'; clsBtn.addEventListener('click', closeModals); content.appendChild(clsBtn); overlay.appendChild(content); document.body.appendChild(overlay); overlay.addEventListener('click', function(e) { if (e.target === overlay) closeModals(); }); } var body = document.getElementById('qr-modal-body'); body.innerHTML = 'Generating...'; overlay.classList.add('active'); document.body.classList.add('qr-modal-open'); fetch(lu_current_url.split('#')[0] + (lu_current_url.indexOf('?') > -1 ? '&' : '?') + 'get_qr=1&link=' + encodeURIComponent(link) + '&_t=' + Date.now()).then(r => r.text()).then(txt => { txt = cleanResponse(txt); if (txt.indexOf('error: qrencode_missing') > -1) body.innerHTML = '<div style="color:#d9534f; font-weight:bold; margin-bottom:10px;">Install qrencode</div>'; else if (txt.indexOf('error: invalid_link') > -1) body.innerHTML = '<div style="color:#d9534f; font-weight:bold;">Invalid Link Format</div>'; else { var svgMatch = txt.match(/<svg[\s\S]*?<\/svg>/i); body.innerHTML = svgMatch ? svgMatch[0] : 'Error'; } }).catch(() => { body.innerHTML = 'Connection error.'; }); }

function doExportStats() { if (!window._telemtLastStats) { alert("Live stats not loaded yet. Wait a few seconds."); return; } logAction("Exporting Live Stats to CSV"); var csv = "username,total_dl_bytes,total_ul_bytes,active_connections\n"; var grandTx = 0, grandRx = 0, grandConns = 0; for (var u in window._telemtLastStats) { if (window._telemtLastStats.hasOwnProperty(u)) { var s = window._telemtLastStats[u]; var tx = (s.live_tx || 0) + (s.acc_tx || 0); var rx = (s.live_rx || 0) + (s.acc_rx || 0); var c = (s.conns || 0); csv += u + "," + tx + "," + rx + "," + c + "\n"; grandTx += tx; grandRx += rx; grandConns += c; } } csv += "TOTAL_ALL_USERS," + grandTx + "," + grandRx + "," + grandConns + "\n"; var blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' }); var link = document.createElement("a"); link.setAttribute("href", URL.createObjectURL(blob)); link.setAttribute("download", "telemt_traffic_stats.csv"); link.style.visibility = 'hidden'; document.body.appendChild(link); link.click(); document.body.removeChild(link); }
function doExportCSV() { logAction("Exporting Users to CSV"); var blob = new Blob(["]] ..
    clean_csv ..
    [["], { type: 'text/csv;charset=utf-8;' }); var link = document.createElement("a"); link.setAttribute("href", URL.createObjectURL(blob)); link.setAttribute("download", "telemt_users.csv"); link.style.visibility = 'hidden'; document.body.appendChild(link); link.click(); document.body.removeChild(link); }
function readCSVFile(input) { var file = input.files[0]; var displaySpan = document.getElementById('csv_file_name_display'); if (!file) { displaySpan.innerText = "No file selected"; return; } displaySpan.innerText = file.name; var reader = new FileReader(); reader.onload = function(e) { document.getElementById('csv_text_area').value = e.target.result; }; reader.readAsText(file); }

function submitImport() {
    logAction('Executing Users Import'); var csv = document.getElementById('csv_text_area').value; var radioBtn = document.querySelector('input[name="import_mode"]:checked'); var mode = radioBtn ? radioBtn.value : 'replace';
    var form = document.createElement('form'); form.method = 'POST'; form.action = lu_current_url.split('#')[0]; var inputs = { 'import_users': '1', 'csv_data': csv, 'import_mode': mode };
    for (var key in inputs) { var el = document.createElement(key === 'csv_data' ? 'textarea' : 'input'); if (key !== 'csv_data') el.type = 'hidden'; el.name = key; el.value = inputs[key]; form.appendChild(el); }
    var tokenVal = null; var tokenNode = document.querySelector('input[name="token"]');
    if (tokenNode) { tokenVal = tokenNode.value; } else if (typeof L !== 'undefined' && L.env) { tokenVal = L.env.token || L.env.requesttoken || null; }
    if (!tokenVal) { var match = document.cookie.match(/(?:sysauth_http|sysauth)=([^;]+)/); if (match) tokenVal = match[1]; }
    if (tokenVal) { var t = document.createElement('input'); t.type = 'hidden'; t.name = 'token'; t.value = tokenVal; form.appendChild(t); }
    document.body.appendChild(form); form.submit();
}

function showImportModal() {
    var m = document.getElementById('import-modal');
    if (!m) {
        m = document.createElement('div'); m.id = 'import-modal'; m.className = 'qr-modal-overlay';
        m.innerHTML = '<div class="custom-modal-content" style="text-align:left;"><h3 style="margin-top:0; margin-bottom:10px;">Import Users from CSV</h3><p style="font-size:12px; opacity:0.8; line-height:1.4; margin-top:0;">Upload or paste a <b>.csv</b> file. Format: <b>username,secret,max_tcp_conns,max_unique_ips,data_quota,expire_date</b></p><div style="margin-bottom:15px; display:flex; gap:10px; align-items:center;"><input type="file" id="csv_file_input" accept=".csv" style="display:none;"><input type="button" class="cbi-button cbi-button-action" id="btn_csv_choose" value="Choose File..."><span id="csv_file_name_display" style="font-size:12px; opacity:0.8;">No file selected</span></div><textarea id="csv_text_area" placeholder="user1,164f44a...,50,5,1.5,31.12.2026 23:59\nuser2,..."></textarea><div style="margin-bottom:20px; font-size:13px;"><label style="display:flex; align-items:center; gap:5px; margin-bottom:8px;"><input type="radio" name="import_mode" value="replace" checked> <span><b>Replace</b> (Delete existing users)</span></label><label style="display:flex; align-items:center; gap:5px;"><input type="radio" name="import_mode" value="merge"> <span><b>Merge</b> (Keep existing)</span></label></div><div style="display:flex; gap:10px;"><input type="button" class="cbi-button cbi-button-apply" id="btn_csv_import" style="flex:1;" value="Import & Save"><input type="button" class="cbi-button cbi-button-reset" id="btn_csv_cancel" style="flex:1;" value="Cancel"></div></div>';
        document.body.appendChild(m); m.addEventListener('click', function(e) { if (e.target === m) closeModals(); });
        document.getElementById('btn_csv_choose').addEventListener('click', function() { document.getElementById('csv_file_input').click(); });
        document.getElementById('csv_file_input').addEventListener('change', function(e) { readCSVFile(e.target); });
        document.getElementById('btn_csv_import').addEventListener('click', submitImport);
        document.getElementById('btn_csv_cancel').addEventListener('click', closeModals);
    }
    document.getElementById('csv_file_input').value = ""; document.getElementById('csv_file_name_display').innerText = "No file selected"; document.getElementById('csv_text_area').value = "";
    m.classList.add('active'); document.body.classList.add('qr-modal-open');
}

function fixTabIsolation() {
    var userTable = document.getElementById('cbi-telemt-user'); var userAnchor = document.getElementById('users_tab_anchor');
    if (userTable && userAnchor && userTable.parentNode) {
        var userTarget = userAnchor.closest('.cbi-tab') || userAnchor.closest('[data-tab]') || userAnchor.parentNode;
        if (userTarget && userTable.parentNode !== userTarget) { userTarget.appendChild(userTable); }
        userTable.style.display = ''; userTable.hidden = false;

        if (!document.getElementById('telemt_users_dashboard_panel')) {
            var dash = document.createElement('div'); dash.id = 'telemt_users_dashboard_panel';

            var topRow = document.createElement('div'); topRow.className = 'telemt-dash-top-row';
            var sumInner = document.createElement('div'); sumInner.id = 'telemt_users_summary_inner'; sumInner.className = 'telemt-dash-summary'; topRow.appendChild(sumInner);
            dash.appendChild(topRow);

            var btnsBar = document.createElement('div'); btnsBar.className = 'telemt-action-btns';
            var btnResetStats = document.createElement('input'); btnResetStats.type = 'button'; btnResetStats.className = 'cbi-button cbi-button-remove'; btnResetStats.value = 'Reset Stats'; btnResetStats.title = 'Clear all accumulated user traffic statistics'; btnResetStats.addEventListener('click', function(){ if(confirm('Are you sure you want to completely clear ALL accumulated user traffic statistics?')) { postAction('reset_stats'); } }); btnsBar.appendChild(btnResetStats);
            var btnExpStat = document.createElement('input'); btnExpStat.type = 'button'; btnExpStat.className = 'cbi-button cbi-button-apply'; btnExpStat.value = 'Export Stats'; btnExpStat.title = 'Export traffic usage statistics'; btnExpStat.addEventListener('click', doExportStats); btnsBar.appendChild(btnExpStat);
            var btnExpCsv = document.createElement('input'); btnExpCsv.type = 'button'; btnExpCsv.className = 'cbi-button cbi-button-action'; btnExpCsv.value = 'Export Users'; btnExpCsv.title = 'Export users configuration as CSV file'; btnExpCsv.addEventListener('click', doExportCSV); btnsBar.appendChild(btnExpCsv);
            var btnImpCsv = document.createElement('input'); btnImpCsv.type = 'button'; btnImpCsv.className = 'cbi-button cbi-button-action'; btnImpCsv.value = 'Import Users'; btnImpCsv.title = 'Import users from CSV file'; btnImpCsv.addEventListener('click', showImportModal); btnsBar.appendChild(btnImpCsv);
            dash.appendChild(btnsBar);

            userTarget.insertBefore(dash, userTable);
        }
    }

    var upTable = document.getElementById('cbi-telemt-upstream'); var upAnchor = document.getElementById('upstreams_tab_anchor');
    if (upTable && upAnchor && upTable.parentNode) {
        var upTarget = upAnchor.closest('.cbi-tab') || upAnchor.closest('[data-tab]') || upAnchor.parentNode;
        if (upTarget && upTable.parentNode !== upTarget) { upTarget.appendChild(upTable); }
        upTable.style.display = ''; upTable.hidden = false;
        var btnAddUp = upTable.querySelector('.cbi-button-add'); if (btnAddUp && btnAddUp.value !== 'Add Upstream') btnAddUp.value = 'Add Upstream';
    }
}

function isTemplateRow(row) {
    if (!row) return true; if (row.classList.contains('cbi-row-template')) return true; if (row.id && row.id.indexOf('-template') > -1) return true;
    if (row.hidden || row.style.display === 'none') return true; if (!row.querySelector('input[name*=".secret"]') && !row.querySelector('input[name*=".address"]')) return true; return false;
}

function injectUI() {
    fixTabIsolation();
    scheduleRepack();

    var secretTh = document.querySelector('#cbi-telemt-user th[data-name="secret"]') || document.querySelector('#cbi-telemt-user .cbi-section-table-titles th:first-child') || document.querySelector('#cbi-telemt-user thead th:first-child');
    if (secretTh && !secretTh.dataset.renamed) { var txt = (secretTh.textContent || '').trim().toLowerCase(); if (txt == 'secret' || txt == 'name' || txt == '') { secretTh.textContent = 'User / Secret'; secretTh.dataset.renamed = "1"; } }

    var btnAdd = document.querySelector('#cbi-telemt-user .cbi-button-add'); if (btnAdd && btnAdd.value !== 'Add user') btnAdd.value = 'Add user';
    if (btnAdd && !document.getElementById('telemt_user_hint')) {
        var hint = document.createElement('div'); hint.id = 'telemt_user_hint';
        hint.style.cssText = 'color:#d35400; font-weight:bold; font-size:0.85em; margin:8px 0 4px 0; padding:0; display:block; clear:both;';
        hint.textContent = 'At least one user is needed for MTProxy to start';
        var addRow = btnAdd.closest('.cbi-section-create') || btnAdd.parentNode;
        if (addRow && addRow.parentNode) addRow.parentNode.insertBefore(hint, addRow.nextSibling);
    }
    var newNameInp = document.querySelector('.cbi-section-create-name'); if(newNameInp && !newNameInp.dataset.maxInjected) { newNameInp.dataset.maxInjected = "1"; newNameInp.maxLength = 15; newNameInp.placeholder = "a-z, 0-9, _"; }

    var ipFlds = []; var m1 = document.querySelector('input[name*="cbid.telemt.general.external_ip"]'); if(m1) ipFlds.push(m1); var m2 = document.getElementById('telemt_mirror_ip'); if(m2) ipFlds.push(m2);
    ipFlds.forEach(function(ipFld) { if(!ipFld.dataset.refBtnInjected && ipFld.type !== "hidden") { ipFld.dataset.refBtnInjected = "1"; if(ipFld.parentNode) { ipFld.parentNode.style.display = 'flex'; ipFld.parentNode.style.alignItems = 'center'; var btn = document.createElement('input'); btn.type = 'button'; btn.className = 'cbi-button cbi-button-neural'; btn.value = 'Get IP'; btn.style.marginLeft = '5px'; btn.style.padding = '0 10px'; btn.style.height = ipFld.offsetHeight > 0 ? ipFld.offsetHeight + 'px' : '32px'; btn.addEventListener('click', function(){ fetchIPViaWget(this); }); ipFld.parentNode.appendChild(btn); } } });

    document.querySelectorAll('#cbi-telemt-upstream .cbi-section-node:not([id*="-template"])').forEach(function(row, index) {
        if (!row.dataset.cascadeInjected) {
            row.dataset.cascadeInjected = "1";
            var header = document.createElement('div');
            header.className = 'telemt-cascade-header';
            header.style.cssText = 'font-size:1.1em; font-weight:bold; color:#00a000; margin-bottom:15px; border-bottom:1px dashed rgba(0,160,0,0.4); padding-bottom:4px; cursor:pointer; display:flex; justify-content:space-between; align-items:center; user-select:none;';
            var titleSpan = document.createElement('span'); header.appendChild(titleSpan);
            var toggleSpan = document.createElement('span'); toggleSpan.innerHTML = '&#9660;'; header.appendChild(toggleSpan);
            row.insertBefore(header, row.firstChild);
            var updateTitle = function() {
                var nInp = row.querySelector('input[name*=".alias"]'); var aInp = row.querySelector('input[name*=".address"]'); var tSel = row.querySelector('select[name*=".type"]');
                var vName = (nInp && nInp.value.trim() !== "") ? nInp.value.trim() : '';
                var vAddr = (aInp && aInp.value.trim() !== "") ? aInp.value.trim() : '';
                var vProto = (tSel) ? tSel.value : 'direct';
                var text = 'Cascade #' + (index + 1);
                // Show: Cascade #1 - Name (socks5://addr) or Cascade #1 - Name (Direct)
                var suffix = (vProto === 'direct') ? 'Direct' : (vProto + '://' + vAddr);
                if (vName || suffix) { text += ' - ' + escHTML(vName ? vName : 'Unnamed'); text += ' <span style="opacity:0.6; font-weight:normal; font-size:0.9em;">(' + escHTML(suffix) + ')</span>'; }
                titleSpan.innerHTML = text;
            };
            setTimeout(updateTitle, 100); row.addEventListener('input', function(e) { if(e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT')) { updateTitle(); } });
            row.addEventListener('change', function(e) { if(e.target && e.target.tagName === 'SELECT') { updateTitle(); } });
            // Dynamic address placeholder based on selected protocol type
            var _tSel = row.querySelector('select[name*=".type"]');
            var _aInp = row.querySelector('input[name*=".address"]');
            if (_tSel && _aInp) {
                var _phMap = { 'socks4': '192.168.1.1:1080', 'socks5': '192.168.1.1:1080', 'direct': '', 'shadowsocks': '' };
                var _updatePh = function() { _aInp.placeholder = _phMap[_tSel.value] || '192.168.1.1:1080'; };
                _tSel.addEventListener('change', _updatePh);
                _updatePh();
            }
            // Exclude health badge and remove button from collapsible fields
            var fields = Array.from(row.children).filter(function(child) { return child !== header && !child.classList.contains('cbi-section-remove') && !child.classList.contains('up-health-badge'); });
            header.addEventListener('click', function(e) { var isHidden = fields[0].style.display === 'none'; fields.forEach(function(f) { f.style.display = isHidden ? '' : 'none'; }); toggleSpan.innerHTML = isHidden ? '&#9660;' : '&#9654;'; });
            var parent = row.parentElement; var rmDiv = parent ? (parent.querySelector(':scope > .cbi-section-remove') || null) : null;
            if (!rmDiv) { var sib = row.nextElementSibling; while (sib) { if (sib.classList && sib.classList.contains('cbi-section-remove')) { rmDiv = sib; break; } sib = sib.nextElementSibling; } }
            if (rmDiv) { row.appendChild(rmDiv); rmDiv.style.textAlign = 'left'; rmDiv.style.marginTop = '15px'; rmDiv.style.paddingTop = '15px'; rmDiv.style.borderTop = '1px dashed var(--border-color, rgba(128,128,128,0.3))'; var btnInput = rmDiv.querySelector('.cbi-button'); if (btnInput) { btnInput.style.float = 'none'; btnInput.style.display = 'inline-block'; } }
        }
    });

    document.querySelectorAll('#cbi-telemt-user .cbi-section-table-row:not([data-injected="1"])').forEach(function(row){
        if (isTemplateRow(row)) return;
        var secInp = row.querySelector('input[name*=".secret"]'); var niList = row.querySelectorAll('input[name*="max_tcp_conns"], input[name*="max_unique_ips"], input[name*="data_quota"], input[name*="expire_date"]'); var linkWrap = row.querySelector('.link-wrapper');
        if (!secInp || niList.length === 0 || !linkWrap) return; row.dataset.injected = "1";
        var match = secInp.name.match(/cbid\.telemt\.([^.]+)\.secret/); var uName = match ? match[1] : '?';

        if (is_owrt25) {
            // OWrt 25+ / SNAPSHOT: first column is missing (new LuCI JS DOM).
            // Inject user name above the secret field as a blue label.
            var secretTd = secInp.closest('td');
            if (secretTd) { var nameDiv = secretTd.querySelector('.telemt-fallback-name'); if (!nameDiv) { nameDiv = document.createElement('div'); nameDiv.className = 'telemt-fallback-name telemt-user-col-text'; nameDiv.style.cssText = 'margin-bottom: 6px; font-size: 1.1em; font-family: monospace; display: block; color: #005ce6 !important; font-weight: bold !important;'; secretTd.insertBefore(nameDiv, secretTd.firstChild); } nameDiv.innerText = '[ user: ' + uName + ' ]'; }
        } else {
            // OWrt 21-24: first column exists natively — just style it blue, never inject.
            var firstCell = row.firstElementChild;
            if (firstCell && !firstCell.contains(secInp)) { var span = firstCell.querySelector('.telemt-user-col-text'); if (!span) { span = document.createElement('span'); span.className = 'telemt-user-col-text'; span.style.cssText = 'color: #005ce6 !important; font-weight: bold !important; margin-bottom: 4px; display: block;'; firstCell.insertBefore(span, firstCell.firstChild); } span.innerText = uName; }
        }

        if(secInp) {
            if(secInp.value.trim() === "") { secInp.value = genRandHex(); secInp.dispatchEvent(new Event('change', {bubbles: true})); }
            secInp.dataset.prevVal = secInp.value; var wrapper = document.createElement('div'); wrapper.className = 'telemt-sec-wrap'; secInp.parentNode.insertBefore(wrapper, secInp); wrapper.appendChild(secInp);
            var grp = document.createElement('div'); grp.className = 'telemt-sec-btns'; var bG = document.createElement('input'); bG.type = 'button'; bG.className = 'cbi-button cbi-button-apply'; bG.value = 'Gen'; bG.addEventListener('click', function(){ secInp.value = genRandHex(); updateLinks(); }); var bR = document.createElement('input'); bR.type = 'button'; bR.className = 'cbi-button cbi-button-reset'; bR.value = 'Rev'; bR.addEventListener('click', function(){ secInp.value = secInp.dataset.prevVal; updateLinks(); }); grp.appendChild(bG); grp.appendChild(bR); wrapper.appendChild(grp);
        }

        var cb = row.querySelector('input[type="checkbox"][name*=".enabled"]');
        if (cb) { cb.addEventListener('change', function(e) { fetch(lu_current_url.split('#')[0], { method: 'POST', body: (function(){var f=new FormData(); f.append('log_ui_event', '1'); f.append('msg', "User " + uName + " manually " + (e.target.checked ? "Resumed" : "Paused")); return f;})() }); }); }

        niList.forEach(function(ni){
            var propName = ni.name.match(/([^\.]+)$/); var fName = propName ? propName[1] : "limit";
            ni.addEventListener('change', function(e) {
                fetch(lu_current_url.split('#')[0], { method: 'POST', body: (function(){var f=new FormData(); f.append('log_ui_event', '1'); f.append('msg', "User " + uName + " " + fName + " changed to: " + (e.target.value || "unlimited")); return f;})() });
                if (fName === 'expire_date' || fName === 'data_quota') { if (cb && !cb.checked) { cb.checked = true; fetch(lu_current_url.split('#')[0], { method: 'POST', body: (function(){var f=new FormData(); f.append('log_ui_event', '1'); f.append('msg', "User " + uName + " auto-resumed due to " + fName + " update"); return f;})() }); } }
            });
            var wrapper = document.createElement('div'); wrapper.className = 'telemt-num-wrap'; ni.parentNode.insertBefore(wrapper, ni); wrapper.appendChild(ni);
            if(ni.name.indexOf('expire_date') !== -1) { var calContainer = document.createElement('div'); calContainer.className = 'telemt-cal-wrap'; var calBtn = document.createElement('input'); calBtn.type = 'button'; calBtn.className = 'cbi-button cbi-button-action telemt-btn-cal'; calBtn.title = 'Select Date'; calBtn.value = ' '; var picker = document.createElement('input'); picker.type = 'datetime-local'; picker.className = 'telemt-cal-picker'; picker.addEventListener('change', function(e) { var val = e.target.value; if(val) { var parts = val.split('T'); var dParts = parts[0].split('-'); if(dParts.length === 3) { ni.value = dParts[2] + '.' + dParts[1] + '.' + dParts[0] + ' ' + parts[1]; ni.dispatchEvent(new Event('change', {bubbles:true})); } } }); calContainer.appendChild(calBtn); calContainer.appendChild(picker); wrapper.appendChild(calContainer); }
            var bD = document.createElement('input'); bD.type = 'button'; bD.className = 'cbi-button cbi-button-reset telemt-btn-cross'; bD.title = 'Reset value'; bD.value = ' '; bD.addEventListener('click', function(){ ni.value = ''; ni.dispatchEvent(new Event('change', {bubbles:true})); }); wrapper.appendChild(bD);
        });

        if(linkWrap) { var btnGrp = document.createElement('div'); btnGrp.className = 'link-btn-group'; var bC = document.createElement('input'); bC.type = 'button'; bC.className = 'cbi-button cbi-button-action btn-copy-custom'; bC.value = 'Copy'; bC.addEventListener('click', function(){ copyProxyLink(this); }); btnGrp.appendChild(bC); var bQ = document.createElement('input'); bQ.type = 'button'; bQ.className = 'cbi-button cbi-button-neural btn-qr-custom'; bQ.value = 'QR'; bQ.addEventListener('click', function(){ showQRModal(linkWrap.querySelector('.user-link-out').value); }); btnGrp.appendChild(bQ); linkWrap.appendChild(btnGrp); }
    });
}

var metricsTimer = null; var fwTimer = null;

function schedulePoll() {
    if (window._telemtFetching) return;
    fetchMetrics().finally(function() {
        // Use 500ms rapid poll during daemon startup, 2500ms normally.
        if (metricsTimer !== null) { metricsTimer = setTimeout(schedulePoll, window._telemtFastPoll ? 500 : 2500); }
    });
}

function startTimers() {
    if (metricsTimer === null) { metricsTimer = setTimeout(schedulePoll, 2500); schedulePoll(); }
    if (!fwTimer) fwTimer = setInterval(updateFWStatus, 15000);
}

function stopTimers() {
    if (metricsTimer !== null) { clearTimeout(metricsTimer); metricsTimer = null; }
    if (fwTimer) { clearInterval(fwTimer); fwTimer = null; }
}

document.addEventListener('visibilitychange', function () { if (document.hidden) { stopTimers(); } else { window._telemtLastTime = 0; updateFWStatus(); startTimers(); } });
document.addEventListener('input', function(e) { if (e.target && e.target.matches('input, select')) { if(e.target.id === 'telemt_mirror_ip') { var master = document.querySelector('input[name*="cbid.telemt.general.external_ip"]'); if(master) { master.value = e.target.value; master.dispatchEvent(new Event('change')); } } else if (e.target.name && e.target.name.indexOf('cbid.telemt.general.external_ip') > -1) { var mirror = document.getElementById('telemt_mirror_ip'); if(mirror) mirror.value = e.target.value; } updateLinks(); } });

function initTelemt() {
    injectUI(); updateLinks(); updateFWStatus(); startTimers();
    setTimeout(function(){ injectUI(); updateLinks(); }, 200);
    setTimeout(function(){ injectUI(); updateLinks(); updateFWStatus(); }, 1200);
    if (window.location.search.indexOf('import_ok=') > -1) { var match = window.location.search.match(/import_ok=(\d+)/); if (match && match[1]) { setTimeout(function() { alert("Successfully imported " + match[1] + " users from CSV!"); }, 300); if (window.history && window.history.replaceState) { window.history.replaceState({}, document.title, window.location.protocol + "//" + window.location.host + window.location.pathname); } } }

    if (typeof window.MutationObserver !== 'undefined') {
        var _injecting = false;
        var domObserver = new MutationObserver(function(mutations) {
            scheduleRepack();
            if (_injecting) return;
            var needsUpdate = false;
            for (var i = 0; i < mutations.length; i++) { if (mutations[i].target.id === 'cbi-telemt-user' || mutations[i].target.id === 'cbi-telemt-upstream' || (mutations[i].target.closest && mutations[i].target.closest('#cbi-telemt-user'))) { needsUpdate = true; break; } }
            if (needsUpdate) { _injecting = true; injectUI(); updateLinks(); _injecting = false; }
        });
        domObserver.observe(document.getElementById('maincontent') || document.body, { childList: true, subtree: true });
    } else { setInterval(function(){ injectUI(); updateLinks(); scheduleRepack(); }, 2500); }
}
if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', initTelemt); } else { initTelemt(); }
</script>
]] .. (m.description or "")

return m
