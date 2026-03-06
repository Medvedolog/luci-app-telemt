-- ==============================================================================
-- Telemt CBI Model (Configuration Binding Interface)
-- Version: 3.2.2-1 (API v1, Smart Hot-Reload, Action Bar Dashboard)
-- ==============================================================================

local sys = require "luci.sys"
local http = require "luci.http"
local dsp = require "luci.dispatcher"
local uci_cursor = require("luci.model.uci").cursor()

-- Universal AJAX kill switch: suppresses 436 errors and prevents footer rendering
local function end_ajax()
    pcall(function() if dsp.context then dsp.context.dispatched = true end end)
    pcall(function() http.close() end)
end

local function has_cmd(c) return (sys.call("command -v " .. c .. " >/dev/null 2>&1") == 0) end
local fetch_bin = nil; if has_cmd("wget") then fetch_bin = "wget" elseif has_cmd("uclient-fetch") then fetch_bin = "uclient-fetch" end

local function read_file(path)
    local f = io.open(path, "r"); if not f then return "" end
    local d = f:read("*all") or ""; f:close(); return d
end

local is_owrt25_lua = "false"
local ow_rel = sys.exec("cat /etc/openwrt_release 2>/dev/null") or ""
if ow_rel:match("DISTRIB_RELEASE='25") or ow_rel:match('DISTRIB_RELEASE="25') or ow_rel:match("SNAPSHOT") or ow_rel:match("%-rc") then is_owrt25_lua = "true" end

local _unpack = unpack or table.unpack
local _ok_url, current_url = pcall(function() if dsp.context and dsp.context.request then return dsp.build_url(_unpack(dsp.context.request)) end return nil end)
if not _ok_url or not current_url or current_url == "" then current_url = dsp.build_url("admin", "services", "telemt") end
local safe_url = current_url:gsub('"', '\\"'):gsub('<', '&lt;'):gsub('>', '&gt;')

local function tip(txt) return string.format([[<span class="telemt-tip" title="%s">(?)</span>]], txt:gsub('"', '&quot;')) end

-- ==============================================================================
-- AJAX DISPATCHER (Bulletproof Mode)
-- ==============================================================================
local is_post = (http.getenv("REQUEST_METHOD") == "POST")

if is_post and http.formvalue("log_ui_event") == "1" then
    local msg = http.formvalue("msg")
    if msg then sys.call(string.format("logger -t telemt %q", "WebUI: " .. msg:gsub("[%c]", " "):gsub("[^A-Za-z0-9 _.%-%:]", ""):sub(1, 128))) end
    http.prepare_content("text/plain")
    pcall(function() http.write("ok") end)
    end_ajax(); return
end

if is_post and http.formvalue("auto_pause_user") then
    local u = http.formvalue("auto_pause_user"); local reason = http.formvalue("reason") or "Limit Exceeded"
    if u and u ~= "" then
        uci_cursor:set("telemt", u, "enabled", "0")
        uci_cursor:save("telemt"); uci_cursor:commit("telemt")
        sys.call(string.format("logger -t telemt 'WebUI: Auto-paused user %s (Reason: %s)'", u, reason))
        sys.call("/etc/init.d/telemt reload >/dev/null 2>&1 &")
    end
    http.prepare_content("text/plain")
    pcall(function() http.write("ok") end)
    end_ajax(); return
end

if is_post and http.formvalue("reset_config") == "1" then
    sys.call("logger -t telemt 'WebUI: FACTORY RESET ALL SETTINGS'")
    local default_uci = "config telemt 'general'\n\toption enabled '0'\n\toption mode 'tls'\n\toption domain 'google.com'\n\toption port '4443'\n\toption metrics_port '9092'\n\toption api_port '9091'\n\toption api_enabled '1'\n\toption minimal_runtime_enabled '1'\n\toption metrics_allow_lo '1'\n\toption metrics_allow_lan '1'\n\toption log_level 'normal'\n"
    local f = io.open("/etc/config/telemt", "w")
    if f then f:write(default_uci); f:close() end
    sys.call("rm -f /var/etc/telemt.toml")
    sys.call("/etc/init.d/telemt stop 2>/dev/null")
    http.prepare_content("text/plain")
    pcall(function() http.write("ok") end)
    end_ajax(); return
end

if is_post and http.formvalue("reset_stats") == "1" then sys.call("logger -t telemt 'WebUI: Executed manual Reset Traffic Stats'; rm -f /tmp/telemt_stats.txt") end

-- Safe specific process kill logic
local safe_kill_cmd = "/etc/init.d/telemt run_save_stats 2>/dev/null; /etc/init.d/telemt stop 2>/dev/null; t_pid=$(pidof telemt | awk '{print $1}'); [ -n \"$t_pid\" ] && kill -9 \"$t_pid\" 2>/dev/null"

if is_post and http.formvalue("start") == "1" then sys.call("logger -t telemt 'WebUI: Manual START service requested'; /etc/init.d/telemt start") end
if is_post and http.formvalue("stop") == "1" then sys.call("logger -t telemt 'WebUI: Manual STOP service requested'; " .. safe_kill_cmd) end
if is_post and http.formvalue("restart") == "1" then sys.call("logger -t telemt 'WebUI: Manual RESTART service requested'; " .. safe_kill_cmd .. "; /etc/init.d/telemt start") end

-- Bot Process Controls
if is_post and http.formvalue("start_bot") == "1" then sys.call("logger -t telemt 'WebUI: Manual START Bot requested'; /etc/init.d/telemt_bot start") end
if is_post and http.formvalue("stop_bot") == "1" then sys.call("logger -t telemt 'WebUI: Manual STOP Bot requested'; /etc/init.d/telemt_bot stop") end
if is_post and http.formvalue("restart_bot") == "1" then sys.call("logger -t telemt 'WebUI: Manual RESTART Bot requested'; /etc/init.d/telemt_bot restart") end

if is_post and http.formvalue("export_config") == "1" then
    local conf = read_file("/var/etc/telemt.toml")
    if conf == "" then conf = "# telemt.toml not found or empty\n" end
    http.prepare_content("application/toml")
    http.header("Content-Disposition", "attachment; filename=\"telemt.toml\"")
    pcall(function() http.write(conf) end)
    end_ajax(); return
end

if http.formvalue("get_fw_status") == "1" then
    local afw = uci_cursor:get("telemt", "general", "auto_fw") or "0"
    local port = tonumber(uci_cursor:get("telemt", "general", "port")) or 4443
    local cmd = string.format("/bin/sh -c \"iptables-save 2>/dev/null | grep -qiE 'Allow-Telemt-Magic|dport.*%d.*accept' || nft list ruleset 2>/dev/null | grep -qiE 'Allow-Telemt-Magic|dport.*%d.*accept'\"", port, port)
    local is_physically_open = (sys.call(cmd) == 0)
    local procd_check = sys.exec("ubus call service list '{\"name\":\"telemt\"}' 2>/dev/null")
    local is_procd_open = (procd_check and procd_check:match("Allow%-Telemt%-Magic") ~= nil)
    local is_running = (sys.call("pidof telemt >/dev/null 2>&1") == 0)
    local status_msg, tip_msg = "<span style='color:red; font-weight:bold'>CLOSED</span>", "(Port not found in rules)"
    if is_physically_open then status_msg = "<span style='color:green; font-weight:bold'>OPEN (OK)</span>"; tip_msg = (afw == "0") and "(Auto-FW off, but port is open)" or ""
    elseif is_procd_open and is_running then status_msg = "<span style='color:green; font-weight:bold'>OPEN (OK)</span>"; tip_msg = "(Visible via ubus API)" end
    if not is_running then status_msg = "<span style='color:#d9534f; font-weight:bold'>SERVICE STOPPED</span> <span style='color:#888'>|</span> " .. status_msg end
    http.prepare_content("text/plain")
    pcall(function() http.write(status_msg .. (tip_msg ~= "" and " <span style='color:#888; font-size:0.85em; margin-left:5px;'>" .. tip_msg .. "</span>" or "")) end)
    end_ajax(); return
end

if http.formvalue("get_metrics") == "1" then
    local m_port = tonumber(uci_cursor:get("telemt", "general", "metrics_port")) or 9092
    local metrics = ""
    if sys.call("pidof telemt >/dev/null 2>&1") == 0 then
        local fetch_cmd = (fetch_bin == "wget") and "wget -q --timeout=3 -O -" or "uclient-fetch -q --timeout=3 -O -"
        metrics = sys.exec(string.format("%s 'http://127.0.0.1:%d/metrics' 2>/dev/null", fetch_cmd, m_port) .. " | grep -E '^telemt_user|^telemt_uptime|^telemt_connections|^telemt_desync|^telemt_upstream_connect'") or ""
        local scanners = sys.exec(string.format("%s 'http://127.0.0.1:%d/beobachten' 2>/dev/null", fetch_cmd, m_port) .. " | grep -cE '^[0-9a-fA-F:\\.]+'") or "0"
        metrics = metrics .. "\ntelemt_active_scanners_count " .. scanners:gsub("%s+", "") .. "\n"
    end
    local f = io.open("/tmp/telemt_stats.txt", "r")
    if f then metrics = metrics .. "\n# ACCUMULATED\n"; for line in f:lines() do local u, tx, rx = line:match("^(%S+) (%S+) (%S+)$"); if u then metrics = metrics .. string.format("telemt_accumulated_tx{user=\"%s\"} %s\ntelemt_accumulated_rx{user=\"%s\"} %s\n", u, tx, u, rx) end end; f:close() end
    http.prepare_content("text/plain")
    pcall(function() http.write(metrics) end)
    end_ajax(); return
end

if http.formvalue("get_scanners") == "1" then
    local m_port = tonumber(uci_cursor:get("telemt", "general", "metrics_port")) or 9092
    local fetch_cmd = (fetch_bin == "wget") and "wget -q --timeout=3 -O -" or "uclient-fetch -q --timeout=3 -O -"
    local res = sys.exec(string.format("%s 'http://127.0.0.1:%d/beobachten' 2>/dev/null", fetch_cmd, m_port))
    if not res or res:gsub("%s+", "") == "" then res = "No active scanners detected or proxy is offline." end
    http.prepare_content("text/plain")
    pcall(function() http.write(res) end)
    end_ajax(); return
end

if http.formvalue("get_log") == "1" then
    http.prepare_content("text/plain")
    local cmd = "logread -e 'telemt' | tail -n 50 2>/dev/null"
    if has_cmd("timeout") then cmd = "timeout 2 " .. cmd end
    local log_data = sys.exec(cmd)
    if not log_data or log_data:gsub("%s+", "") == "" then log_data = "No logs found." end
    log_data = log_data:gsub("\27%[[%d;]*m", "")
    pcall(function() http.write(log_data) end)
    end_ajax(); return
end

if http.formvalue("get_wan_ip") == "1" then
    local fetch_cmd = (fetch_bin == "wget") and "wget -q --timeout=3 -O -" or "uclient-fetch -q --timeout=3 -O -"
    local ip = (sys.exec(fetch_cmd .. " https://ipv4.internet.yandex.net/api/v0/ip 2>/dev/null") or ""):gsub("%s+", ""):gsub("\"", "")
    if not ip:match("^%d+%.%d+%.%d+%.%d+$") then ip = (sys.exec(fetch_cmd .. " https://checkip.amazonaws.com 2>/dev/null") or ""):gsub("%s+", "") end
    http.prepare_content("text/plain")
    pcall(function() http.write(ip:match("^%d+%.%d+%.%d+%.%d+$") and ip or "0.0.0.0") end)
    end_ajax(); return
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
    if has_cmd("timeout") then cmd = "timeout 2 " .. cmd end
    http.prepare_content("image/svg+xml")
    pcall(function() http.write(sys.exec(cmd)) end)
    end_ajax(); return
end

