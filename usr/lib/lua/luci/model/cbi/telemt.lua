-- ==============================================================================
-- Telemt CBI Model (Configuration Binding Interface)
-- Version: 3.1.2-7 (Upstream Master Switch)
-- ==============================================================================

local sys = require "luci.sys"
local http = require "luci.http"
local dsp = require "luci.dispatcher"
local uci_cursor = require("luci.model.uci").cursor()

local function has_cmd(c) return (sys.call("command -v " .. c .. " >/dev/null 2>&1") == 0) end
local fetch_bin = nil
if has_cmd("wget") then fetch_bin = "wget" elseif has_cmd("uclient-fetch") then fetch_bin = "uclient-fetch" end

local function read_file(path)
    local f = io.open(path, "r"); if not f then return "" end
    local d = f:read("*all") or ""; f:close(); return (d:gsub("%s+", ""))
end

local is_owrt25_lua = "false"
local ow_rel = sys.exec("cat /etc/openwrt_release 2>/dev/null") or ""
if ow_rel:match("DISTRIB_RELEASE='25") or ow_rel:match('DISTRIB_RELEASE="25') or ow_rel:match("SNAPSHOT") or ow_rel:match("%-rc") then
    is_owrt25_lua = "true"
end

local _unpack = unpack or table.unpack
local _ok_url, current_url = pcall(function()
    if dsp.context and dsp.context.request then return dsp.build_url(_unpack(dsp.context.request)) end return nil
end)
if not _ok_url or not current_url or current_url == "" then current_url = dsp.build_url("admin", "services", "telemt") end
local safe_url = current_url:gsub('"', '\\"'):gsub('<', '&lt;'):gsub('>', '&gt;')

local function tip(txt) return string.format([[<span class="telemt-tip" title="%s">(?)</span>]], txt:gsub('"', '&quot;')) end

local is_post = (http.getenv("REQUEST_METHOD") == "POST")

if is_post and http.formvalue("log_ui_event") == "1" then
    local msg = http.formvalue("msg")
    if msg then sys.call(string.format("logger -t telemt %q", "WebUI: " .. msg:gsub("[%c]", " "):gsub("[^A-Za-z0-9 _.%-]", ""):sub(1, 128))) end
    http.prepare_content("text/plain"); http.write("ok"); http.close(); return
end

if is_post and http.formvalue("reset_stats") == "1" then
    sys.call("logger -t telemt 'WebUI: Executed manual Reset Traffic Stats'"); sys.call("rm -f /tmp/telemt_stats.txt")
    http.redirect(current_url); return
end

if is_post and http.formvalue("start") == "1" then 
    sys.call("logger -t telemt 'WebUI: Manual START'"); sys.call("/etc/init.d/telemt start")
    http.redirect(current_url); return 
end

if is_post and http.formvalue("stop") == "1" then 
    sys.call("logger -t telemt 'WebUI: Manual STOP'"); sys.call("/etc/init.d/telemt run_save_stats 2>/dev/null; /etc/init.d/telemt stop; sleep 1; pidof telemt >/dev/null && killall -9 telemt 2>/dev/null")
    http.redirect(current_url); return 
end

if is_post and http.formvalue("restart") == "1" then 
    sys.call("logger -t telemt 'WebUI: Manual RESTART'"); sys.call("/etc/init.d/telemt run_save_stats 2>/dev/null; /etc/init.d/telemt stop; sleep 1; pidof telemt >/dev/null && killall -9 telemt 2>/dev/null; /etc/init.d/telemt start")
    http.redirect(current_url); return 
end

local is_ajax = (http.formvalue("get_metrics") or http.formvalue("get_fw_status") or http.formvalue("get_log") or http.formvalue("get_wan_ip") or http.formvalue("get_qr") or http.formvalue("log_ui_event"))

if http.formvalue("get_fw_status") == "1" then
    local afw = uci_cursor:get("telemt", "general", "auto_fw") or "0"
    local port = tonumber(uci_cursor:get("telemt", "general", "port")) or 4443
    http.prepare_content("text/plain")
    local cmd = string.format("/bin/sh -c \"iptables-save 2>/dev/null | grep -qiE 'Allow-Telemt-Magic|dport.*%d.*accept' || nft list ruleset 2>/dev/null | grep -qiE 'Allow-Telemt-Magic|dport.*%d.*accept'\"", port, port)
    local is_physically_open = (sys.call(cmd) == 0)
    local procd_check = sys.exec("ubus call service list '{\"name\":\"telemt\"}' 2>/dev/null")
    local is_procd_open = (procd_check and procd_check:match("firewall") and procd_check:match("Allow%-Telemt%-Magic"))
    local is_running = (sys.call("pidof telemt >/dev/null 2>&1") == 0)
    
    local status_msg = ""; local tip_msg = ""
    if is_physically_open then status_msg = "<span style='color:green; font-weight:bold'>OPEN (OK)</span>"; if afw == "0" then tip_msg = "(Auto-FW disabled, but port is open in FW rules)" end
    elseif is_procd_open and is_running then status_msg = "<span style='color:green; font-weight:bold'>OPEN (OK)</span>"; tip_msg = "(Not visible in FW rules. Manual port opening recommended)"
    else status_msg = "<span style='color:red; font-weight:bold'>CLOSED</span>"; tip_msg = "(Port not found in FW rules. Consider adding manually)" end
    if not is_running then status_msg = "<span style='color:#d9534f; font-weight:bold'>SERVICE STOPPED</span> <span style='color:#888'>|</span> " .. status_msg end
    http.write(status_msg .. " <span style='color:#888; font-size:0.85em; margin-left:5px;'>" .. tip_msg .. "</span>"); http.close(); return
