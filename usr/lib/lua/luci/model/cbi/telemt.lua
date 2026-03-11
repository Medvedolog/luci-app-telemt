-- ==============================================================================
-- Telemt CBI Model (Configuration Binding Interface)
-- Version: 3.3.15 (Strict UCI-only, No direct CORS, Unified Extended Runtime)
-- ==============================================================================

local sys = require "luci.sys"
local dsp = require "luci.dispatcher"

-- Helper to safely build current LuCI URL for AJAX calls to our Controller
local _ok_url, current_url = pcall(function() 
    if dsp.context and dsp.context.request then 
        return dsp.build_url("admin", "services", "telemt") 
    end 
    return "" 
end)

-- ==============================================================================
-- 1. Graceful Degradation & System Checks
-- ==============================================================================
local bin_path = sys.exec("command -v telemt 2>/dev/null"):gsub("%s+", "")
if bin_path == "" then
    -- Lock down UI if binary is missing. No 500 errors.
    local m_err = Map("telemt", "Telegram Proxy (MTProto)", 
        "<div style='padding: 15px; background: rgba(217, 83, 79, 0.1); border-left: 5px solid #d9534f;'>" ..
        "<h3 style='color:#d9534f; margin-top:0;'>Fatal Error: telemt binary not found!</h3>" ..
        "<p>Please install the <b>telemt-wrt</b> package to continue using this interface.</p></div>")
    return m_err
end

-- OpenWrt 25+ Client-side rendering detection (for UI injections)
local is_owrt25_lua = "false"
local ow_rel = sys.exec("cat /etc/openwrt_release 2>/dev/null") or ""
if ow_rel:match("DISTRIB_RELEASE='25") or ow_rel:match('DISTRIB_RELEASE="25') or ow_rel:match("SNAPSHOT") then
    is_owrt25_lua = "true"
end

-- 0% CPU version check using tail and grep (avoiding full binary execution)
local bin_ver = sys.exec("tail -c 128 /usr/bin/telemt 2>/dev/null | grep -aoE 'MTProxy v[0-9.]+' | head -n 1"):gsub("%s+", "")
if bin_ver == "" then bin_ver = "unknown" end

local function tip(txt) 
    return string.format([[<span class="telemt-tip" title="%s">(?)</span>]], txt:gsub('"', '&quot;')) 
end

-- ==============================================================================
-- 2. CBI Map Definition
-- ==============================================================================
m = Map("telemt", "Telegram Proxy (MTProto)", 
    [[Multi-user MTProxy server based on <a href="https://github.com/telemt/telemt" target="_blank" style="text-decoration:none; color:inherit; font-weight:bold; border-bottom: 1px dotted currentColor;">telemt</a>.<br>]] ..
    [[<b>Binary Version: <span style='color:#00a000;'>]] .. bin_ver .. [[</span></b> | ]] ..
    [[<span style='color:#d35400; font-weight:bold;'>Strict UCI Mode</span>]])

m.on_commit = function(self)
    -- Triggered when "Save & Apply" is clicked. init.d will handle TOML generation.
    sys.call("logger -t telemt 'WebUI: Config saved. Reloading...'")
end

-- ==============================================================================
-- 3. Validation Helpers (Port collisions)
-- ==============================================================================
local function validate_port_unique(self, value, section)
    if not value then return nil end
    local p = tonumber(value)
    local proxy_port = tonumber(m.uci:get("telemt", "general", "port")) or 8443
    local api_port = tonumber(m.uci:get("telemt", "general", "api_port")) or 9091
    local metrics_port = tonumber(m.uci:get("telemt", "general", "metrics_port")) or 9092
    
    -- Dynamically check against the other two based on which field we are validating
    if self.option == "port" and (p == api_port or p == metrics_port) then
        return nil, "Proxy port collides with API or Metrics port!"
    elseif self.option == "api_port" and (p == proxy_port or p == metrics_port) then
        return nil, "API port collides with Proxy or Metrics port!"
    elseif self.option == "metrics_port" and (p == proxy_port or p == api_port) then
        return nil, "Metrics port collides with Proxy or API port!"
    end
    return value