local function norm_secret(s) if not s then return nil end; s = s:match("secret=(%x+)") or s; local hex = s:match("(%x+)"); if not hex then return nil end; local pfx = hex:sub(1,2):lower(); if pfx == "ee" or pfx == "dd" then hex = hex:sub(3) end; if #hex < 32 then return nil end; return hex:sub(1, 32):lower() end

if is_post and http.formvalue("import_users") == "1" then
    local csv = http.formvalue("csv_data")
    if csv and csv ~= "" then
        local valid_users = {}; local char_cr, char_lf, bom = string.char(13), string.char(10), string.char(239, 187, 191)
        csv = csv:gsub("^" .. bom, ""):gsub(char_cr .. char_lf, char_lf):gsub(char_cr, char_lf)
        for line in csv:gmatch("[^" .. char_lf .. "]+") do
            if not line:match("^username,") and not line:match("^<") then
                local p = {}; for f in (line..","):gmatch("([^,]*),") do table.insert(p, (f:gsub("^%s*(.-)%s*$", "%1"))) end
                local u, sec, c, uips, q, exp = p[1], p[2], p[3], p[4], p[5], p[6]; local sec_clean = norm_secret(sec)
                if c and c ~= "" and c ~= "unlimited" and not c:match("^%d+$") then c = "" end
                if uips and uips ~= "" and uips ~= "unlimited" and not uips:match("^%d+$") then uips = "" end
                if q and q ~= "" and q ~= "unlimited" and not q:match("^%d+%.?%d*$") then q = "" end
                if u and u ~= "" and u:match("^[A-Za-z0-9_]+$") and #u <= 15 and sec_clean then table.insert(valid_users, {u=u, sec=sec_clean, c=c, uips=uips, q=q, exp=exp}) end
            end
        end
        if #valid_users > 0 then
            if http.formvalue("import_mode") == "replace" then local to_delete = {}; uci_cursor:foreach("telemt", "user", function(s) table.insert(to_delete, s['.name']) end); for _, name in ipairs(to_delete) do uci_cursor:delete("telemt", name) end end
            for _, v in ipairs(valid_users) do
                uci_cursor:set("telemt", v.u, "user"); uci_cursor:set("telemt", v.u, "secret", v.sec); uci_cursor:set("telemt", v.u, "enabled", "1")
                if v.c and v.c ~= "" then uci_cursor:set("telemt", v.u, "max_tcp_conns", v.c) else uci_cursor:delete("telemt", v.u, "max_tcp_conns") end
                if v.uips and v.uips ~= "" then uci_cursor:set("telemt", v.u, "max_unique_ips", v.uips) else uci_cursor:delete("telemt", v.u, "max_unique_ips") end
                if v.q and v.q ~= "" then uci_cursor:set("telemt", v.u, "data_quota", v.q) else uci_cursor:delete("telemt", v.u, "data_quota") end
                if v.exp and v.exp:match("^%d%d%.%d%d%.%d%d%d%d %d%d:%d%d$") then uci_cursor:set("telemt", v.u, "expire_date", v.exp) else uci_cursor:delete("telemt", v.u, "expire_date") end
            end
            uci_cursor:save("telemt"); uci_cursor:commit("telemt")
            sys.call("logger -t telemt \"WebUI: Successfully imported " .. #valid_users .. " users via CSV.\"")
            http.redirect(current_url .. (current_url:match("?") and "&" or "?") .. "import_ok=" .. tostring(#valid_users)); return
        end
    end
    http.redirect(current_url); return
end

local clean_csv = "username,secret,max_tcp_conns,max_unique_ips,data_quota,expire_date\n"
uci_cursor:foreach("telemt", "user", function(s) clean_csv = clean_csv .. string.format("%s,%s,%s,%s,%s,%s\n", s['.name'] or "", s.secret or "", s.max_tcp_conns or "", s.max_unique_ips or "", s.data_quota or "", s.expire_date or "") end)
clean_csv = clean_csv:gsub("\n", "\\n"):gsub("\r", "")

local bin_info = ""
if not is_ajax then
    local bin_path = (sys.exec("command -v telemt 2>/dev/null") or ""):gsub("%s+", "")
    if bin_path == "" then bin_info = "<span style='color:#d9534f; font-weight:bold; font-size:0.9em;'>Not installed (telemt binary not found)</span>"
    else bin_info = string.format("<small style='opacity: 0.6;'>%s (v%s)</small>", bin_path, (read_file("/var/etc/telemt.version"):gsub("%s+", "")) == "" and "unknown" or (read_file("/var/etc/telemt.version"):gsub("%s+", ""))) end
end

m = Map("telemt", "Telegram Proxy (MTProto)", [[Multi-user proxy server based on <a href="https://github.com/telemt/telemt" target="_blank" style="text-decoration:none; color:inherit; font-weight:bold; border-bottom: 1px dotted currentColor;">telemt</a>.<br><b>LuCI App Version: <a href="https://github.com/Medvedolog/luci-app-telemt" target="_blank" style="text-decoration:none; color:inherit; border-bottom: 1px dotted currentColor;">3.2.2-1</a></b> | <span style='color:#d35400; font-weight:bold;'>Requires telemt v3.2.1+</span>]])
m.on_commit = function(self) sys.call("logger -t telemt 'WebUI: Config saved. Dumping stats before procd reload...'; /etc/init.d/telemt run_save_stats 2>/dev/null") end

s = m:section(NamedSection, "general", "telemt")
s.anonymous = true

-- TABS DEFINITION
s:tab("general", "General Settings")
s:tab("upstreams", "Upstream Proxies")
s:tab("users", "Users")
s:tab("advanced", "Advanced Tuning")
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
function postAction(action) {
    var form = document.createElement('form'); form.method = 'POST'; form.action = lu_current_url.split('?')[0].split('#')[0];
    var inp = document.createElement('input'); inp.type = 'hidden'; inp.name = action; inp.value = '1'; form.appendChild(inp);
    var tokenVal = null;
    var tokenNode = document.querySelector('input[name="token"]');
    if (tokenNode) { tokenVal = tokenNode.value; }
    else if (typeof L !== 'undefined' && L.env) { tokenVal = L.env.token || L.env.requesttoken || null; }
    if (!tokenVal) {
        var m = document.cookie.match(/(?:sysauth_http|sysauth)=([^;]+)/);
        if (m) tokenVal = m[1];
    }
    if (tokenVal) {
        var t = document.createElement('input'); t.type = 'hidden'; t.name = 'token'; t.value = tokenVal; form.appendChild(t);
    }
    document.body.appendChild(form); form.submit();
}
setTimeout(function(){
    var b1=document.getElementById('btn_telemt_start'); if(b1) b1.addEventListener('click', function(){ logAction('Manual Start'); postAction('start'); });
    var b2=document.getElementById('btn_telemt_stop'); if(b2) b2.addEventListener('click', function(){ logAction('Manual Stop'); postAction('stop'); });
    var b3=document.getElementById('btn_telemt_restart'); if(b3) b3.addEventListener('click', function(){ logAction('Manual Restart'); postAction('restart'); });
}, 500);
</script>]], current_url)

local pid = not is_ajax and (sys.exec("pidof telemt | awk '{print $1}'") or ""):gsub("%s+", "") or ""
local process_status = "<span style='color:#d9534f; font-weight:bold;'>STOPPED</span><br>" .. bin_info
if pid ~= "" and sys.call("kill -0 " .. pid .. " 2>/dev/null") == 0 then process_status = string.format("<span style='color:green;font-weight:bold'>RUNNING (PID: %s)</span><br>%s", pid, bin_info) end
local st = s:taboption("general", DummyValue, "_status", "Process Status"); st.rawhtml = true; st.value = process_status

local mode = s:taboption("general", ListValue, "mode", "Protocol Mode" .. tip("FakeTLS: HTTPS masking. DD: Old obfuscation. Classic: MTProto without masking."))
mode:value("tls", "FakeTLS (Recommended)"); mode:value("dd", "DD (Random Padding)"); mode:value("classic", "Classic"); mode:value("all", "All together (Debug)"); mode.default = "tls"

local lfmt = s:taboption("general", ListValue, "_link_fmt", "Link Format to Display" .. tip("Select which protocol link to show in the Users tab for copying."))
lfmt:depends("mode", "all"); lfmt:value("tls", "FakeTLS (Recommended)"); lfmt:value("dd", "Secure (DD)"); lfmt:value("classic", "Classic"); lfmt.default = "tls"

local dom = s:taboption("general", Value, "domain", "FakeTLS Domain" .. tip("Unauthenticated DPI traffic will be routed here. Must be ASCII only."))
dom.datatype = "hostname"; dom.default = "google.com"; dom.description = "<span class='warn-txt' style='color:#d35400; font-weight:bold;'>Warning: Change the default domain!</span>"
dom:depends("mode", "tls"); dom:depends("mode", "all")

local saved_ip = m.uci:get("telemt", "general", "external_ip")
if type(saved_ip) == "table" then saved_ip = saved_ip[1] or "" end; saved_ip = saved_ip or ""; if saved_ip:match("%s") then saved_ip = saved_ip:match("^([^%s]+)") end

local myip = s:taboption("general", Value, "external_ip", "External IP / DynDNS" .. tip("IP address or domain used strictly for generating tg:// links in UI."))
myip.datatype = "string"; myip.default = saved_ip; function myip.validate(self, value) if value and #value > 0 then value = value:match("^([^%s]+)"); if not value:match("^[a-zA-Z0-9%-%.:]+$") then return nil, "Invalid characters!" end end; return value end

local p = s:taboption("general", Value, "port", "MTProxy Port" .. tip("The port on which the MTProxy server will listen for connections.")); p.datatype = "port"; p.rmempty = false

local afw = s:taboption("general", Flag, "auto_fw", "Auto-open Port (Magic)" .. tip("Uses procd API to open port in RAM. Rule will not appear in Firewall menu. Closes automatically if proxy stops."))
afw.default = "0"; afw.description = "<div style='margin-top:5px; padding:8px; background:rgba(128,128,128,0.1); border-left:3px solid #00a000; font-size:0.9em;'><b>Current Status:</b> <span id='fw_status_span' style='color:#888; font-style:italic;'>Checking...</span></div>"

local ll = s:taboption("general", ListValue, "log_level", "Log Level" .. tip("Verbosity of telemt daemon log output.")); ll:value("debug", "Debug"); ll:value("verbose", "Verbose"); ll:value("normal", "Normal (default)"); ll:value("silent", "Silent"); ll.default = "normal"

-- === TAB: UPSTREAMS (CASCADES) ===
local up_anchor = s:taboption("upstreams", DummyValue, "_up_anchor", ""); up_anchor.rawhtml = true; up_anchor.default = '<div id="upstreams_tab_anchor" style="display:none"></div>'
local up_master = s:taboption("upstreams", Flag, "enable_upstreams", "Enable All Cascades" .. tip("Master switch for Upstream Proxies. Disabling this ignores the list below.")); up_master.default = "1"

s_up = m:section(TypedSection, "upstream", "Upstream Proxies (Cascades)", "Chain your outgoing Telegram traffic through other servers to bypass ISP DPI.<br><span style='color:#555;'><b>Note:</b> If no upstreams are enabled, the proxy will gracefully fallback to <b>Direct Connection</b>.</span>")
s_up.addremove = true; s_up.anonymous = true

local u_lbl = s_up:option(Value, "alias", "Cascade Name" .. tip("Optional. Latin letters, numbers and spaces only."))
u_lbl.placeholder = "e.g. Frankfurt Server"
function u_lbl.validate(self, v, section)
    if not v or v == "" then return v end
    if not v:match("^[A-Za-z0-9 _]+$") then return nil, "Only Latin letters, numbers and spaces allowed!" end
    local count = 0
    uci_cursor:foreach("telemt", "upstream", function(s) if s.alias == v and s['.name'] ~= section then count = count + 1 end end)
    if count > 0 then return nil, "Cascade name must be unique!" end
    return v