end

if http.formvalue("get_metrics") == "1" then
    local m_port = tonumber(uci_cursor:get("telemt", "general", "metrics_port")) or 9091
    local metrics = ""
    if sys.call("pidof telemt >/dev/null 2>&1") == 0 then
        local fetch_cmd = (fetch_bin == "wget") and "wget -q --timeout=3 -O -" or "uclient-fetch -q --timeout=3 -O -"
        metrics = sys.exec(string.format("%s 'http://127.0.0.1:%d/metrics' 2>/dev/null", fetch_cmd, m_port) .. " | grep -E '^telemt_user|^telemt_uptime|^telemt_connections|^telemt_desync_total'") or ""
    end
    local f = io.open("/tmp/telemt_stats.txt", "r")
    if f then
        metrics = metrics .. "\n# ACCUMULATED\n"
        for line in f:lines() do
            local u, tx, rx = line:match("^(%S+) (%S+) (%S+)$")
            if u then metrics = metrics .. string.format("telemt_accumulated_tx{user=\"%s\"} %s\ntelemt_accumulated_rx{user=\"%s\"} %s\n", u, tx, u, rx) end
        end
        f:close()
    end
    http.prepare_content("text/plain"); http.write(metrics); http.close(); return
end

if http.formvalue("get_log") == "1" then
    http.prepare_content("text/plain")
    local cmd = "logread -e 'telemt' | tail -n 50 2>/dev/null"
    if has_cmd("timeout") then cmd = "timeout 2 " .. cmd end
    local log_data = sys.exec(cmd); if not log_data or log_data:gsub("%s+", "") == "" then log_data = "No logs found." end
    http.write(log_data:gsub("\27%[[%d;]*m", "")); http.close(); return
end

if http.formvalue("get_wan_ip") == "1" then
    http.prepare_content("text/plain")
    local fetch_cmd = (fetch_bin == "wget") and "wget -q --timeout=3 -O -" or "uclient-fetch -q --timeout=3 -O -"
    local ip = sys.exec(fetch_cmd .. " https://ipv4.internet.yandex.net/api/v0/ip 2>/dev/null") or ""
    ip = ip:gsub("%s+", ""):gsub("\"", "")
    if not ip:match("^%d+%.%d+%.%d+%.%d+$") then ip = sys.exec(fetch_cmd .. " https://checkip.amazonaws.com 2>/dev/null") or ""; ip = ip:gsub("%s+", "") end
    if not ip:match("^%d+%.%d+%.%d+%.%d+$") then ip = "0.0.0.0" end
    http.write(ip); http.close(); return
end

local bin_info = ""
if not is_ajax then
    local bin_path = (sys.exec("command -v telemt 2>/dev/null") or ""):gsub("%s+", "")
    if bin_path == "" then bin_info = "<span style='color:#d9534f; font-weight:bold; font-size:0.9em;'>Not installed (telemt binary not found)</span>"
    else local ver = read_file("/var/etc/telemt.version"); if ver == "" then ver = "unknown" end; bin_info = string.format("<small style='opacity: 0.6;'>%s (v%s)</small>", bin_path, ver) end
end

m = Map("telemt", "Telegram Proxy (MTProto)", [[Multi-user proxy server based on <a href="https://github.com/telemt/telemt" target="_blank" style="text-decoration:none; color:inherit; font-weight:bold; border-bottom: 1px dotted currentColor;">telemt</a>.<br><b>LuCI App Version: 3.1.2-7</b>]])
m.on_commit = function(self) sys.call("logger -t telemt 'WebUI: Config saved. Dumping stats before procd reload...'; /etc/init.d/telemt run_save_stats 2>/dev/null") end

s = m:section(NamedSection, "general", "telemt")
s:tab("general", "General Settings")
s:tab("upstream", "Upstream Proxy")
s:tab("users", "Users")
s:tab("advanced", "Advanced Tuning")
s:tab("bot", "Telegram Bot")
s:tab("log", "Diagnostics")
s.anonymous = true

-- Вкладка: GENERAL
s:taboption("general", Flag, "enabled", "Enable Service")
local ctrl = s:taboption("general", DummyValue, "_controls", "Controls")
ctrl.rawhtml = true; ctrl.default = string.format([[<div class="btn-controls"><input type="button" class="cbi-button cbi-button-apply" id="btn_telemt_start" value="Start" /><input type="button" class="cbi-button cbi-button-reset" id="btn_telemt_stop" value="Stop" /><input type="button" class="cbi-button cbi-button-reload" id="btn_telemt_restart" value="Restart" /></div><script>function postAction(action) { var form = document.createElement('form'); form.method = 'POST'; form.action = '%s'.split('#')[0]; var input = document.createElement('input'); input.type = 'hidden'; input.name = action; input.value = '1'; form.appendChild(input); var token = document.querySelector('input[name="token"]'); if (token) { var t = document.createElement('input'); t.type = 'hidden'; t.name = 'token'; t.value = token.value; form.appendChild(t); } else if (typeof L !== 'undefined' && L.env && L.env.token) { var t2 = document.createElement('input'); t2.type = 'hidden'; t2.name = 'token'; t2.value = L.env.token; form.appendChild(t2); } document.body.appendChild(form); form.submit(); } setTimeout(function(){ var b1=document.getElementById('btn_telemt_start'); if(b1) b1.addEventListener('click', function(){ logAction('Manual Start'); postAction('start'); }); var b2=document.getElementById('btn_telemt_stop'); if(b2) b2.addEventListener('click', function(){ logAction('Manual Stop'); postAction('stop'); }); var b3=document.getElementById('btn_telemt_restart'); if(b3) b3.addEventListener('click', function(){ logAction('Manual Restart'); postAction('restart'); }); }, 500);</script>]], current_url)