end

s = m:section(NamedSection, "general", "telemt")
s.anonymous = true

-- Tabs Definition
s:tab("general", "General Settings")
s:tab("upstreams", "Cascades (Upstreams)")
s:tab("users", "Users")
s:tab("advanced", "Advanced & ME")
s:tab("bot", "Telegram Bot")
s:tab("log", "Diagnostics")

-- ==============================================================================
-- TAB: GENERAL
-- ==============================================================================
s:taboption("general", Flag, "enabled", "Enable Service")

local st = s:taboption("general", DummyValue, "_status", "Process Status")
st.rawhtml = true
local is_running = (sys.call("pidof telemt >/dev/null 2>&1") == 0)
st.value = is_running and "<span style='color:green;font-weight:bold'>RUNNING</span>" or "<span style='color:#d9534f; font-weight:bold;'>STOPPED</span>"

local ext_rt = s:taboption("general", Flag, "extended_runtime_enabled", "Enable Extended Runtime Dashboard" .. tip("Unified switch: Enables Control API and Minimal Runtime for rich diagnostics in UI."))
ext_rt.default = "1"

local p = s:taboption("general", Value, "port", "MTProxy Port")
p.datatype = "port"; p.rmempty = false; p.default = "8443"
p.validate = validate_port_unique

local mode = s:taboption("general", ListValue, "mode", "Protocol Mode" .. tip("FakeTLS: HTTPS masking. DD: Random Padding."))
mode:value("tls", "FakeTLS (Recommended)")
mode:value("dd", "Secure (DD)")
mode.default = "tls"

local dom = s:taboption("general", Value, "domain", "FakeTLS Domain" .. tip("Unauthenticated DPI traffic will be routed here."))
dom.datatype = "hostname"; dom.default = "google.com"
dom:depends("mode", "tls")

local afw = s:taboption("general", Flag, "auto_fw", "Auto-open Port (Magic)" .. tip("Uses procd API to open port in RAM. Closes automatically if proxy stops."))
afw.default = "0"
afw.description = "<div style='margin-top:5px; padding:8px; background:rgba(128,128,128,0.1); border-left:3px solid #00a000; font-size:0.9em;'><b>Current Firewall Status:</b> <span id='fw_status_span' style='color:#888; font-style:italic;'>Checking...</span></div>"

-- ==============================================================================
-- TAB: USERS
-- ==============================================================================
-- The Micro-dashboard will be injected via JS at the top of this tab
local dash_anchor = s:taboption("users", DummyValue, "_dash_anchor", "")
dash_anchor.rawhtml = true
dash_anchor.default = '<div id="telemt_dashboard_container"></div>'

s2 = m:section(TypedSection, "user", "")
s2.template = "cbi/tblsection"
s2.addremove = true
s2.anonymous = false

-- Logging changes to UCI
s2.create = function(self, section)
    if not section or not section:match("^[A-Za-z0-9_]+$") or #section > 15 then return nil end
    sys.call(string.format("logger -t telemt 'WebUI: Added new user -> %s'", section))
    return TypedSection.create(self, section)
end
s2.remove = function(self, section)
    sys.call(string.format("logger -t telemt 'WebUI: Deleted user -> %s'", section))
    return TypedSection.remove(self, section)
end

local sec = s2:option(Value, "secret", "Secret (32 hex)" .. tip("Must be exactly 32 hex chars."))
sec.rmempty = false; sec.datatype = "hexstring"
function sec.validate(self, value)
    if not value or #value ~= 32 or not value:match("^[0-9a-fA-F]+$") then return nil, "Secret must be exactly 32 hex chars!" end
    return value
end

s2:option(Value, "max_tcp_conns", "TCP Conns" .. tip("Limit sessions")).datatype = "uinteger"
s2:option(Value, "max_unique_ips", "Max IPs" .. tip("Max unique client IPs")).datatype = "uinteger"
s2:option(Value, "data_quota", "Quota (GB)").datatype = "ufloat"
local t_exp = s2:option(Value, "expire_date", "Expire Date" .. tip("Format: DD.MM.YYYY HH:MM"))
function t_exp.validate(self, value)
    if not value or value == "" then return "" end
    if not value:match("^%d%d%.%d%d%.%d%d%d%d %d%d:%d%d$") then return nil, "Format: DD.MM.YYYY HH:MM" end
    return value