end

local uen = s_up:option(Flag, "enabled", "Active"); uen.default = "1"; uen.rmempty = false
local ut = s_up:option(ListValue, "type", "Protocol")
ut:value("direct", "Direct"); ut:value("socks4", "SOCKS4"); ut:value("socks5", "SOCKS5"); ut.default = "socks5"

local ua = s_up:option(Value, "address", "Address" .. tip("Format: IP:PORT or HOST:PORT. No hyphens allowed."))
ua.datatype = "hostport"; ua:depends("type", "socks4"); ua:depends("type", "socks5")
ua.placeholder = "e.g. 192.168.1.100:1080"
function ua.validate(self, v) if v and v ~= "" and not v:match("^[A-Za-z0-9%.%:]+$") then return nil, "Invalid characters! No hyphens allowed." end return v end

local uu = s_up:option(Value, "username", "Username" .. tip("Optional. Latin letters and numbers only, no hyphens."))
function uu.validate(self, v) if v and v ~= "" and not v:match("^[A-Za-z0-9_]+$") then return nil, "Only Latin letters, numbers and underscores allowed!" end return v end

local up = s_up:option(Value, "password", "Password" .. tip("Optional. Password for SOCKS. Latin only, no hyphens.")); up.password = true
function up.validate(self, v) if v and v ~= "" and not v:match("^[A-Za-z0-9_]+$") then return nil, "Only Latin letters, numbers and underscores allowed!" end return v end

local uw = s_up:option(Value, "weight", "Weight" .. tip("Routing priority weight. Default: 10.")); uw.datatype = "uinteger"; uw.default = "10"; uw.placeholder = "10"

-- === TAB: ADVANCED ===
local hnet = s:taboption("advanced", DummyValue, "_head_net"); hnet.rawhtml = true; hnet.default = "<h3>Network Listeners</h3>"
s:taboption("advanced", Flag, "listen_ipv4", "Enable IPv4 Listener" .. tip("Listen for incoming IPv4 connections on 0.0.0.0")).default = "1"
s:taboption("advanced", Flag, "listen_ipv6", "Enable IPv6 Listener (::)" .. tip("Listen for incoming IPv6 connections on ::")).default = "0"
local pref_ip = s:taboption("advanced", ListValue, "prefer_ip", "Preferred IP Protocol" .. tip("Which protocol to prefer when connecting to Telegram DC.")); pref_ip:value("4", "IPv4"); pref_ip:value("6", "IPv6"); pref_ip.default = "4"

local hme = s:taboption("advanced", DummyValue, "_head_me"); hme.rawhtml = true; hme.default = "<h3 style='margin-top:20px;'>Middle-End Proxy</h3>"
local mp = s:taboption("advanced", Flag, "use_middle_proxy", "Use ME Proxy" .. tip("Allows Media/CDN (DC=203) to work correctly.")); mp.default = "0"; mp.description = "<span style='color:#d35400; font-weight:bold;'>Requires public IP on interface OR NAT 1:1 with STUN enabled.</span>"
local stun = s:taboption("advanced", Flag, "use_stun", "Enable STUN-probing" .. tip("Leave enabled if your server is behind NAT. Required for ME proxy on standard setups.")); stun:depends("use_middle_proxy", "1"); stun.default = "0"

-- Adaptive ME Parameters
local fmode = s:taboption("advanced", ListValue, "me_floor_mode", "ME Floor Mode" .. tip("Static maintains fixed pool, Adaptive shrinks pool during idle to avoid DPI attention.")); fmode:value("static", "Static (Fixed)"); fmode:value("adaptive", "Adaptive (Dynamic)"); fmode.default = "static"; fmode:depends("use_middle_proxy", "1")
s:taboption("advanced", Value, "me_adaptive_floor_idle_secs", "Adaptive Idle (sec)" .. tip("Time without traffic before shrinking the pool. Default: 600.")):depends("me_floor_mode", "adaptive")
s:taboption("advanced", Value, "me_adaptive_floor_recover_grace_secs", "Adaptive Grace (sec)" .. tip("Grace period preventing pool flapping on short bursts. Default: 120.")):depends("me_floor_mode", "adaptive")
s:taboption("advanced", Value, "me_adaptive_floor_min_writers_single_endpoint", "Adaptive Min Writers" .. tip("Minimum writers to keep alive during deep idle. Default: 1.")):depends("me_floor_mode", "adaptive")

s:taboption("advanced", Value, "me_pool_size", "ME Pool Size" .. tip("Desired number of concurrent ME writers in pool. Default: 16.")):depends("use_middle_proxy", "1")
s:taboption("advanced", Value, "me_warm_standby", "ME Warm Standby" .. tip("Pre-initialized warm-standby ME connections kept idle. Default: 8.")):depends("use_middle_proxy", "1")

-- Single Endpoint Resilience & Hardswap
s:taboption("advanced", Value, "me_single_endpoint_shadow_writers", "Shadow Writers" .. tip("Hidden backup connections for fragile single-endpoint DCs. Default: 2.")):depends("use_middle_proxy", "1")
local outm = s:taboption("advanced", Flag, "me_single_endpoint_outage_mode_enabled", "Outage Recovery Mode" .. tip("Aggressive reconnect loop if all writers die. Default: enabled.")); outm.default = "1"; outm:depends("use_middle_proxy", "1")
s:taboption("advanced", Flag, "me_single_endpoint_outage_disable_quarantine", "Bypass Quarantine" .. tip("Ignore reconnect delays during an outage to restore fast. Default: enabled.")):depends("me_single_endpoint_outage_mode_enabled", "1")
s:taboption("advanced", Value, "me_single_endpoint_shadow_rotate_every_secs", "Shadow Rotate (sec)" .. tip("Period to refresh idle shadow writers. Default: 900.")):depends("use_middle_proxy", "1")

s:taboption("advanced", Flag, "hardswap", "ME Pool Hardswap" .. tip("Enable C-like hard-swap for ME pool generations.")):depends("use_middle_proxy", "1")
s:taboption("advanced", Value, "me_drain_ttl", "ME Drain TTL (sec)" .. tip("Drain-TTL in seconds for stale ME writers. Default: 90.")):depends("use_middle_proxy", "1")
local adeg = s:taboption("advanced", Flag, "auto_degradation", "Auto-Degradation" .. tip("Enable auto-degradation from ME to Direct-DC if ME fails. Default: enabled.")); adeg.default = "1"; adeg:depends("use_middle_proxy", "1")
s:taboption("advanced", Value, "degradation_min_dc", "Degradation Min DC" .. tip("Minimum unavailable ME DC groups before degrading. Default: 2.")):depends("auto_degradation", "1")

local hadv = s:taboption("advanced", DummyValue, "_head_adv"); hadv.rawhtml = true
hadv.default = [[<div style="display:block; width:100%;"><details id="telemt_adv_opts_details" style="display:block; width:100%; box-sizing:border-box; margin-top:20px; padding:10px; background:rgba(128,128,128,0.05); border:1px solid rgba(128,128,128,0.3); border-radius:6px; cursor:pointer;"><summary style="font-weight:bold; font-size:1.05em; outline:none; cursor:pointer;">Additional Options (Click to expand)</summary><p style="font-size:0.85em; opacity:0.8; margin-top:5px; margin-bottom:0;">Extra proxy settings and overrides.</p></details></div><script>setTimeout(function(){var d = document.getElementById('telemt_adv_opts_details');if(!d) return;var tM = ['desync_all_full', 'mask_proxy_protocol', 'announce_ip', 'ad_tag', 'fake_cert_len', 'tls_full_cert_ttl_secs', 'ignore_time_skew'];tM.forEach(function(n){var el = document.querySelector('.cbi-value[data-name="' + n + '"]') || document.getElementById('cbi-telemt-general-' + n) || document.querySelector('[id$="-' + n + '"]');if(el) { el.style.paddingLeft = '15px'; d.appendChild(el); }});}, 300);</script>]]
s:taboption("advanced", Flag, "desync_all_full", "Full Crypto-Desync Logs" .. tip("Emit full forensic logs for every event. Default: disabled (false).")).default = "0"
local mpp = s:taboption("advanced", ListValue, "mask_proxy_protocol", "Mask Proxy Protocol" .. tip("Send PROXY protocol header to mask_host (if behind HAProxy/Nginx).")); mpp:value("0", "0 (Off)"); mpp:value("1", "1 (v1 - Text)"); mpp:value("2", "2 (v2 - Binary)"); mpp.default = "0"
local ip = s:taboption("advanced", Value, "announce_ip", "Announce Address" .. tip("Optional. Public IP or Domain for tg:// links. Overrides 'External IP' if set.")); ip.datatype = "string"
local ad = s:taboption("advanced", Value, "ad_tag", "Ad Tag" .. tip("Get your 32-hex promotion tag from @mtproxybot.")); ad.datatype = "hexstring"
s:taboption("advanced", Value, "fake_cert_len", "Fake Cert Length" .. tip("Size of the generated fake TLS certificate in bytes. Default: 2048.")).datatype = "uinteger"
s:taboption("advanced", Value, "tls_full_cert_ttl_secs", "TLS Full Cert TTL (sec)" .. tip("Time-to-Live for the full certificate chain per client IP. Default: 90.")).datatype = "uinteger"
s:taboption("advanced", Flag, "ignore_time_skew", "Ignore Time Skew" .. tip("Disable strict time checks. Useful if clients have desynced clocks.")).default = "0"

local htm = s:taboption("advanced", DummyValue, "_head_tm"); htm.rawhtml = true
htm.default = [[<div style="display:block; width:100%;"><details id="telemt_timeouts_details" style="display:block; width:100%; box-sizing:border-box; margin-top:20px; padding:10px; background:rgba(128,128,128,0.05); border:1px solid rgba(128,128,128,0.3); border-radius:6px; cursor:pointer;"><summary style="font-weight:bold; font-size:1.05em; outline:none; cursor:pointer;">Timeouts & Replay Protection (Click to expand)</summary><p style="font-size:0.85em; opacity:0.8; margin-top:5px; margin-bottom:0;">Adjust connection timeouts and replay window. Leave defaults if unsure.</p></details></div><script>setTimeout(function(){var details = document.getElementById('telemt_timeouts_details');if(!details) return;var toMove = ['tm_handshake', 'tm_connect', 'tm_keepalive', 'tm_ack', 'replay_window_secs'];toMove.forEach(function(name){var el = document.querySelector('.cbi-value[data-name="' + name + '"]') || document.getElementById('cbi-telemt-general-' + name) || document.querySelector('[id$="-' + name + '"]');if(el) { el.style.paddingLeft = '15px'; details.appendChild(el); }});}, 300);</script>]]
s:taboption("advanced", Value, "tm_handshake", "Handshake" .. tip("Client handshake timeout in seconds.")).default = "15"
s:taboption("advanced", Value, "tm_connect", "Connect" .. tip("Telegram DC connect timeout in seconds.")).default = "10"
s:taboption("advanced", Value, "tm_keepalive", "Keepalive" .. tip("Client keepalive interval in seconds.")).default = "60"
s:taboption("advanced", Value, "tm_ack", "ACK" .. tip("Client ACK timeout in seconds.")).default = "300"
s:taboption("advanced", Value, "replay_window_secs", "Replay Window (sec)" .. tip("Time window for replay attack protection. Default: 1800.")).default = "1800"