local pid = ""
if not is_ajax then pid = (sys.exec("pidof telemt | awk '{print $1}'") or ""):gsub("%s+", "") end
local process_status = "<span style='color:#d9534f; font-weight:bold;'>STOPPED</span><br>" .. bin_info
if pid ~= "" and sys.call("kill -0 " .. pid .. " 2>/dev/null") == 0 then process_status = string.format("<span style='color:green;font-weight:bold'>RUNNING (PID: %s)</span><br>%s", pid, bin_info) end
local st = s:taboption("general", DummyValue, "_status", "Process Status"); st.rawhtml = true; st.value = process_status

local mode = s:taboption("general", ListValue, "mode", "Protocol Mode"); mode:value("tls", "FakeTLS (Recommended)"); mode:value("dd", "DD (Random Padding)"); mode:value("classic", "Classic"); mode:value("all", "All together (Debug)"); mode.default = "tls"
local lfmt = s:taboption("general", ListValue, "_link_fmt", "Link Format to Display"); lfmt:depends("mode", "all"); lfmt:value("tls", "FakeTLS (Recommended)"); lfmt:value("dd", "Secure (DD)"); lfmt:value("classic", "Classic"); lfmt.default = "tls"
local dom = s:taboption("general", Value, "domain", "FakeTLS Domain"); dom.datatype = "hostname"; dom.default = "google.com"; dom.description = "<span class='warn-txt' style='color:#d35400; font-weight:bold;'>Warning: Change the default domain!</span>"; dom:depends("mode", "tls"); dom:depends("mode", "all")

local saved_ip = m.uci:get("telemt", "general", "external_ip")
if type(saved_ip) == "table" then saved_ip = saved_ip[1] or "" end
saved_ip = saved_ip or ""; if saved_ip:match("%s") then saved_ip = saved_ip:match("^([^%s]+)") end

local myip = s:taboption("general", Value, "external_ip", "External IP / DynDNS" .. tip("For proxy links")); myip.datatype = "string"; myip.default = saved_ip
local p = s:taboption("general", Value, "port", "Proxy Port"); p.datatype = "port"; p.rmempty = false
local afw = s:taboption("general", Flag, "auto_fw", "Auto-open Port (Magic)"); afw.default = "0"; afw.description = string.format("<div style='margin-top:5px; padding:8px; background:rgba(128,128,128,0.1); border-left:3px solid #00a000; font-size:0.9em;'><b>Current Status:</b> <span id='fw_status_span' style='color:#888; font-style:italic;'>Checking...</span></div>")
local hll = s:taboption("general", DummyValue, "_head_ll"); hll.rawhtml = true; hll.default = "<h3 style='margin-top:20px;'>Logging</h3>"
local ll = s:taboption("general", ListValue, "log_level", "Log Level"); ll:value("debug", "Debug"); ll:value("verbose", "Verbose"); ll:value("normal", "Normal (default)"); ll:value("silent", "Silent"); ll.default = "normal"


-- Вкладка: UPSTREAMS (Мастер-рубильник и Якорь)
local up_master = s:taboption("upstream", Flag, "enable_upstreams", "Enable Upstream Routing" .. tip("Master switch. If unchecked, all proxy traffic is routed Direct.")); up_master.default = "0"
local anchor_up = s:taboption("upstream", DummyValue, "_up_anchor", ""); anchor_up.rawhtml = true; anchor_up.default = '<div id="upstreams_tab_anchor" style="display:none"></div>'

-- Вкладка: USERS (Якорь)
local anchor = s:taboption("users", DummyValue, "_users_anchor", ""); anchor.rawhtml = true; anchor.default = '<div id="users_tab_anchor" style="display:none"></div>'
local myip_u = s:taboption("users", DummyValue, "_ip_display", "External IP / DynDNS" .. tip("IP address or domain used for generating tg:// links.")); myip_u.rawhtml = true; myip_u.default = string.format([[<input type="text" class="cbi-input-text" style="width:250px;" id="telemt_mirror_ip" value="%s">]], saved_ip)

-- Вкладка: ADVANCED TUNING
local hnet = s:taboption("advanced", DummyValue, "_head_net"); hnet.rawhtml = true; hnet.default = "<h3 style='margin-top:15px;'>Network Listeners</h3>"
s:taboption("advanced", Flag, "listen_ipv4", "Enable IPv4 Listener").default = "1"
s:taboption("advanced", Flag, "listen_ipv6", "Enable IPv6 Listener (::)").default = "0"
local pref_ip = s:taboption("advanced", ListValue, "prefer_ip", "Preferred IP Protocol"); pref_ip:value("4", "IPv4"); pref_ip:value("6", "IPv6"); pref_ip.default = "4"