end

-- Dummy value to hold Prometheus stats injected by JS
local lst = s2:option(DummyValue, "_stat", "Live Stats" .. tip("Accumulated usage & sessions via Prometheus"))
lst.rawhtml = true
function lst.cfgvalue(self, section) 
    return string.format('<div class="user-flat-stat" data-user="%s"><span style="color:#888;">Waiting for metrics...</span></div>', section) 
end

-- ==============================================================================
-- TAB: UPSTREAMS (Cascades)
-- ==============================================================================
s_up = m:section(TypedSection, "upstream", "Upstream Proxies (Cascades)", 
    "<span style='color:#555;'>Chain outgoing Telegram traffic. If none are enabled, falls back to Direct. Detailed health requires Extended Runtime.</span>")
s_up.addremove = true
s_up.anonymous = true

local ut = s_up:option(ListValue, "type", "Protocol")
ut:value("direct", "Direct")
ut:value("socks4", "SOCKS4")
ut:value("socks5", "SOCKS5")
ut.default = "socks5"

s_up:option(Flag, "enabled", "Active").default = "1"

local ua = s_up:option(Value, "address", "Address" .. tip("IP:PORT or HOST:PORT"))
ua:depends("type", "socks4"); ua:depends("type", "socks5")

-- Interface is only relevant for Direct
local uint = s_up:option(Value, "interface", "Interface / Bind IP" .. tip("Optional bind interface for direct connections"))
uint:depends("type", "direct")

local uw = s_up:option(Value, "weight", "Weight" .. tip("Routing priority (default 10)")); uw.default = "10"

-- ==============================================================================
-- TAB: ADVANCED & ME (Strictly protected by Dependencies)
-- ==============================================================================
local hnet = s:taboption("advanced", DummyValue, "_head_net")
hnet.rawhtml = true; hnet.default = "<h3>Control-Plane Access & Metrics</h3>"

local mport = s:taboption("advanced", Value, "metrics_port", "Metrics Port")
mport.datatype = "port"; mport.default = "9092"; mport.validate = validate_port_unique

local aport = s:taboption("advanced", Value, "api_port", "Control API Port")
aport.datatype = "port"; aport.default = "9091"; aport.validate = validate_port_unique

s:taboption("advanced", Flag, "metrics_allow_lo", "Allow Localhost").default = "1"
s:taboption("advanced", Flag, "metrics_allow_lan", "Allow LAN Access (Control-Plane)" .. tip("Auto-allow router LAN subnet in control-plane whitelist.")).default = "1"
local mwl = s:taboption("advanced", Value, "metrics_whitelist", "Additional Whitelist" .. tip("Comma separated CIDRs (e.g. 10.8.0.0/24)"))

local hme = s:taboption("advanced", DummyValue, "_head_me")
hme.rawhtml = true; hme.default = "<h3 style='margin-top:20px;'>Middle-End Proxy (ME)</h3>"

local mp = s:taboption("advanced", Flag, "use_middle_proxy", "Enable Middle-End Proxy" .. tip("Master toggle for ME. Allows Media/CDN to work correctly."))
mp.default = "0"

s:taboption("advanced", Flag, "use_stun", "Enable STUN-probing" .. tip("Required if server is behind NAT.")):depends("use_middle_proxy", "1")