local hmet = s:taboption("advanced", DummyValue, "_head_met"); hmet.rawhtml = true; hmet.default = "<h3 style='margin-top:20px;'>Metrics & Control API</h3>"
local api_en = s:taboption("advanced", Flag, "api_enabled", "Enable REST API v1" .. tip("Critically required for the Telegram Bot operation and external JSON monitoring.")); api_en.default = "1"
local aport = s:taboption("advanced", Value, "api_port", "Control API Port" .. tip("Port for the new REST API (v1). Default: 9091.")); aport.datatype = "port"; aport.default = "9091"
local mport = s:taboption("advanced", Value, "metrics_port", "Prometheus Port" .. tip("Port for internal Prometheus exporter. Default: 9092.")); mport.datatype = "port"; mport.default = "9092"
s:taboption("advanced", Flag, "minimal_runtime_enabled", "Enable Minimal Runtime" .. tip("Provides heavy JSON snapshots on API. Required for TG Bot.")).default = "1"
s:taboption("advanced", Flag, "metrics_allow_lo", "Allow Localhost" .. tip("Auto-allow 127.0.0.1 and ::1. Required for Live Traffic stats.")).default = "1"
s:taboption("advanced", Flag, "metrics_allow_lan", "Allow LAN Subnet" .. tip("Auto-detect and allow your router's local network.")).default = "1"
local mwl = s:taboption("advanced", Value, "metrics_whitelist", "Additional Whitelist" .. tip("Optional. Comma separated CIDRs for external access.")); mwl.placeholder = "e.g. 10.8.0.0/24"
local cur_m_port = tonumber(m.uci:get("telemt", "general", "metrics_port")) or 9092
local mlink = s:taboption("advanced", DummyValue, "_mlink", "Prometheus Endpoint" .. tip("Click to open in a new tab, or copy for Grafana.")); mlink.rawhtml = true
mlink.default = string.format([[<a id="prom_link" href="#" target="_blank" class="telemt-prom-link" style="font-family: monospace; color: #00a000; padding: 4px; background: rgba(0,0,0,0.05); border-radius: 4px; text-decoration: none; border: 1px solid rgba(0,160,0,0.2);">http://&lt;router_ip&gt;:%d/metrics</a><script>setTimeout(function(){ var a = document.getElementById('prom_link'); if(a) { a.href = window.location.protocol + '//' + window.location.hostname + ':%d/metrics'; } }, 500);</script>]], cur_m_port, cur_m_port)

-- === TAB: TELEGRAM BOT ===
local hbot = s:taboption("bot", DummyValue, "_head_bot", ""); hbot.rawhtml = true; hbot.default = "<div style='margin-bottom:15px; padding-top:10px;'><h3 style='margin-top:0;'>Autonomous Telegram Bot (Sidecar)</h3><p style='opacity:0.8; margin-top:5px; margin-bottom:0;'>Configure the autonomous local bot to monitor Telemt status, fetch stats via Telegram, and send crash alerts directly to your phone.</p></div>"
s:taboption("bot", Flag, "bot_enabled", "Enable Bot Sidecar" .. tip("Start the autonomous monitoring script via procd.")).default = "0"

-- Bot Process Status
local bot_pid = not is_ajax and (sys.exec("pidof telemt-bot.sh | awk '{print $1}'") or ""):gsub("%s+", "") or ""
local bot_status = "<span style='color:#d9534f; font-weight:bold;'>STOPPED</span>"
if bot_pid ~= "" and sys.call("kill -0 " .. bot_pid .. " 2>/dev/null") == 0 then bot_status = string.format("<span style='color:green;font-weight:bold'>RUNNING (PID: %s)</span>", bot_pid) end
local bst = s:taboption("bot", DummyValue, "_bot_status", "Bot Status"); bst.rawhtml = true; bst.value = bot_status; bst:depends("bot_enabled", "1")

-- Bot Controls
local bctrl = s:taboption("bot", DummyValue, "_bot_controls", "Bot Controls"); bctrl.rawhtml = true
bctrl.default = string.format([[
<div class="btn-controls">
    <input type="button" class="cbi-button cbi-button-apply" id="btn_bot_start" value="Start Bot" />
    <input type="button" class="cbi-button cbi-button-reset" id="btn_bot_stop" value="Stop Bot" />
    <input type="button" class="cbi-button cbi-button-reload" id="btn_bot_restart" value="Restart Bot" />
</div>
<script>
setTimeout(function(){
    var bb1=document.getElementById('btn_bot_start'); if(bb1) bb1.addEventListener('click', function(){ logAction('Start Bot'); postAction('start_bot'); });
    var bb2=document.getElementById('btn_bot_stop'); if(bb2) bb2.addEventListener('click', function(){ logAction('Stop Bot'); postAction('stop_bot'); });
    var bb3=document.getElementById('btn_bot_restart'); if(bb3) bb3.addEventListener('click', function(){ logAction('Restart Bot'); postAction('restart_bot'); });
}, 500);
</script>]], current_url); bctrl:depends("bot_enabled", "1")

local bt = s:taboption("bot", Value, "bot_token", "Bot Token" .. tip("Get it from @BotFather.")); bt.password = true; bt:depends("bot_enabled", "1")
local bc = s:taboption("bot", Value, "bot_chat_id", "Admin Chat ID" .. tip("Your personal or group Chat ID for alerts.")); bc:depends("bot_enabled", "1")

-- === TAB: DIAGNOSTICS ===
local lv = s:taboption("log", DummyValue, "_lv"); lv.rawhtml = true
lv.default = [[
<div class="telemt-dash-top-row" style="margin-bottom:15px; padding:12px; background:rgba(128,128,128,0.05); border:1px solid var(--border-color, rgba(128,128,128,0.2)); border-radius:6px; display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px;">
    <div style="font-weight:bold; font-size:1.05em; color:var(--text-color, #555);">Diagnostics & Maintenance</div>
    <div style="display:flex; gap:10px; flex-wrap:wrap;">
        <input type="button" class="cbi-button cbi-button-action" id="btn_export_config" value="Export Active Config" style="background:#4a90e2; color:#fff; border:1px solid #357abd;" />
        <input type="button" class="cbi-button cbi-button-remove" id="btn_reset_config" value="Reset to defaults" />
    </div>
</div>
<div style="width:100%; box-sizing:border-box; height:500px; font-family:monospace; font-size:12px; padding:12px; background: #1e1e1e; color: #d4d4d4; border: 1px solid #333; border-radius: 4px; overflow-y:auto; overflow-x:auto; white-space:pre;" id="telemt_log_container">Click a button below to load data.</div>
<div style="margin-top:10px; display:flex; gap:10px; flex-wrap:wrap;">
    <input type="button" class="cbi-button cbi-button-apply" id="btn_load_log" value="System Log" />
    <input type="button" class="cbi-button cbi-button-reset" id="btn_load_scanners" value="Show Active Scanners" />
    <input type="button" class="cbi-button cbi-button-action" id="btn_copy_log" value="Copy Output" />
</div>
<script>
setTimeout(function(){
    document.getElementById('btn_load_log').addEventListener('click', loadLog);
    document.getElementById('btn_load_scanners').addEventListener('click', loadScanners);
    document.getElementById('btn_copy_log').addEventListener('click', function(){ copyLogContent(this); });
    
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
local anchor = s:taboption("users", DummyValue, "_users_anchor", ""); anchor.rawhtml = true; anchor.default = '<div id="users_tab_anchor" style="display:none"></div>'
local myip_u = s:taboption("users", DummyValue, "_ip_display", "External IP / DynDNS" .. tip("IP address or domain used for generating tg:// links.")); myip_u.rawhtml = true; myip_u.default = string.format([[<input type="text" class="cbi-input-text" style="width:250px;" id="telemt_mirror_ip" value="%s">]], saved_ip)

s2 = m:section(TypedSection, "user", "")
s2.template = "cbi/tblsection"; s2.addremove = true; s2.anonymous = false
s2.create = function(self, section) if not section or not section:match("^[A-Za-z0-9_]+$") or #section > 15 then return nil end; sys.call(string.format("logger -t telemt 'WebUI: Added new user -> %s'", section)); return TypedSection.create(self, section) end
s2.remove = function(self, section) sys.call(string.format("logger -t telemt 'WebUI: Deleted user -> %s'", section)); return TypedSection.remove(self, section) end

local sec = s2:option(Value, "secret", "User / Secret" .. tip("Leave empty to auto-generate.")); sec.rmempty = false; sec.datatype = "hexstring"; function sec.validate(self, value) if not value or value:gsub("%s+", "") == "" then value = (sys.exec("cat /proc/sys/kernel/random/uuid") or ""):gsub("%-", ""):gsub("%s+", ""):sub(1,32) end; if #value ~= 32 or not value:match("^[0-9a-fA-F]+$") then return nil, "Secret must be exactly 32 hex chars!" end; return value end
local u_en = s2:option(Flag, "enabled", "Active" .. tip("Uncheck to manually pause this user.")); u_en.default = "1"; u_en.rmempty = false
local t_con = s2:option(Value, "max_tcp_conns", "TCP Conns" .. tip("Limit sessions (e.g. 50)")); t_con.datatype = "uinteger"; t_con.placeholder = "unlimited"
local t_uips = s2:option(Value, "max_unique_ips", "Max IPs" .. tip("Max unique client IPs.")); t_uips.datatype = "uinteger"; t_uips.placeholder = "unlimited"
local t_qta = s2:option(Value, "data_quota", "Quota (GB)" .. tip("E.g. 1.5 or 0.5")); t_qta.datatype = "ufloat"; t_qta.placeholder = "unlimited"
local t_exp = s2:option(Value, "expire_date", "Expire Date" .. tip("Format: DD.MM.YYYY HH:MM")); t_exp.datatype = "string"; t_exp.placeholder = "DD.MM.YYYY HH:MM"; function t_exp.validate(self, value) if not value then return "" end value = value:match("^%s*(.-)%s*$"); if value == "" or value == "unlimited" then return "" end if not value:match("^%d%d%.%d%d%.%d%d%d%d %d%d:%d%d$") then return nil, "Format: DD.MM.YYYY HH:MM" end return value end
local lst = s2:option(DummyValue, "_stat", "Status and Stats" .. tip("Accumulated usage & sessions")); lst.rawhtml = true
function lst.cfgvalue(self, section) 
    local q = self.map:get(section, "data_quota") or ""; local e = self.map:get(section, "expire_date") or ""; local en = self.map:get(section, "enabled") or "1"
    return string.format('<div class="user-flat-stat" data-user="%s" data-q="%s" data-e="%s" data-en="%s"><span style="color:#888;">No Data</span></div>', section:gsub("[<>&\"']", ""), q, e, en) 
end
local lnk = s2:option(DummyValue, "_link", "Ready-to-use link" .. tip("Click the link to copy it.")); lnk.rawhtml = true; function lnk.cfgvalue(self, section) return [[<div class="link-wrapper"><input type="text" class="cbi-input-text user-link-out" readonly onclick="this.select()"></div>]] end

m.description = [[
<style>
/* Hiding standard LuCI help icons and tooltips */
.cbi-value-helpicon, img[src*="help.gif"], img[src*="help.png"], .cbi-tooltip-container, .cbi-tooltip { display: none !important; }

/* FIX FOR OPENWRT 24.10+ DEFAULT BLUE QUESTION MARKS */
.cbi-value-description::before, .cbi-value-description img { display: none !important; content: none !important; margin: 0 !important; padding: 0 !important; width: 0 !important; height: 0 !important; }

#cbi-telemt-user .cbi-section-table-descr { display: none !important; width: 0 !important; height: 0 !important; visibility: hidden !important; }
#cbi-telemt-user .cbi-row-template, #cbi-telemt-user [id*="-template"] { display: none !important; visibility: hidden !important; height: 0 !important; overflow: hidden !important; pointer-events: none !important; }

/* Add User / Upstream Buttons */
html body #cbi-telemt-user .cbi-button-add, html body #cbi-telemt-upstream .cbi-button-add { color: #00a000 !important; background-color: transparent !important; border: 1px solid #00a000 !important; transition: all 0.2s ease !important; padding: 0 16px !important; height: 32px !important; line-height: 30px !important; border-radius: 4px !important; font-weight: bold !important; }
html body #cbi-telemt-user .cbi-button-add:hover, html body #cbi-telemt-upstream .cbi-button-add:hover { background-color: #00a000 !important; color: #ffffff !important; -webkit-text-fill-color: #ffffff !important; }

#cbi-telemt-user .cbi-section-table td:first-child { vertical-align: middle !important; }

/* Upstreams Block Fix (Cards and Buttons - STRICT BOTTOM LEFT) */
#cbi-telemt-upstream .cbi-section-node-row,
#cbi-telemt-upstream > div:not([id$="-template"]) {
    display: flex !important;
    flex-direction: column !important;
    background: rgba(128,128,128,0.03) !important;
    border: 1px solid var(--border-color, rgba(128,128,128,0.2)) !important;
    border-radius: 8px !important;
    padding: 15px !important;
    margin-bottom: 20px !important;
}
#cbi-telemt-upstream > div:not([id$="-template"]) > .cbi-section-remove,
#cbi-telemt-upstream .cbi-section-node > .cbi-section-remove {
    order: 99 !important;
    align-self: flex-start !important;
    margin-top: 15px !important;
    padding-top: 15px !important;
    border-top: 1px dashed var(--border-color, rgba(128,128,128,0.3)) !important;
    width: 100% !important;
    text-align: left !important;
}
html body #cbi-telemt-upstream .cbi-button-remove { display: inline-block !important; float: left !important; margin: 0 !important; color: #d9534f !important; background-color: transparent !important; border: 1px solid #d9534f !important; padding: 0 12px !important; height: 30px !important; line-height: 28px !important; font-weight: normal !important; transition: all 0.2s ease !important; }
html body #cbi-telemt-upstream .cbi-button-remove:hover { background-color: #d9534f !important; color: #ffffff !important; -webkit-text-fill-color: #ffffff !important; }

/* ADVANCED TUNING SPOILERS WIDTH FIX */
div[id^="cbi-telemt-advanced-_head_adv"] .cbi-value-title,
div[id^="cbi-telemt-advanced-_head_tm"] .cbi-value-title { display: none !important; }
div[id^="cbi-telemt-advanced-_head_adv"] .cbi-value-field,
div[id^="cbi-telemt-advanced-_head_tm"] .cbi-value-field { width: 100% !important; padding: 0 !important; margin: 0 !important; float: none !important; }

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

@media (prefers-color-scheme: dark) {
    .telemt-btn-cross { background-image: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23cccccc' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cline x1='18' y1='6' x2='6' y2='18'/%3E%3Cline x1='6' y1='6' x2='18' y2='18'/%3E%3C/svg%3E") !important; }
    .telemt-btn-cal { background-image: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23cccccc' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Crect x='3' y='4' width='18' height='18' rx='2' ry='2'/%3E%3Cline x1='16' y1='2' x2='16' y2='6'/%3E%3Cline x1='8' y1='2' x2='8' y2='6'/%3E%3Cline x1='3' y1='10' x2='21' y2='10'/%3E%3C/svg%3E") !important; }
}

#cbi-telemt-user .user-link-out { height: 32px !important; line-height: 32px !important; width: 100%; font-family: monospace; font-size: 11px; background: transparent !important; color: inherit !important; border: 1px solid var(--border-color, rgba(128,128,128,0.5)) !important; box-sizing: border-box; margin: 0; cursor: pointer; }
.user-link-err { color: #d9534f !important; font-weight: bold; border-color: #d9534f !important; }
.user-flat-stat { display: flex; flex-wrap: wrap; align-items: center; line-height: 1.4; font-size: 0.95em; }
.user-flat-stat > * { margin-right: 4px; }
.user-flat-stat > *:last-child { margin-right: 0; }
.stat-divider, .sum-divider { color: #ccc; margin: 0 4px; }
.btn-controls input { width: auto; margin-right: 5px; }

.telemt-dash-info-panel { display: flex; flex-direction: column; gap: 6px; padding: 12px; background: rgba(0,160,0,0.05); border: 1px solid rgba(0,160,0,0.2); border-radius: 6px; margin-bottom: 12px; }
.telemt-dash-row { display: flex; flex-wrap: wrap; align-items: center; font-size: 1.05em; row-gap: 5px; }
.telemt-dash-row > span { margin-right: 12px; white-space: nowrap; }
.telemt-dash-action-panel { display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 15px; }

.link-btn-group { display: flex; margin-top: 4px; }

@media screen and (min-width: 769px) {
    #cbi-telemt-user .cbi-section-table { width: 100% !important; table-layout: auto !important; }
    #cbi-telemt-user .cbi-section-table td { padding: 6px 8px !important; white-space: nowrap !important; vertical-align: middle !important; }
    .user-flat-stat, .user-flat-stat > div { flex-wrap: nowrap !important; white-space: nowrap !important; }
    td[data-name="_stat"] { min-width: 180px !important; }
    td[data-name="max_tcp_conns"] .telemt-num-wrap, td[data-name="max_unique_ips"] .telemt-num-wrap, td[data-name="data_quota"] .telemt-num-wrap { max-width: 95px !important; }
    td[data-name="expire_date"] { min-width: 155px !important; }
    td[data-name="expire_date"] .telemt-num-wrap { min-width: 155px !important; width: 100% !important; }
    td[data-name="_link"] .link-wrapper { min-width: 160px !important; }
    td[data-name="secret"] .telemt-sec-wrap { min-width: 160px !important; }
    .telemt-dash-warn { font-size:1em; color:#d35400; font-weight:bold; }
}

@media screen and (max-width: 768px) {
    #telemt_mirror_ip, input[name*="cbid.telemt.general.external_ip"] { flex: 1 1 100% !important; width: 100% !important; max-width: 100% !important; }
    #cbi-telemt-user .cbi-section-table .cbi-section-table-row { display: flex !important; flex-direction: column !important; margin-bottom: 15px !important; border: 1px solid var(--border-color, #ddd) !important; padding: 10px !important; border-radius: 6px !important; }
    #cbi-telemt-user .cbi-section-table td { display: block !important; width: 100% !important; box-sizing: border-box !important; padding: 6px 0 !important; border: none !important; white-space: normal !important; }
    #cbi-telemt-user .cbi-section-table td[data-title]::before { content: attr(data-title) !important; display: block !important; font-weight: bold !important; margin-bottom: 4px !important; color: var(--text-color, #555) !important; }
    #cbi-telemt-user .cbi-section-actions .cbi-button::before, #cbi-telemt-user td .cbi-button::before { display: none !important; content: none !important; }
    #cbi-telemt-user .cbi-section-actions, #cbi-telemt-user td.cbi-section-actions, #cbi-telemt-user .cbi-section-table td:last-child { display: block !important; visibility: visible !important; opacity: 1 !important; padding: 10px 0 0 0 !important; overflow: visible !important; width: 100% !important; }
    html body #cbi-telemt-user .cbi-section-actions .cbi-button-remove:not(.telemt-btn-cross), html body #cbi-telemt-user td.cbi-section-actions .cbi-button-remove:not(.telemt-btn-cross) { display: flex !important; width: 100% !important; height: 44px !important; line-height: 44px !important; align-items: center !important; justify-content: center !important; }
    .user-flat-stat, .user-flat-stat > div { flex-direction: column; align-items: flex-start; flex-wrap: wrap !important; }
    .telemt-dash-row { flex-direction: column; align-items: flex-start; }
    .telemt-dash-row > span { margin-right: 0 !important; margin-bottom: 6px !important; display: block !important; width: 100% !important; white-space: normal !important; }
    .stat-divider, .sum-divider { display: none !important; }
    .telemt-dash-action-panel { flex-direction: column; width: 100%; gap: 8px !important; }
    .telemt-dash-action-panel input.cbi-button { width: 100% !important; height: 36px !important; }
    .link-btn-group { flex-direction: row !important; width: 100%; display: flex; margin-top: 5px; }
    .telemt-sec-btns input.cbi-button, .link-btn-group input.cbi-button { height: 32px !important; min-height: 32px !important; line-height: 30px !important; font-size: 13px !important; margin-right: 5px; }
}

/* DARK CSV MODAL */
.qr-modal-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 2147483647 !important; display: flex; align-items: center; justify-content: center; opacity: 0; pointer-events: none; transition: opacity 0.2s; }
.qr-modal-overlay.active { opacity: 1; pointer-events: auto; }
.custom-modal-content { background-color: #1e1e1e !important; color: #dddddd !important; padding: 20px; border-radius: 8px; box-shadow: 0 10px 30px rgba(0,0,0,0.8); border: 1px solid #444 !important; text-align: center; max-width: 450px; width: 90%; }
.custom-modal-content p, .custom-modal-content h3, .custom-modal-content label, .custom-modal-content span { color: #dddddd !important; }
.custom-modal-content svg { max-width: 100%; height: auto; display: block; margin: 0 auto; }
#csv_text_area { background-color: #121212 !important; color: #00ff00 !important; width: 100%; height: 120px; font-family: monospace; font-size: 11px; margin-bottom: 10px; box-sizing: border-box; padding: 5px; resize: vertical; border: 1px solid #555 !important; }
</style>

<script type="text/javascript">
var lu_current_url = "]] .. safe_url .. [[";
var is_owrt25 = ]] .. is_owrt25_lua .. [[;

function logAction(msg, data) { console.log("[Telemt UI] " + msg); }
function escHTML(s) { return String(s).replace(/[&<>'"]/g, function(c) { return '&#' + c.charCodeAt(0) + ';'; }); }
function logToRouter(msg) { var f = new FormData(); f.append('log_ui_event', '1'); f.append('msg', msg); fetch(lu_current_url.split('#')[0], { method: 'POST', body: f }); }
function formatMB(bytes) { if(!bytes || bytes === 0) return '0.00 MB'; var mb = bytes / 1048576; if (mb >= 1024) return (mb / 1024).toFixed(2) + ' GB'; return mb.toFixed(2) + ' MB'; }
function formatUptime(secs) { if(!secs) return '0s'; var d = Math.floor(secs/86400), h = Math.floor((secs%86400)/3600), m = Math.floor((secs%3600)/60), s = Math.floor(secs%60); var str = ""; if(d>0) str += d+"d "; if(h>0 || d>0) str += h+"h "; str += m+"m "+s+"s"; return str; }

window._telemtLastStats = null;

function cleanResponse(txt) {
    if (!txt) return '';
    var cut = txt.search(/<(!DOCTYPE|html[\s>])/i);
    if (cut > 0) return txt.substring(0, cut).trim();
    return txt;
}

function updateCascadesState() {
    var upRows = document.querySelectorAll('#cbi-telemt-upstream .cbi-section-node:not([id*="-template"])');
    var masterSwitch = document.querySelector('input[type="checkbox"][name*="enable_upstreams"]');
    if (masterSwitch) {
        if (upRows.length === 0) {
            masterSwitch.disabled = true; masterSwitch.checked = false; masterSwitch.title = "No cascades configured";
        } else {
            masterSwitch.disabled = false; masterSwitch.title = "";
        }
        var isMasterOn = masterSwitch.checked;
        upRows.forEach(function(row) {
            row.style.transition = "opacity 0.3s ease";
            row.style.opacity = isMasterOn ? "1" : "0.4";
            row.style.pointerEvents = isMasterOn ? "auto" : "none";
        });
        if(!masterSwitch.dataset.bound) {
            masterSwitch.dataset.bound = "1";
            masterSwitch.addEventListener('change', updateCascadesState);
        }
    }
}

function fetchMetrics() {
    if (!document.getElementById('cbi-telemt-general') && !document.getElementById('cbi-telemt-user') && !document.getElementById('cbi-telemt-upstream')) { stopTimers(); return; }
    if (window._telemtFetching) return; window._telemtFetching = true;
    
    fetch(lu_current_url.split('#')[0] + (lu_current_url.indexOf('?') > -1 ? '&' : '?') + 'get_metrics=1&_t=' + Date.now()).then(r => r.text()).then(txt => {
        window._telemtFetching = false; 
        txt = cleanResponse(txt || ""); 
        
        var userStats = {}; var allUserRows = document.querySelectorAll('.user-flat-stat');
        allUserRows.forEach(function(statEl) { var u = statEl.getAttribute('data-user'); if(u) userStats[u] = { live_rx: 0, live_tx: 0, acc_rx: 0, acc_tx: 0, conns: 0, ip_cur: 0, ip_lim: 0 }; });
        
        var globalStatsObj = { uptime: 0, dpi: 0, up_ok: 0, up_fail: 0, scanners: 0 }; 
        var totalLiveRx = 0, totalLiveTx = 0, totalAccRx = 0, totalAccTx = 0;
        
        var lines = txt.split('\n');
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim(); if (line.indexOf('#') === 0 || line === "") continue;
            if (line.indexOf('telemt_uptime_seconds') === 0) { var m = line.match(/\s+([0-9\.eE\+\-]+)/); if(m) globalStatsObj.uptime = parseFloat(m[1]); continue; }
            if (line.indexOf('telemt_desync_total') === 0) { var m = line.match(/\s+([0-9\.eE\+\-]+)/); if(m) globalStatsObj.dpi += parseFloat(m[1]); continue; }
            if (line.indexOf('telemt_upstream_connect_success_total') === 0) { var m = line.match(/\s+([0-9\.eE\+\-]+)/); if(m) globalStatsObj.up_ok = parseFloat(m[1]); continue; }
            if (line.indexOf('telemt_upstream_connect_fail_total') === 0) { var m = line.match(/\s+([0-9\.eE\+\-]+)/); if(m) globalStatsObj.up_fail = parseFloat(m[1]); continue; }
            if (line.indexOf('telemt_active_scanners_count') === 0) { var m = line.match(/\s+([0-9]+)/); if(m) globalStatsObj.scanners = parseInt(m[1]); continue; }
            
            var userMatch = line.match(/user="([^"]+)"/);
            if (userMatch) {
                var u = userMatch[1]; if (!userStats[u]) userStats[u] = { live_rx: 0, live_tx: 0, acc_rx: 0, acc_tx: 0, conns: 0, ip_cur: 0, ip_lim: 0 };
                var valMatch = line.match(/\}\s+([0-9\.eE\+\-]+)/);
                if (valMatch) {
                    var val = parseFloat(valMatch[1]);
                    if (line.indexOf('telemt_user_octets_from_client') > -1) { userStats[u].live_rx = val; totalLiveRx += val; }
                    else if (line.indexOf('telemt_user_octets_to_client') > -1) { userStats[u].live_tx = val; totalLiveTx += val; }
                    else if (line.indexOf('telemt_user_connections_current') > -1) { userStats[u].conns = val; }
                    else if (line.indexOf('telemt_user_unique_ips_current') > -1) { userStats[u].ip_cur = val; }
                    else if (line.indexOf('telemt_user_unique_ips_limit') > -1) { userStats[u].ip_lim = val; }
                    else if (line.indexOf('telemt_accumulated_rx') > -1) { userStats[u].acc_rx = val; totalAccRx += val; }
                    else if (line.indexOf('telemt_accumulated_tx') > -1) { userStats[u].acc_tx = val; totalAccTx += val; }
                }
            }
        }
        window._telemtLastStats = userStats; var totalRx = totalLiveRx + totalAccRx; var totalTx = totalLiveTx + totalAccTx;
        var totalConfiguredUsers = allUserRows.length; var usersOnline = 0;
        
        allUserRows.forEach(function(statEl) {
            var u = statEl.getAttribute('data-user'); var stat = userStats[u] || { live_rx: 0, live_tx: 0, acc_rx: 0, acc_tx: 0, conns: 0, ip_cur: 0, ip_lim: 0 };
            var finalTx = stat.live_tx + stat.acc_tx; var finalRx = stat.live_rx + stat.acc_rx; if (stat.conns > 0) usersOnline++;
            
            var qStr = statEl.getAttribute('data-q'); var eStr = statEl.getAttribute('data-e'); var isEn = statEl.getAttribute('data-en');
            var cb = document.querySelector('input[name*="cbid.telemt.' + u + '.enabled"]');
            
            var isExpired = false;
            if (eStr) { var p = eStr.split(' '); if(p.length==2) { var d=p[0].split('.'); var t=p[1].split(':'); if(d.length==3 && t.length==2) { if (Date.now() > new Date(d[2], d[1]-1, d[0], t[0], t[1]).getTime()) isExpired = true; } } }
            
            var isOverQuota = false;
            if (qStr) { var qGB = parseFloat(qStr); if (!isNaN(qGB) && qGB > 0) { if ((finalTx + finalRx) >= (qGB * 1073741824)) isOverQuota = true; } }
            
            if (isExpired) { 
                if (isEn !== "0" || (cb && cb.checked)) {
                    if (cb) cb.checked = false;
                    var f = new FormData(); f.append('auto_pause_user', u); f.append('reason', 'Expired');
                    var tokenVal = null; var tokenNode = document.querySelector('input[name="token"]');
                    if (tokenNode) tokenVal = tokenNode.value; else if (typeof L !== 'undefined' && L.env) tokenVal = L.env.token || L.env.requesttoken || null;
                    if (!tokenVal) { var cm = document.cookie.match(/(?:sysauth_http|sysauth)=([^;]+)/); if (cm) tokenVal = cm[1]; }
                    if (tokenVal) f.append('token', tokenVal); fetch(lu_current_url.split('#')[0], { method: 'POST', body: f });
                    statEl.setAttribute('data-en', '0');
                }
                statEl.innerHTML = "<span style='color:#d9534f; font-weight:bold;'>[ PAUSED: EXPIRED ]</span>"; return; 
            }
            if (isOverQuota) { 
                if (isEn !== "0" || (cb && cb.checked)) {
                    if (cb) cb.checked = false;
                    var f = new FormData(); f.append('auto_pause_user', u); f.append('reason', 'Quota Exceeded');
                    var tokenVal = null; var tokenNode = document.querySelector('input[name="token"]');
                    if (tokenNode) tokenVal = tokenNode.value; else if (typeof L !== 'undefined' && L.env) tokenVal = L.env.token || L.env.requesttoken || null;
                    if (!tokenVal) { var cm = document.cookie.match(/(?:sysauth_http|sysauth)=([^;]+)/); if (cm) tokenVal = cm[1]; }
                    if (tokenVal) f.append('token', tokenVal); fetch(lu_current_url.split('#')[0], { method: 'POST', body: f });
                    statEl.setAttribute('data-en', '0');
                }
                statEl.innerHTML = "<span style='color:#d9534f; font-weight:bold;'>[ PAUSED: QUOTA ]</span>"; return; 
            }
            if (isEn === "0" || (cb && !cb.checked)) { statEl.innerHTML = "<span style='color:#888; font-weight:bold;'>[ PAUSED: MANUAL ]</span>"; return; }
            
            var c_col = stat.conns > 0 ? "#00a000" : "#888"; 
            var dotUser = "<svg width='10' height='10' style='vertical-align:middle;'><circle cx='5' cy='5' r='5' fill='" + c_col + "'/></svg>";
            var ipAlert = ""; if (stat.ip_lim > 0 && stat.ip_cur >= stat.ip_lim) { ipAlert = "<span class='stat-divider'>|</span> <span style='color:#d35400; font-weight:bold; font-size:0.9em;'>&#9888; IPs: " + stat.ip_cur + "/" + stat.ip_lim + "</span>"; }
            statEl.innerHTML = "<div style='display:flex; align-items:center; gap:4px; margin-bottom:2px; flex-wrap:wrap;'><span style='white-space:nowrap; color:#00a000;'>&darr; " + formatMB(finalTx) + "</span> <span class='stat-divider'>/</span> <span style='white-space:nowrap; color:#d35400;'>&uarr; " + formatMB(finalRx) + "</span> <span class='stat-divider'>|</span> <span style='white-space:nowrap; color:" + c_col + "; display:inline-flex; align-items:center;'>" + dotUser + "&nbsp;" + stat.conns + "</span>" + ipAlert + "</div>";
        });
        
        var now = Date.now(); var speedDL = 0, speedUL = 0; 
        if (!window._telemtLastTime) { window._telemtLastTime = now; window._telemtLastTotalRx = totalRx; window._telemtLastTotalTx = totalTx; } 
        else { var diffSec = (now - window._telemtLastTime) / 1000.0; if (diffSec > 0) { var dRx = totalRx - window._telemtLastTotalRx; var dTx = totalTx - window._telemtLastTotalTx; if (dRx >= 0) speedUL = (dRx * 8) / 1048576 / diffSec; if (dTx >= 0) speedDL = (dTx * 8) / 1048576 / diffSec; } window._telemtLastTime = now; window._telemtLastTotalRx = totalRx; window._telemtLastTotalTx = totalTx; }
        
        var row1El = document.getElementById('telemt_dash_row1');
        var row2El = document.getElementById('telemt_dash_row2');
        if (row1El && row2El) {
            if (txt.trim() === "") { 
                row1El.innerHTML = "<span style='color:#d9534f; font-weight:bold;'>Status: Offline</span><span class='sum-divider'>|</span><span><b style='color:#555;'>Total DL:</b> <span style='color:#00a000;'>&darr; " + formatMB(totalTx) + "</span></span><span class='sum-divider'>|</span><span><b style='color:#555;'>Total UL:</b> <span style='color:#d35400;'>&uarr; " + formatMB(totalRx) + "</span></span><span class='sum-divider'>|</span><span><b style='color:#555;'>Users Online:</b> <b style='color:#888; margin-left:4px;'>0</b><span style='margin:0 4px;'>/</span>" + totalConfiguredUsers + "</span>"; 
                row2El.innerHTML = "";
            } else { 
                row1El.innerHTML = "<b style='margin-right:6px;'>Uptime:</b><span style='color:#666;'>" + formatUptime(globalStatsObj.uptime) + "</span><span class='sum-divider'>|</span><span><b style='color:#555;'>Total DL:</b> <span style='color:#00a000;'>&darr; " + formatMB(totalTx) + "</span></span><span class='sum-divider'>|</span><span><b style='color:#555;'>Total UL:</b> <span style='color:#d35400;'>&uarr; " + formatMB(totalRx) + "</span></span><span class='sum-divider'>|</span><span><b style='color:#555;'>Speed:</b> <span style='color:#00a000;'>&darr; " + speedDL.toFixed(2) + "</span> <span style='color:#d35400; margin-left:4px;'>&uarr; " + speedUL.toFixed(2) + "</span> <small>Mbps</small></span><span class='sum-divider'>|</span><span><b style='color:#555;'>Users Online:</b> <b style='color:#00a000; margin-left:4px;'>" + usersOnline + "</b><span style='margin:0 4px;'>/</span>" + totalConfiguredUsers + "</span>"; 
                
                var scanCol = globalStatsObj.scanners > 0 ? "#d9534f" : "#00a000";
                row2El.innerHTML = "<span><b style='color:#555;'>Upstream Health:</b> <span style='color:#00a000; font-weight:bold; margin-left:4px;'>&#128994; " + globalStatsObj.up_ok + " OK</span> <span class='sum-divider'>/</span> <span style='color:#d9534f; font-weight:bold;'>&#128308; " + globalStatsObj.up_fail + " Fails</span></span><span class='sum-divider'>|</span><span><b style='color:#555;'>DPI Probes:</b> <span style='color:" + (globalStatsObj.dpi > 0 ? "#d9534f" : "#00a000") + "; font-weight:bold; margin-left:4px;'>" + globalStatsObj.dpi + "</span></span><span class='sum-divider'>|</span><span><b style='color:#555;'>Active Scanners:</b> <span style='color:" + scanCol + "; font-weight:bold; margin-left:4px;'>" + globalStatsObj.scanners + "</span></span>";
            }
        }
    }).catch(() => { window._telemtFetching = false; });
}

function getEffectiveIP() { var m1 = document.querySelector('input[name*="cbid.telemt.general.external_ip"]'); var m2 = document.getElementById('telemt_mirror_ip'); if (m2 && m2.offsetParent !== null) return m2.value.trim(); if (m1) return m1.value.trim(); return "0.0.0.0"; }

function updateLinks() {
    var d = document.querySelector('input[name*="domain"]'); var p = document.querySelector('input[name*="port"]'); var modeSelect = document.querySelector('select[name*="mode"]'); var fmtSelect = document.querySelector('select[name*="_link_fmt"]');
    var ip = getEffectiveIP(); var port = p ? p.value.trim() : "4443"; var domain = d ? d.value.trim() : ""; var mode = modeSelect ? modeSelect.value : "tls";
    var effectiveFmt = mode; if (mode === 'all' && fmtSelect) effectiveFmt = fmtSelect.value;
    if(!ip || !port) return;
    var hd = ""; if (domain && (effectiveFmt === 'tls' || effectiveFmt === 'all')) { for(var n=0; n<domain.length; n++) { var hex = domain.charCodeAt(n).toString(16); if (hex.length < 2) hex = "0" + hex; hd += hex; } }
    document.querySelectorAll('#cbi-telemt-user .cbi-section-table-row:not(.cbi-row-template), #cbi-telemt-user tr.cbi-row:not(.cbi-row-template), #cbi-telemt-user div.cbi-row:not(.cbi-row-template)').forEach(function(row) {
        var secInp = row.querySelector('input[name*="secret"]'); var linkOut = row.querySelector('.user-link-out');
        if(secInp && linkOut) { var val = secInp.value.trim(); if(/^[0-9a-fA-F]{32}$/.test(val)) { var finalSecret = (effectiveFmt === 'tls' || effectiveFmt === 'all') ? "ee" + val + hd : ((effectiveFmt === 'dd') ? "dd" + val : val); linkOut.value = "tg://proxy?server=" + ip + "&port=" + port + "&secret=" + finalSecret; linkOut.classList.remove('user-link-err'); } else { linkOut.value = "Error: 32 hex chars required!"; linkOut.classList.add('user-link-err'); } }
    });
    updateCascadesState();
}

function copyProxyLink(btn) { var row = btn.closest('.cbi-section-table-row') || btn.closest('.cbi-row'); if (!row) return; var input = row.querySelector('.user-link-out'); if (input && !input.classList.contains('user-link-err')) { var textToCopy = input.value; logToRouter("WebUI: Proxy link copied to clipboard"); if (navigator.clipboard && window.isSecureContext) { navigator.clipboard.writeText(textToCopy).then(function() { var oldVal = btn.value; btn.value = '✔'; setTimeout(function(){ btn.value = oldVal; }, 1500); }); } else { input.select(); input.setSelectionRange(0, 99999); try { if(document.execCommand('copy')) { var oldVal = btn.value; btn.value = '✔'; setTimeout(function(){ btn.value = oldVal; }, 1500); } } catch(e) {} } } }

function genRandHex() { var arr = new Uint8Array(16); (window.crypto || window.msCrypto).getRandomValues(arr); var h = ""; for(var i=0; i<16; i++) { var hex = arr[i].toString(16); if(hex.length < 2) hex = "0" + hex; h += hex; } return h; }

function fetchIPViaWget(btn) { var oldVal = btn.value; btn.value = '...'; fetch(lu_current_url.split('#')[0] + (lu_current_url.indexOf('?') > -1 ? '&' : '?') + 'get_wan_ip=1&_t=' + Date.now()).then(r => r.text()).then(txt => { txt = cleanResponse(txt); var match = txt.match(/\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b/); if (match) { var master = document.querySelector('input[name*="cbid.telemt.general.external_ip"]'); var mirror = document.getElementById('telemt_mirror_ip'); if(master) master.value = match[0]; if(mirror) mirror.value = match[0]; updateLinks(); } btn.value = oldVal; }).catch(() => { btn.value = oldVal; }); }

function loadLog() { var btn = document.getElementById('btn_load_log'); if(!btn) return; var oldVal = btn.value; btn.value = 'Loading...'; fetch(lu_current_url.split('#')[0] + (lu_current_url.indexOf('?') > -1 ? '&' : '?') + 'get_log=1&_t=' + Date.now()).then(r => r.text()).then(txt => { document.getElementById('telemt_log_container').textContent = cleanResponse(txt) || 'No logs found.'; btn.value = 'System Log'; }).catch(() => { btn.value = 'Error'; }); }
function loadScanners() { var btn = document.getElementById('btn_load_scanners'); if(!btn) return; var oldVal = btn.value; btn.value = 'Loading...'; fetch(lu_current_url.split('#')[0] + (lu_current_url.indexOf('?') > -1 ? '&' : '?') + 'get_scanners=1&_t=' + Date.now()).then(r => r.text()).then(txt => { document.getElementById('telemt_log_container').textContent = "=== [ ACTIVE DPI SCANNERS (beobachten.txt) ] ===\n\n" + (cleanResponse(txt) || 'No data.'); btn.value = 'Refresh Scanners'; }).catch(() => { btn.value = 'Error'; }); }
function copyLogContent(btn) { var logText = document.getElementById('telemt_log_container').textContent; if(!logText) return; var ta = document.createElement('textarea'); ta.value = logText; document.body.appendChild(ta); ta.select(); try { if(document.execCommand('copy')) { var oldVal = btn.value; btn.value = 'Copied!'; setTimeout(function(){ btn.value = oldVal; }, 1500); } } catch(e) {} document.body.removeChild(ta); }

function updateFWStatus() { if (!document.getElementById('cbi-telemt-general')) return; var fwSpan = document.getElementById('fw_status_span'); if (!fwSpan) return; fetch(lu_current_url.split('#')[0] + (lu_current_url.indexOf('?') > -1 ? '&' : '?') + 'get_fw_status=1&_t=' + Date.now()).then(r => r.text()).then(txt => { txt = cleanResponse(txt); if(txt.indexOf('OPEN') > -1 || txt.indexOf('CLOSED') > -1 || txt.indexOf('STOPPED') > -1) fwSpan.innerHTML = txt; }).catch(()=>{}); }

function closeModals() { document.querySelectorAll('.qr-modal-overlay').forEach(function(m) { m.classList.remove('active'); }); document.body.classList.remove('qr-modal-open'); }
function showQRModal(link) { if (!link || link.indexOf('Error') === 0) return; var overlay = document.getElementById('qr-modal'); if (!overlay) { overlay = document.createElement('div'); overlay.id = 'qr-modal'; overlay.className = 'qr-modal-overlay'; var content = document.createElement('div'); content.className = 'custom-modal-content'; var body = document.createElement('div'); body.id = 'qr-modal-body'; content.appendChild(body); var clsBtn = document.createElement('button'); clsBtn.className = 'cbi-button cbi-button-reset'; clsBtn.style.cssText = 'margin-top:15px; width:100%;'; clsBtn.innerText = 'Close'; clsBtn.addEventListener('click', closeModals); content.appendChild(clsBtn); overlay.appendChild(content); document.body.appendChild(overlay); overlay.addEventListener('click', function(e) { if (e.target === overlay) closeModals(); }); } var body = document.getElementById('qr-modal-body'); body.innerHTML = 'Generating...'; overlay.classList.add('active'); document.body.classList.add('qr-modal-open'); fetch(lu_current_url.split('#')[0] + (lu_current_url.indexOf('?') > -1 ? '&' : '?') + 'get_qr=1&link=' + encodeURIComponent(link) + '&_t=' + Date.now()).then(r => r.text()).then(txt => { txt = cleanResponse(txt); if (txt.indexOf('error: qrencode_missing') > -1) body.innerHTML = '<div style="color:#d9534f; font-weight:bold; margin-bottom:10px;">Install qrencode</div>'; else if (txt.indexOf('error: invalid_link') > -1) body.innerHTML = '<div style="color:#d9534f; font-weight:bold;">Invalid Link Format</div>'; else { var svgMatch = txt.match(/<svg[\s\S]*?<\/svg>/i); body.innerHTML = svgMatch ? svgMatch[0] : 'Error'; } }).catch(() => { body.innerHTML = 'Connection error.'; }); }

function doExportStats() { if (!window._telemtLastStats) { alert("Live stats not loaded yet. Wait a few seconds."); return; } logToRouter("Exporting Live Stats to CSV"); var csv = "username,total_dl_bytes,total_ul_bytes,active_connections\n"; var grandTx = 0, grandRx = 0, grandConns = 0; for (var u in window._telemtLastStats) { if (window._telemtLastStats.hasOwnProperty(u)) { var s = window._telemtLastStats[u]; var tx = (s.live_tx || 0) + (s.acc_tx || 0); var rx = (s.live_rx || 0) + (s.acc_rx || 0); var c = (s.conns || 0); csv += u + "," + tx + "," + rx + "," + c + "\n"; grandTx += tx; grandRx += rx; grandConns += c; } } csv += "TOTAL_ALL_USERS," + grandTx + "," + grandRx + "," + grandConns + "\n"; var blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' }); var link = document.createElement("a"); link.setAttribute("href", URL.createObjectURL(blob)); link.setAttribute("download", "telemt_traffic_stats.csv"); link.style.visibility = 'hidden'; document.body.appendChild(link); link.click(); document.body.removeChild(link); }
function doExportCSV() { logToRouter("Exporting Users to CSV"); var blob = new Blob(["]] .. clean_csv .. [["], { type: 'text/csv;charset=utf-8;' }); var link = document.createElement("a"); link.setAttribute("href", URL.createObjectURL(blob)); link.setAttribute("download", "telemt_users.csv"); link.style.visibility = 'hidden'; document.body.appendChild(link); link.click(); document.body.removeChild(link); }
function readCSVFile(input) { var file = input.files[0]; var displaySpan = document.getElementById('csv_file_name_display'); if (!file) { displaySpan.innerText = "No file selected"; return; } displaySpan.innerText = file.name; var reader = new FileReader(); reader.onload = function(e) { document.getElementById('csv_text_area').value = e.target.result; }; reader.readAsText(file); }

function submitImport() { 
    logToRouter("Executing Users Import"); var csv = document.getElementById('csv_text_area').value; var radioBtn = document.querySelector('input[name="import_mode"]:checked'); var mode = radioBtn ? radioBtn.value : 'replace';
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
        m.innerHTML = '<div class="custom-modal-content" style="text-align:left;"><h3 style="margin-top:0; margin-bottom:10px;">Import Users (CSV)</h3><p style="font-size:12px; opacity:0.8; line-height:1.4; margin-top:0;">Format: <b>username,secret,max_tcp_conns,max_unique_ips,data_quota,expire_date</b></p><div style="margin-bottom:15px; display:flex; gap:10px; align-items:center;"><input type="file" id="csv_file_input" accept=".csv" style="display:none;"><input type="button" class="cbi-button cbi-button-action" id="btn_csv_choose" value="Choose File..."><span id="csv_file_name_display" style="font-size:12px; opacity:0.8;">No file selected</span></div><textarea id="csv_text_area" placeholder="user1,164f44a...,50,5,1.5,31.12.2026 23:59\nuser2,..."></textarea><div style="margin-bottom:20px; font-size:13px;"><label style="display:flex; align-items:center; gap:5px; margin-bottom:8px;"><input type="radio" name="import_mode" value="replace" checked> <span><b>Replace</b> (Delete existing users)</span></label><label style="display:flex; align-items:center; gap:5px;"><input type="radio" name="import_mode" value="merge"> <span><b>Merge</b> (Keep existing)</span></label></div><div style="display:flex; gap:10px;"><input type="button" class="cbi-button cbi-button-apply" id="btn_csv_import" style="flex:1;" value="Import & Save"><input type="button" class="cbi-button cbi-button-reset" id="btn_csv_cancel" style="flex:1;" value="Cancel"></div></div>';
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
            
            // Row 1 & 2 Info Panel
            var infoPanel = document.createElement('div'); infoPanel.className = 'telemt-dash-info-panel';
            var row1 = document.createElement('div'); row1.id = 'telemt_dash_row1'; row1.className = 'telemt-dash-row';
            var row2 = document.createElement('div'); row2.id = 'telemt_dash_row2'; row2.className = 'telemt-dash-row';
            infoPanel.appendChild(row1); infoPanel.appendChild(row2);
            dash.appendChild(infoPanel);

            // Action Buttons Panel
            var actionPanel = document.createElement('div'); actionPanel.className = 'telemt-dash-action-panel';
            var btnExpStat = document.createElement('input'); btnExpStat.type = 'button'; btnExpStat.className = 'cbi-button cbi-button-apply'; btnExpStat.value = 'Export Stats'; btnExpStat.addEventListener('click', doExportStats); actionPanel.appendChild(btnExpStat);
            var btnRstStat = document.createElement('input'); btnRstStat.type = 'button'; btnRstStat.className = 'cbi-button cbi-button-remove'; btnRstStat.value = 'Reset Traffic Stats'; btnRstStat.addEventListener('click', function() { if(confirm('Clear RAM stats?')) { logAction('Reset Stats'); postAction('reset_stats'); } }); actionPanel.appendChild(btnRstStat);
            var btnImpCsv = document.createElement('input'); btnImpCsv.type = 'button'; btnImpCsv.className = 'cbi-button cbi-button-action'; btnImpCsv.value = 'Import CSV'; btnImpCsv.addEventListener('click', showImportModal); actionPanel.appendChild(btnImpCsv);
            var btnExpCsv = document.createElement('input'); btnExpCsv.type = 'button'; btnExpCsv.className = 'cbi-button cbi-button-action'; btnExpCsv.value = 'Export CSV'; btnExpCsv.addEventListener('click', doExportCSV); actionPanel.appendChild(btnExpCsv);
            dash.appendChild(actionPanel);
            
            var warnMsg = document.createElement('div'); warnMsg.className = 'telemt-dash-warn'; warnMsg.innerText = 'Important: You must create at least one active user for the proxy to start!'; dash.appendChild(warnMsg);
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
    
    var secretTh = document.querySelector('#cbi-telemt-user th[data-name="secret"]') || document.querySelector('#cbi-telemt-user .cbi-section-table-titles th:first-child') || document.querySelector('#cbi-telemt-user thead th:first-child');
    if (secretTh && !secretTh.dataset.renamed) { var txt = (secretTh.textContent || '').trim().toLowerCase(); if (txt == 'secret' || txt == 'секрет' || txt == 'name' || txt == '') { secretTh.textContent = 'User / Secret'; secretTh.dataset.renamed = "1"; } }
    
    var btnAdd = document.querySelector('#cbi-telemt-user .cbi-button-add'); if (btnAdd && btnAdd.value !== 'Add user') btnAdd.value = 'Add user';
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
                var nInp = row.querySelector('input[name*=".alias"]'); var aInp = row.querySelector('input[name*=".address"]');
                var vName = (nInp && nInp.value.trim() !== "") ? nInp.value.trim() : ''; var vAddr = (aInp && aInp.value.trim() !== "") ? aInp.value.trim() : '';
                var text = 'Cascade #' + (index + 1);
                if (vName || vAddr) { text += ' — ' + escHTML(vName ? vName : 'Unnamed'); if (vAddr) text += ' <span style="color:#888; font-weight:normal; font-size:0.9em;">(' + escHTML(vAddr) + ')</span>'; }
                titleSpan.innerHTML = text;
            };
            setTimeout(updateTitle, 100);
            row.addEventListener('input', function(e) { if(e.target && e.target.tagName === 'INPUT') { updateTitle(); } });
            var fields = Array.from(row.children).filter(function(child) { return child !== header && !child.classList.contains('cbi-section-remove'); });
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
            var secretTd = secInp.closest('td');
            if (secretTd) { var nameDiv = secretTd.querySelector('.telemt-fallback-name'); if (!nameDiv) { nameDiv = document.createElement('div'); nameDiv.className = 'telemt-fallback-name telemt-user-col-text'; nameDiv.style.cssText = 'margin-bottom: 6px; font-size: 1.1em; font-family: monospace; display: block; color: #005ce6 !important; font-weight: bold !important;'; secretTd.insertBefore(nameDiv, secretTd.firstChild); } nameDiv.innerText = '[ user: ' + uName + ' ]'; }
        } else {
            var firstCell = row.firstElementChild;
            if (firstCell && !firstCell.contains(secInp)) { var span = firstCell.querySelector('.telemt-user-col-text'); if (!span) { span = document.createElement('span'); span.className = 'telemt-user-col-text'; span.style.cssText = 'color: #005ce6 !important; font-weight: bold !important; margin-bottom: 4px; display: block;'; firstCell.insertBefore(span, firstCell.firstChild); } span.innerText = uName; }
        }
        
        if(secInp) {
            if(secInp.value.trim() === "") { secInp.value = genRandHex(); secInp.dispatchEvent(new Event('change', {bubbles: true})); }
            secInp.dataset.prevVal = secInp.value; var wrapper = document.createElement('div'); wrapper.className = 'telemt-sec-wrap'; secInp.parentNode.insertBefore(wrapper, secInp); wrapper.appendChild(secInp);
            var grp = document.createElement('div'); grp.className = 'telemt-sec-btns'; var bG = document.createElement('input'); bG.type = 'button'; bG.className = 'cbi-button cbi-button-apply'; bG.value = 'Gen'; bG.addEventListener('click', function(){ secInp.value = genRandHex(); updateLinks(); }); var bR = document.createElement('input'); bR.type = 'button'; bR.className = 'cbi-button cbi-button-reset'; bR.value = 'Rev'; bR.addEventListener('click', function(){ secInp.value = secInp.dataset.prevVal; updateLinks(); });
            grp.appendChild(bG); grp.appendChild(bR); wrapper.appendChild(grp);
        }
        
        var cb = row.querySelector('input[type="checkbox"][name*=".enabled"]');
        if (cb) { cb.addEventListener('change', function(e) { logToRouter("User " + uName + " manually " + (e.target.checked ? "Resumed" : "Paused")); }); }
        
        niList.forEach(function(ni){
            var propName = ni.name.match(/([^\.]+)$/); var fName = propName ? propName[1] : "limit";
            ni.addEventListener('change', function(e) { logToRouter("User " + uName + " " + fName + " changed to: " + (e.target.value || "unlimited")); if (fName === 'expire_date' || fName === 'data_quota') { if (cb && !cb.checked) { cb.checked = true; logToRouter("User " + uName + " auto-resumed due to " + fName + " update"); } } });
            var wrapper = document.createElement('div'); wrapper.className = 'telemt-num-wrap'; ni.parentNode.insertBefore(wrapper, ni); wrapper.appendChild(ni);
            if(ni.name.indexOf('expire_date') !== -1) {
                var calContainer = document.createElement('div'); calContainer.className = 'telemt-cal-wrap'; var calBtn = document.createElement('input'); calBtn.type = 'button'; calBtn.className = 'cbi-button cbi-button-action telemt-btn-cal'; calBtn.title = 'Select Date'; calBtn.value = ' ';
                var picker = document.createElement('input'); picker.type = 'datetime-local'; picker.className = 'telemt-cal-picker'; picker.addEventListener('change', function(e) { var val = e.target.value; if(val) { var parts = val.split('T'); var dParts = parts[0].split('-'); if(dParts.length === 3) { ni.value = dParts[2] + '.' + dParts[1] + '.' + dParts[0] + ' ' + parts[1]; ni.dispatchEvent(new Event('change', {bubbles:true})); } } });
                calContainer.appendChild(calBtn); calContainer.appendChild(picker); wrapper.appendChild(calContainer);
            }
            var bD = document.createElement('input'); bD.type = 'button'; bD.className = 'cbi-button cbi-button-reset telemt-btn-cross'; bD.title = 'Reset value'; bD.value = ' '; bD.addEventListener('click', function(){ ni.value = ''; ni.dispatchEvent(new Event('change', {bubbles:true})); }); wrapper.appendChild(bD);
        });
        
        if(linkWrap) { var btnGrp = document.createElement('div'); btnGrp.className = 'link-btn-group'; var bC = document.createElement('input'); bC.type = 'button'; bC.className = 'cbi-button cbi-button-action btn-copy-custom'; bC.value = 'Copy'; bC.addEventListener('click', function(){ copyProxyLink(this); }); btnGrp.appendChild(bC); var bQ = document.createElement('input'); bQ.type = 'button'; bQ.className = 'cbi-button cbi-button-neural btn-qr-custom'; bQ.value = 'QR'; bQ.addEventListener('click', function(){ showQRModal(linkWrap.querySelector('.user-link-out').value); }); btnGrp.appendChild(bQ); linkWrap.appendChild(btnGrp); }
    });
}

var metricsTimer = null; var fwTimer = null;
function startTimers() { if (!metricsTimer) metricsTimer = setInterval(fetchMetrics, 2500); if (!fwTimer) fwTimer = setInterval(updateFWStatus, 15000); }
function stopTimers() { if (metricsTimer) { clearInterval(metricsTimer); metricsTimer = null; } if (fwTimer) { clearInterval(fwTimer); fwTimer = null; } }

document.addEventListener('visibilitychange', function () { if (document.hidden) { stopTimers(); } else { window._telemtLastTime = 0; fetchMetrics(); updateFWStatus(); startTimers(); } });
document.addEventListener('input', function(e) { if (e.target && e.target.matches('input, select')) { if(e.target.id === 'telemt_mirror_ip') { var master = document.querySelector('input[name*="cbid.telemt.general.external_ip"]'); if(master) { master.value = e.target.value; master.dispatchEvent(new Event('change')); } } else if (e.target.name && e.target.name.indexOf('cbid.telemt.general.external_ip') > -1) { var mirror = document.getElementById('telemt_mirror_ip'); if(mirror) mirror.value = e.target.value; } updateLinks(); } });

function initTelemt() {
    injectUI(); updateLinks(); updateFWStatus(); fetchMetrics(); setTimeout(function(){ injectUI(); updateLinks(); }, 200); setTimeout(function(){ injectUI(); updateLinks(); updateFWStatus(); }, 1200); 
    if (window.location.search.indexOf('import_ok=') > -1) { var match = window.location.search.match(/import_ok=(\d+)/); if (match && match[1]) { setTimeout(function() { alert("Successfully imported " + match[1] + " users from CSV!"); }, 300); if (window.history && window.history.replaceState) { window.history.replaceState({}, document.title, window.location.protocol + "//" + window.location.host + window.location.pathname); } } }
    if (typeof window.MutationObserver !== 'undefined') { var _injecting = false; var domObserver = new MutationObserver(function(mutations) { if (_injecting) return; var needsUpdate = false; for (var i = 0; i < mutations.length; i++) { if (mutations[i].target.id === 'cbi-telemt-user' || mutations[i].target.id === 'cbi-telemt-upstream' || (mutations[i].target.closest && mutations[i].target.closest('#cbi-telemt-user'))) { needsUpdate = true; break; } } if (needsUpdate) { _injecting = true; injectUI(); updateLinks(); _injecting = false; } }); domObserver.observe(document.getElementById('maincontent') || document.body, { childList: true, subtree: true }); } else { setInterval(function(){ injectUI(); updateLinks(); }, 2500); }
    startTimers();
}
if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', initTelemt); } else { initTelemt(); }
</script>
]] .. (m.description or "")

return m