local hme = s:taboption("advanced", DummyValue, "_head_me"); hme.rawhtml = true; hme.default = "<h3 style='margin-top:20px;'>Middle-End Proxy</h3>"
local mp = s:taboption("advanced", Flag, "use_middle_proxy", "Use ME Proxy"); mp.default = "0"; mp.description = "<span style='color:#d35400; font-weight:bold;'>Requires public IP on interface OR NAT 1:1 with STUN enabled.</span>"
local stun = s:taboption("advanced", Flag, "use_stun", "Enable STUN-probing"); stun:depends("use_middle_proxy", "1"); stun.default = "1"
s:taboption("advanced", Value, "me_pool_size", "ME Pool Size"):depends("use_middle_proxy", "1")
s:taboption("advanced", Value, "me_warm_standby", "ME Warm Standby"):depends("use_middle_proxy", "1")
s:taboption("advanced", Flag, "hardswap", "ME Pool Hardswap"):depends("use_middle_proxy", "1")
s:taboption("advanced", Value, "me_drain_ttl", "ME Drain TTL (sec)"):depends("use_middle_proxy", "1")
local auto_deg = s:taboption("advanced", Flag, "auto_degradation", "Auto-Degradation"); auto_deg:depends("use_middle_proxy", "1"); auto_deg.default = "1"
s:taboption("advanced", Value, "degradation_min_dc", "Degradation Min DC"):depends("auto_degradation", "1")

local hadv = s:taboption("advanced", DummyValue, "_head_adv"); hadv.rawhtml = true
hadv.default = [[<details id="telemt_adv_opts_details" style="margin-top:20px; margin-bottom:15px; padding:10px; background:rgba(128,128,128,0.05); border:1px solid rgba(128,128,128,0.3); border-radius:6px; cursor:pointer;"><summary style="font-weight:bold; outline:none;">Additional Options (Click to expand)</summary></details><script>setTimeout(function(){var d=document.getElementById('telemt_adv_opts_details');if(!d)return;['desync_all_full','mask_proxy_protocol','announce_ip','ad_tag','fake_cert_len','tls_full_cert_ttl_secs','ignore_time_skew'].forEach(function(name){var el=document.querySelector('.cbi-value[data-name="'+name+'"]');if(el){el.style.paddingLeft='15px';d.appendChild(el);}});}, 300);</script>]]

s:taboption("advanced", Flag, "desync_all_full", "Full Crypto-Desync Logs").default = "0"
local mpp = s:taboption("advanced", ListValue, "mask_proxy_protocol", "Mask Proxy Protocol" .. tip("Send PROXY protocol header to mask_host")); mpp:value("0", "0 (Off)"); mpp:value("1", "1 (v1 - Text)"); mpp:value("2", "2 (v2 - Binary)"); mpp.default = "0"
s:taboption("advanced", Value, "announce_ip", "Announce Address").datatype = "string"
s:taboption("advanced", Value, "ad_tag", "Ad Tag").datatype = "hexstring"
s:taboption("advanced", Value, "fake_cert_len", "Fake Cert Length").datatype = "uinteger"
s:taboption("advanced", Value, "tls_full_cert_ttl_secs", "TLS Full Cert TTL (sec)").datatype = "uinteger"
s:taboption("advanced", Flag, "ignore_time_skew", "Ignore Time Skew").default = "0"

local htm = s:taboption("advanced", DummyValue, "_head_tm"); htm.rawhtml = true
htm.default = [[<details id="telemt_timeouts_details" style="margin-top:20px; margin-bottom:15px; padding:10px; background:rgba(128,128,128,0.05); border:1px solid rgba(128,128,128,0.3); border-radius:6px; cursor:pointer;"><summary style="font-weight:bold; outline:none;">Timeouts & Replay Protection (Click to expand)</summary></details><script>setTimeout(function(){var details=document.getElementById('telemt_timeouts_details');if(!details)return;['tm_handshake','tm_connect','tm_keepalive','tm_ack','replay_window_secs'].forEach(function(name){var el=document.querySelector('.cbi-value[data-name="'+name+'"]');if(el){el.style.paddingLeft='15px';details.appendChild(el);}});}, 300);</script>]]
s:taboption("advanced", Value, "tm_handshake", "Handshake").default = "15"
s:taboption("advanced", Value, "tm_connect", "Connect").default = "10"
s:taboption("advanced", Value, "tm_keepalive", "Keepalive").default = "60"
s:taboption("advanced", Value, "tm_ack", "ACK").default = "300"
s:taboption("advanced", Value, "replay_window_secs", "Replay Window (sec)").default = "1800"