-- SPOILER: Deep ME Tuning
local h_adv = s:taboption("advanced", DummyValue, "_head_adv")
h_adv.rawhtml = true
h_adv.default = [[
<details id="me_tuning_spoiler" style="margin-top:15px; padding:10px; background:rgba(128,128,128,0.05); border:1px solid rgba(128,128,128,0.3); border-radius:6px; cursor:pointer;">
    <summary style="font-weight:bold; font-size:1.05em; outline:none;">Deep ME Tuning (Click to expand)</summary>
    <p style="font-size:0.85em; opacity:0.8; margin-top:5px;">Advanced parameters. Edit only if you understand the runtime model.</p>
</details>
<script>
setTimeout(function(){
    var details = document.getElementById('me_tuning_spoiler');
    if(!details) return;
    var toMove = ['me_floor_mode', 'me_pool_size', 'me_drain_ttl', 'hardswap'];
    toMove.forEach(function(name){
        var el = document.querySelector('.cbi-value[data-name="' + name + '"]') || document.getElementById('cbi-telemt-general-' + name);
        if(el) { el.style.paddingLeft = '15px'; details.appendChild(el); }
    });
}, 300);
</script>
]]

local fmode = s:taboption("advanced", ListValue, "me_floor_mode", "ME Floor Mode")
fmode:value("static", "Static"); fmode:value("adaptive", "Adaptive"); fmode.default = "static"
fmode:depends("use_middle_proxy", "1")

s:taboption("advanced", Value, "me_pool_size", "ME Pool Size" .. tip("Desired number of concurrent ME writers.")):depends("use_middle_proxy", "1")
s:taboption("advanced", Value, "me_drain_ttl", "ME Drain TTL (sec)" .. tip("Time stale writers are kept alive.")):depends("use_middle_proxy", "1")
s:taboption("advanced", Flag, "hardswap", "Enable Hardswap" .. tip("Strict generation-based pool swaps.")):depends("use_middle_proxy", "1")

-- ==============================================================================
-- TAB: DIAGNOSTICS & BOT
-- ==============================================================================
s:taboption("bot", Flag, "bot_enabled", "Enable Autonomous Bot Sidecar").default = "0"
s:taboption("bot", Value, "bot_token", "Bot Token"):depends("bot_enabled", "1")

local diag = s:taboption("log", DummyValue, "_diag")
diag.rawhtml = true
diag.default = [[
<div style="display:flex; gap:10px; margin-bottom: 15px;">
    <input type="button" class="cbi-button cbi-button-apply" id="btn_diag_log" value="View System Log">
    <input type="button" class="cbi-button cbi-button-action" id="btn_diag_scanners" value="View Active Scanners">
    <input type="button" class="cbi-button cbi-button-remove" id="btn_diag_clear" value="Clear View (DOM Only)">
</div>
<div id="diag_console" style="height:400px; padding:10px; background:#1e1e1e; color:#d4d4d4; font-family:monospace; overflow-y:auto; border-radius:4px;">
    Ready. Click a button to fetch data via LuCI Controller.
</div>
]]