local hmet = s:taboption("advanced", DummyValue, "_head_met"); hmet.rawhtml = true; hmet.default = "<h3 style='margin-top:20px;'>Metrics & Prometheus API</h3>"
s:taboption("advanced", Value, "metrics_port", "Metrics Port").default = "9091"
s:taboption("advanced", Flag, "metrics_allow_lo", "Allow Localhost").default = "1"
s:taboption("advanced", Flag, "metrics_allow_lan", "Allow LAN Subnet").default = "1"
s:taboption("advanced", Value, "metrics_whitelist", "Additional Whitelist").placeholder = "e.g. 10.8.0.0/24"
local cur_m_port = tonumber(m.uci:get("telemt", "general", "metrics_port")) or 9091
local mlink = s:taboption("advanced", DummyValue, "_mlink", "Prometheus Endpoint"); mlink.rawhtml = true; mlink.default = string.format([[<a href="http://127.0.0.1:%d/metrics" target="_blank" style="font-family: monospace; color:#00a000;">http://&lt;router_ip&gt;:%d/metrics</a>]], cur_m_port, cur_m_port)

-- Вкладка: TELEGRAM BOT (Заготовка)
local bot_head = s:taboption("bot", DummyValue, "_bot_head", ""); bot_head.rawhtml = true
bot_head.default = [[<div style="padding:15px; background:rgba(0,136,204,0.05); border-left:4px solid #0088cc; border-radius:4px; margin-bottom:20px;">
<h3 style="margin-top:0; color:#0088cc;">Telegram Bot & Alerts</h3>
<p style="margin-bottom:0; font-size:0.95em;">The bot feature is currently under development. Here you will be able to set up automatic alerts, daily traffic reports, and remote control via Telegram.</p></div>]]

s:taboption("bot", Flag, "bot_enabled", "Enable Bot").default = "0"
s:taboption("bot", Value, "bot_token", "Bot Token" .. tip("From @BotFather"))
s:taboption("bot", Value, "bot_chat_id", "Admin Chat ID" .. tip("Your personal ID or Group ID"))

-- Вкладка: LOGS
local lv = s:taboption("log", DummyValue, "_lv"); lv.rawhtml = true
lv.default = [[<div style="width:100%; height:500px; font-family:monospace; font-size:12px; padding:12px; background:#1e1e1e; color:#d4d4d4; border:1px solid #333; overflow-y:auto; white-space:pre;" id="telemt_log_container">Click "Load Log" to view system logs.</div><div style="margin-top:10px;"><input type="button" class="cbi-button cbi-button-apply" id="btn_load_log" value="Load Log" /></div><script>setTimeout(function(){ var b1=document.getElementById('btn_load_log'); if(b1) b1.addEventListener('click', loadLog); }, 500);</script>]]


-- СЕКЦИЯ 1: UPSTREAMS (Каскад прокси)
s3 = m:section(TypedSection, "upstream", "Routing Chain")
s3.addremove = true
s3.anonymous = false

local up_en = s3:option(Flag, "enabled", "Enable")
up_en.default = "1"; up_en.rmempty = false

local up_type = s3:option(ListValue, "type", "Protocol Type")
up_type:value("direct", "Direct")
up_type:value("socks4", "SOCKS4")
up_type:value("socks5", "SOCKS5")
up_type.default = "socks5"

local up_addr = s3:option(Value, "address", "Address (IP:Port)")
up_addr.placeholder = "192.168.1.1:1080"
up_addr:depends("type", "socks4")
up_addr:depends("type", "socks5")

local up_user = s3:option(Value, "username", "Username")
up_user:depends("type", "socks5")

local up_pass = s3:option(Value, "password", "Password")
up_pass.password = true
up_pass:depends("type", "socks5")

local up_weight = s3:option(Value, "weight", "Weight")
up_weight.datatype = "uinteger"
up_weight.default = "10"


-- СЕКЦИЯ 2: USERS 
s2 = m:section(TypedSection, "user", "")
s2.template = "cbi/tblsection"
s2.addremove = true
s2.anonymous = false

local sec = s2:option(Value, "secret", "Secret (32 hex)")
sec.rmempty = false; sec.datatype = "hexstring"
local t_con = s2:option(Value, "max_tcp_conns", "TCP Conns"); t_con.datatype = "uinteger"; t_con.placeholder = "unlimited"
local t_uips = s2:option(Value, "max_unique_ips", "Max IPs"); t_uips.datatype = "uinteger"; t_uips.placeholder = "unlimited"
local t_qta = s2:option(Value, "data_quota", "Quota (GB)"); t_qta.datatype = "ufloat"; t_qta.placeholder = "unlimited"
local t_exp = s2:option(Value, "expire_date", "Expire Date"); t_exp.placeholder = "DD.MM.YYYY HH:MM"
local lst = s2:option(DummyValue, "_stat", "Live Traffic"); lst.rawhtml = true; function lst.cfgvalue(self, section) return string.format('<div class="user-flat-stat" data-user="%s"><span style="color:#888;">No Data</span></div>', section:gsub("[<>&\"']", "")) end
local lnk = s2:option(DummyValue, "_link", "Ready-to-use link"); lnk.rawhtml = true; lnk.default = [[<div class="link-wrapper"><input type="text" class="cbi-input-text user-link-out" readonly onclick="this.select()"></div>]]

m.description = [[
<style>
.cbi-value-helpicon, img[src*="help.gif"], img[src*="help.png"] { display: none !important; }
#cbi-telemt-user .cbi-section-table-descr { display: none !important; width: 0; height: 0; visibility: hidden; }
#cbi-telemt-user .cbi-row-template, #cbi-telemt-user [id*="-template"] { display: none !important; visibility: hidden !important; }

/* Global Buttons */
.cbi-button-add { color: #00a000 !important; -webkit-text-fill-color: #00a000 !important; background: transparent !important; border: 1px solid #00a000 !important; font-weight: bold !important; border-radius:4px; padding: 0 16px !important; height: 32px !important; }
.cbi-button-add:hover { background: #00a000 !important; color: #fff !important; -webkit-text-fill-color: #fff !important; }
.cbi-button-remove:not(.telemt-btn-cross), .cbi-button-del { color: #d9534f !important; -webkit-text-fill-color: #d9534f !important; background: transparent !important; border: 1px solid #d9534f !important; height: 30px !important; padding: 0 12px !important; }
.cbi-button-remove:not(.telemt-btn-cross):hover, .cbi-button-del:hover { background: #d9534f !important; color: #fff !important; -webkit-text-fill-color: #fff !important; }

.telemt-tip { display: inline-block !important; cursor: help; opacity: 0.5; font-size: 0.85em; border-bottom: 1px dotted currentColor; margin-left: 4px; }
.telemt-user-col-text { font-weight: bold !important; color: #005ce6 !important; white-space: nowrap !important; }
@media (prefers-color-scheme: dark) { .telemt-user-col-text { color: #4da6ff !important; } }

/* Table formatting */
.cbi-section-table th { white-space: nowrap !important; vertical-align: middle !important; }
.cbi-section-table td { padding: 6px 8px !important; vertical-align: middle !important; }
#cbi-telemt-user .cbi-section-table td:last-child { width: 1% !important; white-space: nowrap !important; }

/* Controls */
#telemt_mirror_ip, input[name*="cbid.telemt.general.external_ip"] { flex: 0 1 250px !important; width: 250px !important; }
.telemt-sec-wrap { display: flex; flex-direction: column; width: 100%; gap:4px; }
.telemt-sec-btns, .link-btn-group { display: flex; gap:4px; }
.telemt-sec-btns input.cbi-button, .link-btn-group input.cbi-button { flex: 1; height: 20px !important; line-height: 18px !important; padding: 0 8px !important; font-size: 11px !important; }
.telemt-num-wrap { display: flex !important; align-items: center !important; gap: 4px; height: 32px; }
.telemt-num-wrap > input:not([type="button"]) { flex: 1 1 auto !important; width: 100% !important; min-width: 40px !important; height: 100% !important; margin: 0 !important; }

/* Icons */
.telemt-btn-cross { flex: 0 0 24px !important; width: 24px !important; height: 24px !important; cursor: pointer; background: transparent url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23666666' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cline x1='18' y1='6' x2='6' y2='18'/%3E%3Cline x1='6' y1='6' x2='18' y2='18'/%3E%3C/svg%3E") no-repeat center / 14px !important; border: none !important; opacity: 1 !important; }
.telemt-btn-cross:hover { background-color: rgba(217, 83, 79, 0.1) !important; border-radius: 4px; background-image: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23d9534f' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cline x1='18' y1='6' x2='6' y2='18'/%3E%3Cline x1='6' y1='6' x2='18' y2='18'/%3E%3C/svg%3E") !important; }

#cbi-telemt-user .user-link-out { height: 32px !important; width: 100%; font-family: monospace; font-size: 11px; background: transparent !important; color: inherit !important; border: 1px solid var(--border-color, rgba(128,128,128,0.5)) !important; cursor: pointer; }
.user-link-err { color: #d9534f !important; font-weight: bold; border-color: #d9534f !important; }

/* Dashboard */
.telemt-dash-top-row { display:flex; justify-content:space-between; align-items:center; padding:12px; background:rgba(0,160,0,0.05); border:1px solid rgba(0,160,0,0.2); border-radius:6px; margin-bottom:15px; flex-wrap:wrap; gap:15px; }
.telemt-dash-summary { font-size:1.05em; display:flex; flex-wrap:wrap; align-items:center; gap:12px; }
.stat-divider, .sum-divider { color: #ccc; margin: 0 4px; }
.telemt-conns-bold { font-weight: bold; }
</style>

<script type="text/javascript">
var lu_current_url = "]] .. safe_url .. [[";
var is_owrt25 = ]] .. is_owrt25_lua .. [[;

function logAction(msg) { console.log("[Telemt UI] " + msg); }
function formatMB(b) { if(!b) return '0.00 MB'; var mb = b/1048576; return mb>=1024 ? (mb/1024).toFixed(2)+' GB' : mb.toFixed(2)+' MB'; }
function formatUptime(s) { if(!s) return '0s'; var d=Math.floor(s/86400), h=Math.floor((s%86400)/3600), m=Math.floor((s%3600)/60); var str=""; if(d>0) str+=d+"d "; if(h>0||d>0) str+=h+"h "; return str+m+"m"; }

window._telemtLastStats = null;
function fetchMetrics() {
    if (!document.getElementById('cbi-telemt-user')) return;
    if (window._telemtFetching) return; window._telemtFetching = true;
    fetch(lu_current_url.split('#')[0] + (lu_current_url.indexOf('?') > -1 ? '&' : '?') + 'get_metrics=1&_t=' + Date.now()).then(r => r.text()).then(txt => {
        window._telemtFetching = false; txt = (txt || "");
        var userStats = {}; var allUserRows = document.querySelectorAll('.user-flat-stat');
        allUserRows.forEach(function(el) { var u = el.getAttribute('data-user'); if(u) userStats[u] = { live_rx:0, live_tx:0, acc_rx:0, acc_tx:0, conns:0 }; });
        var g = { uptime:0, dpiProbes:0 }; var totalRx=0, totalTx=0;
        var lines = txt.split('\n');
        for (var i=0; i<lines.length; i++) {
            var l = lines[i].trim(); if (l==="" || l.indexOf('#')===0) continue;
            if (l.indexOf('telemt_uptime_seconds')===0) { g.uptime = parseFloat(l.match(/\s+([0-9\.eE\+\-]+)/)[1]); continue; }
            if (l.indexOf('telemt_desync_total ')===0) { g.dpiProbes = parseInt(l.match(/\s+([0-9\.eE\+\-]+)/)[1]); continue; }
            var m = l.match(/user="([^"]+)"/);
            if (m) {
                var u = m[1]; if(!userStats[u]) userStats[u] = { live_rx:0, live_tx:0, acc_rx:0, acc_tx:0, conns:0 };
                var vM = l.match(/\}\s+([0-9\.eE\+\-]+)/); if(!vM) continue; var val = parseFloat(vM[1]);
                if (l.indexOf('_octets_from_client')>-1) { userStats[u].live_rx=val; totalRx+=val; }
                else if (l.indexOf('_octets_to_client')>-1) { userStats[u].live_tx=val; totalTx+=val; }
                else if (l.indexOf('_connections_current')>-1) { userStats[u].conns=val; }
                else if (l.indexOf('accumulated_rx')>-1) { userStats[u].acc_rx=val; totalRx+=val; }
                else if (l.indexOf('accumulated_tx')>-1) { userStats[u].acc_tx=val; totalTx+=val; }
            }
        }
        var usersOnline = 0;
        allUserRows.forEach(function(el) {
            var u = el.getAttribute('data-user'); var st = userStats[u];
            var fTx = st.live_tx+st.acc_tx; var fRx = st.live_rx+st.acc_rx; if(st.conns>0) usersOnline++;
            var col = st.conns>0 ? "#00a000" : "#888";
            el.innerHTML = "<div style='display:flex; align-items:center; gap:4px;'><span style='color:#00a000;'>&darr; "+formatMB(fTx)+"</span> <span class='stat-divider'>|</span> <span style='color:#d35400;'>&uarr; "+formatMB(fRx)+"</span> <span class='stat-divider'>|</span> <span style='color:"+col+"; font-weight:"+(st.conns>0?"bold":"normal")+";'>"+st.conns+" conns</span></div>";
        });
        
        var sumEl = document.getElementById('telemt_users_summary_inner');
        if (sumEl) {
            if (txt==="") sumEl.innerHTML = "<span style='color:#d9534f; font-weight:bold;'>Status: Offline</span>";
            else {
                var dpiCol = g.dpiProbes>0 ? "#d9534f" : "#888";
                sumEl.innerHTML = "<b>Uptime:</b> "+formatUptime(g.uptime)+" <span class='sum-divider'>|</span> <b>DL:</b> <span style='color:#00a000;'>"+formatMB(totalTx)+"</span> <span class='sum-divider'>|</span> <b>UL:</b> <span style='color:#d35400;'>"+formatMB(totalRx)+"</span> <span class='sum-divider'>|</span> <span title='DPI/Censorship checks'><b>DPI Probes:</b> <b style='color:"+dpiCol+";'>"+g.dpiProbes+"</b></span> <span class='sum-divider'>|</span> <b>Online:</b> <b style='color:#00a000;'>"+usersOnline+"</b>";
            }
        }
    }).catch(()=>{});
}

function updateLinks() {
    var m1 = document.querySelector('input[name*="cbid.telemt.general.external_ip"]'); var m2 = document.getElementById('telemt_mirror_ip');
    var ip = (m2 && m2.offsetParent !== null) ? m2.value.trim() : (m1 ? m1.value.trim() : "0.0.0.0");
    var port = document.querySelector('input[name*="port"]') ? document.querySelector('input[name*="port"]').value.trim() : "4443";
    var dom = document.querySelector('input[name*="domain"]') ? document.querySelector('input[name*="domain"]').value.trim() : "";
    var mode = document.querySelector('select[name*="mode"]') ? document.querySelector('select[name*="mode"]').value : "tls";
    var hd = ""; if (dom) { for(var n=0; n<dom.length; n++) { var hex = dom.charCodeAt(n).toString(16); hd += (hex.length<2?"0"+hex:hex); } }
    
    document.querySelectorAll('#cbi-telemt-user .cbi-section-table-row:not(.cbi-row-template)').forEach(function(row) {
        var secInp = row.querySelector('input[name*="secret"]'); var linkOut = row.querySelector('.user-link-out');
        if(secInp && linkOut) {
            var val = secInp.value.trim();
            if(/^[0-9a-fA-F]{32}$/.test(val)) { 
                var finalSecret = (mode === 'tls' || mode === 'all') ? "ee" + val + hd : val;
                linkOut.value = "tg://proxy?server=" + ip + "&port=" + port + "&secret=" + finalSecret; 
                linkOut.classList.remove('user-link-err'); 
            } else { linkOut.value = "Error: 32 hex chars required!"; linkOut.classList.add('user-link-err'); }
        }
    });
}

function fixTabs() {
    var upSec = document.getElementById('cbi-telemt-upstream'); var upAnchor = document.getElementById('upstreams_tab_anchor');
    if (upSec && upAnchor) { var tA = upAnchor.closest('.cbi-tab') || upAnchor.parentNode; if(tA && upSec.parentNode !== tA) { upAnchor.style.display = 'none'; tA.appendChild(upSec); } }
    
    var usTable = document.getElementById('cbi-telemt-user'); var usAnchor = document.getElementById('users_tab_anchor');
    if (usTable && usAnchor) { 
        var tU = usAnchor.closest('.cbi-tab') || usAnchor.parentNode; 
        if(tU && usTable.parentNode !== tU) {
            tU.appendChild(usTable);
            if (!document.getElementById('telemt_users_dashboard_panel')) {
                var dash = document.createElement('div'); dash.id = 'telemt_users_dashboard_panel'; dash.className = 'telemt-dash-top-row';
                dash.innerHTML = "<div id='telemt_users_summary_inner' class='telemt-dash-summary'></div>";
                tU.insertBefore(dash, usTable);
            }
        }
    }
}

function injectUI() {
    fixTabs();
    if (!is_owrt25) {
        var th = document.querySelector('#cbi-telemt-user .cbi-section-table-titles th:first-child') || document.querySelector('#cbi-telemt-user thead th:first-child');
        if (th && !th.dataset.renamed) { var t = (th.textContent||'').trim().toLowerCase(); if(t==='name'||t==='название'||t==='') { th.textContent = 'User'; th.dataset.renamed="1"; } }
    }
    
    document.querySelectorAll('#cbi-telemt-user .cbi-section-table-row:not(.cbi-row-template):not([data-injected="1"])').forEach(function(row) {
        var secInp = row.querySelector('input[name*=".secret"]'); if(!secInp) return; row.dataset.injected = "1";
        var match = secInp.name.match(/cbid\.telemt\.([^.]+)\.secret/); var uName = match ? match[1] : '?';

        if (is_owrt25) { var sTd = secInp.closest('td'); if (sTd) { var nDiv = document.createElement('div'); nDiv.className = 'telemt-user-col-text'; nDiv.style.marginBottom = '6px'; nDiv.innerText = '[ user: ' + uName + ' ]'; sTd.insertBefore(nDiv, sTd.firstChild); } } 
        else { var fC = row.firstElementChild; if (fC && !fC.contains(secInp)) { fC.innerHTML = "<span class='telemt-user-col-text'>" + uName + "</span>"; } }
        
        var w = document.createElement('div'); w.className = 'telemt-sec-wrap'; secInp.parentNode.insertBefore(w, secInp); w.appendChild(secInp);
        var grp = document.createElement('div'); grp.className = 'telemt-sec-btns';
        var bG = document.createElement('input'); bG.type = 'button'; bG.className = 'cbi-button cbi-button-apply'; bG.value = 'Gen'; bG.onclick = function(){ var arr=new Uint8Array(16); crypto.getRandomValues(arr); var h=""; for(var i=0;i<16;i++){var hex=arr[i].toString(16); h+=(hex.length<2?"0"+hex:hex);} secInp.value=h; updateLinks(); };
        grp.appendChild(bG); w.appendChild(grp);
        
        var linkWrap = row.querySelector('.link-wrapper');
        if(linkWrap) { var bGrp = document.createElement('div'); bGrp.className = 'link-btn-group'; var bC = document.createElement('input'); bC.type = 'button'; bC.className = 'cbi-button cbi-button-action'; bC.value = 'Copy'; bC.onclick = function(){ var inp = linkWrap.querySelector('.user-link-out'); if(inp){ navigator.clipboard.writeText(inp.value); bC.value='✔'; setTimeout(()=>bC.value='Copy',1500); } }; bGrp.appendChild(bC); linkWrap.appendChild(bGrp); }
    });

    // Inject purely for Upstreams table (OpenWrt 25 Name protection)
    document.querySelectorAll('#cbi-telemt-upstream .cbi-section-table-row:not(.cbi-row-template):not([data-injected="1"])').forEach(function(row) {
        var enInp = row.querySelector('input[name*=".enabled"]'); if(!enInp) return; row.dataset.injected = "1";
        var match = enInp.name.match(/cbid\.telemt\.([^.]+)\.enabled/); var uName = match ? match[1] : '?';
        if (is_owrt25) { var sTd = enInp.closest('td'); if (sTd) { var nDiv = document.createElement('div'); nDiv.className = 'telemt-user-col-text'; nDiv.style.marginBottom = '6px'; nDiv.innerText = '[ alias: ' + uName + ' ]'; sTd.insertBefore(nDiv, sTd.firstChild); } } 
        else { var fC = row.firstElementChild; if (fC && !fC.contains(enInp)) { fC.innerHTML = "<span class='telemt-user-col-text'>" + uName + "</span>"; } }
    });
}

function loadLog() {
    var btn = document.getElementById('btn_load_log'); if(!btn) return; btn.value = 'Loading...';
    fetch(lu_current_url.split('#')[0] + (lu_current_url.indexOf('?') > -1 ? '&' : '?') + 'get_log=1&_t=' + Date.now()).then(r => r.text()).then(txt => { document.getElementById('telemt_log_container').textContent = txt || 'No logs found.'; btn.value = 'Refresh Log'; });
}

setInterval(fetchMetrics, 2500);
document.addEventListener('input', updateLinks);
document.addEventListener('DOMContentLoaded', function(){ injectUI(); updateLinks(); setInterval(injectUI, 1000); });
</script>
]]

return m