-- ==============================================================================
-- 4. JS Engine (Secure Controller Polling & DOM Manipulation)
-- ==============================================================================
m.description = [[
<style>
/* Clean minimalist CSS preserved from 3.2.1 */
.cbi-value-helpicon, .cbi-tooltip-container, .cbi-tooltip { display: none !important; }
.telemt-tip { cursor: help; opacity: 0.6; font-size: 0.85em; border-bottom: 1px dotted currentColor; margin-left: 5px; }
.user-flat-stat { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; font-size: 0.95em; }
.telemt-dash-warn { padding: 10px; background: rgba(217, 83, 79, 0.1); border-left: 4px solid #d9534f; margin-bottom: 15px; font-weight: bold; }
</style>

<script>
var ctrl_url = "]] .. current_url .. [[";
var is_owrt25 = ]] .. is_owrt25_lua .. [[;

function fetchController(action, callback) {
    var separator = ctrl_url.indexOf('?') > -1 ? '&' : '?';
    fetch(ctrl_url + separator + action + '=1&_t=' + Date.now())
        .then(res => res.text())
        .then(txt => { if(callback) callback(txt.trim()); })
        .catch(err => console.error("[Telemt UI] Fetch error:", err));
}

// 1. Diagnostics Logic
setTimeout(function() {
    var con = document.getElementById('diag_console');
    document.getElementById('btn_diag_log')?.addEventListener('click', function() {
        con.innerHTML = 'Fetching logs...';
        fetchController('log', txt => con.textContent = txt || 'No telemt log entries found.');
    });
    document.getElementById('btn_diag_scanners')?.addEventListener('click', function() {
        con.innerHTML = 'Fetching scanners...';
        fetchController('scanners', txt => con.textContent = "=== ACTIVE DPI SCANNERS ===\n\n" + (txt || 'No data.'));
    });
    document.getElementById('btn_diag_clear')?.addEventListener('click', function() {
        con.textContent = 'View cleared.'; // Only clears DOM, not system buffer!
    });
}, 500);

// 2. Firewall Status Polling
function updateFW() {
    fetchController('fw_status', function(txt) {
        var el = document.getElementById('fw_status_span');
        if(el && txt) el.innerHTML = txt;
    });
}

// 3. Prometheus Parsing (Offloaded to client JS)
function updateMetrics() {
    fetchController('metrics', function(txt) {
        if (!txt) return; // Daemon stopped or starting
        
        var userStats = {}; 
        var lines = txt.split('\n');
        
        // Parse Prometheus Text Format natively in JS
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line.indexOf('#') === 0 || line === "") continue;
            
            var userMatch = line.match(/user="([^"]+)"/);
            if (userMatch) {
                var u = userMatch[1];
                if (!userStats[u]) userStats[u] = { rx: 0, tx: 0, conns: 0 };
                
                var valMatch = line.match(/\}\s+([0-9\.eE\+\-]+)/);
                if (valMatch) {
                    var val = parseFloat(valMatch[1]);
                    if (line.indexOf('telemt_user_octets_from_client') > -1 || line.indexOf('telemt_accumulated_rx') > -1) { userStats[u].rx += val; }
                    else if (line.indexOf('telemt_user_octets_to_client') > -1 || line.indexOf('telemt_accumulated_tx') > -1) { userStats[u].tx += val; }
                    else if (line.indexOf('telemt_user_connections_current') > -1) { userStats[u].conns = val; }
                }
            }
        }
        
        // Update DOM Elements
        document.querySelectorAll('.user-flat-stat').forEach(function(el) {
            var u = el.getAttribute('data-user');
            var stat = userStats[u];
            if (stat) {
                var rxMB = (stat.rx / 1048576).toFixed(2);
                var txMB = (stat.tx / 1048576).toFixed(2);
                var c_col = stat.conns > 0 ? "#00a000" : "#888";
                el.innerHTML = "<span style='color:#00a000;'>&darr; " + txMB + " MB</span> | " +
                               "<span style='color:#d35400;'>&uarr; " + rxMB + " MB</span> | " +
                               "<b style='color:" + c_col + ";'>" + stat.conns + " conns</b>";
            } else {
                el.innerHTML = "<span style='color:#888;'>No active data</span>";
            }
        });
    });
}

// 4. OpenWrt 25+ UI Injection (Blue usernames above secrets)
function injectUI() {
    if (!is_owrt25) return;
    var secrets = document.querySelectorAll('input[type="password"], input[type="text"]');
    for (var i = 0; i < secrets.length; i++) {
        var el = secrets[i];
        var idMatch = el.id && el.id.match(/cbid\.telemt\.([^.]+)\.secret/);
        
        if (idMatch && idMatch[1]) {
            var username = idMatch[1];
            if (!el.parentNode.querySelector('.telemt-ow25-name')) {
                var nameDiv = document.createElement('div');
                nameDiv.className = 'telemt-ow25-name';
                nameDiv.style.cssText = 'color:#0069d6; font-weight:bold; margin-bottom: 5px; font-size: 1.1em;';
                nameDiv.innerText = '👤 User: ' + username;
                el.parentNode.insertBefore(nameDiv, el);
            }
        }
    }
}

// Start local polling timers and UI observers
if (!document.hidden) {
    setInterval(updateMetrics, 3000);
    setInterval(updateFW, 10000);
    setTimeout(updateFW, 1000);
    setTimeout(updateMetrics, 1000);
}

// Run injection immediately and observe DOM for OpenWrt 25 CSR
setTimeout(injectUI, 500);
if (typeof window.MutationObserver !== 'undefined') {
    var observer = new MutationObserver(injectUI);
    observer.observe(document.body, { childList: true, subtree: true });
}
</script>
]]

return m
