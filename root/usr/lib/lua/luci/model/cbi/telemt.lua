local sys = require "luci.sys"
local http = require "luci.http"
local dsp = require "luci.dispatcher"
local utl = require "luci.util"
local xml = require "luci.xml"

if http.formvalue("get_wan_ip") == "1" then
    http.prepare_content("text/plain")
    local ip = sys.exec([[wget -qO- -T 2 https://ipv4.internet.yandex.net/api/v0/ip 2>/dev/null | sed 's/"//g']]) or ""
    ip = ip:gsub("%s+", "")
    if not ip:match("^%d+%.%d+%.%d+%.%d+$") then
        ip = sys.exec([[wget -qO- -T 2 https://checkip.amazonaws.com 2>/dev/null]]) or ""
        ip = ip:gsub("%s+", "")
    end
    if not ip:match("^%d+%.%d+%.%d+%.%d+$") then ip = "0.0.0.0" end
    http.write(ip)
    return
end

local function tip(txt)
    return string.format([[ <span title="%s" style="cursor:help; color:#888; font-size:0.9em; border-bottom:1px dotted #888; margin-left:4px;">(?)</span>]], txt:gsub('"', '&quot;'))
end

local current_url = dsp.build_url(unpack(dsp.context.request))

if http.formvalue("start") == "1" then 
    sys.call("/etc/init.d/telemt start")
    http.redirect(current_url)
    return 
end
if http.formvalue("stop") == "1" then 
    sys.call("/etc/init.d/telemt stop; killall -9 telemt 2>/dev/null")
    http.redirect(current_url)
    return 
end
if http.formvalue("restart") == "1" then 
    sys.call("/etc/init.d/telemt stop; killall -9 telemt 2>/dev/null; sleep 1; /etc/init.d/telemt start")
    http.redirect(current_url)
    return 
end

local pid = sys.exec("pidof telemt | awk '{print $1}'"):gsub("%s+", "")
local process_status = "<span style='color:#d9534f; font-weight:bold;'>STOPPED</span>"
if pid ~= "" and sys.call("kill -0 " .. pid .. " 2>/dev/null") == 0 then
    process_status = string.format("<span style='color:green;font-weight:bold'>RUNNING (PID: %s)</span><br><small style='color:#666'>/usr/bin/telemt</small>", pid)
else
    pid = nil
end

local css_style = [[<style>
.cbi-value-helpicon, img[src*="help.gif"], img[src*="help.png"] { display: none !important; }

.cbi-value-description, .cbi-value-description .cbi-tooltip-container, .cbi-value-description .cbi-tooltip {
    display: block !important; position: static !important; visibility: visible !important; opacity: 1 !important;
    background: transparent !important; color: var(--text-color, #555) !important; box-shadow: none !important;
    transform: none !important; padding: 0 !important; margin: 4px 0 0 0 !important; width: auto !important;
    max-width: 100% !important; white-space: normal !important; text-align: left !important;
    font-size: 0.85em !important; line-height: 1.3 !important;
}

.alert-txt { color: #d9534f; font-weight: bold; }
.warn-txt { color: #d35400; font-weight: bold; }
.hint-gray { color: #888; font-size: 0.85em; font-weight: normal; }

.btn-controls input { width: auto; margin-right: 5px; }

#cbi-telemt-user { border-top: none; }
#cbi-telemt-user .cbi-section-table-cell { vertical-align: top; padding-top: 8px !important; text-align: left; }
#cbi-telemt-user .cbi-section-table-titles th { text-align: left; vertical-align: bottom; }
#cbi-telemt-user .cbi-section-table-cell:first-child { max-width: 140px; word-break: break-all; }
#cbi-telemt-user input[type="text"] { height: 32px !important; box-sizing: border-box; }

.user-btn-group { display: flex; gap: 4px; margin-top: 2px; }
.user-btn-group input.cbi-button, .btn-copy-custom {
    height: 18px !important; line-height: 16px !important; font-size: 10px !important; padding: 0 6px !important; margin-top: 0 !important;
}

.user-link-out { 
    width: 100%; font-family: monospace; font-size: 11px; background: transparent !important; color: inherit !important;
    border: 1px solid var(--border-color, #ccc) !important; box-sizing: border-box; margin: 0; cursor: pointer; 
}
.user-link-err { color: #d9534f !important; font-weight: bold; border-color: #d9534f !important; }

#cbi-telemt-general-_lv { display: block !important; padding: 0 !important; border: none !important; margin-top: 15px !important; }
#cbi-telemt-general-_lv .cbi-value-title { display: none !important; }
#cbi-telemt-general-_lv .cbi-value-field { width: 100% !important; max-width: 100% !important; padding: 0 !important; margin: 0 !important; float: none !important; }

@media screen and (max-width: 768px) {
    .user-btn-group { width: 100%; gap: 5px; margin-top: 5px; }
    .user-btn-group input { flex: 1; height: 26px !important; font-size: 12px !important; }
    .btn-copy-custom { width: 100%; align-self: stretch; height: 26px !important; }
}
</style>]]

local js_logic = [[<script type="text/javascript">
function genRandHex(){
    var h=""; var c="0123456789abcdef";
    for(var i=0;i<32;i++) h+=c.charAt(Math.floor(Math.random()*16));
    return h;
}

function updateLinks(){
    var d = document.querySelector('input[name*="domain"]');
    var p = document.querySelector('input[name*="port"]');
    var ipInputs = document.querySelectorAll('input[name*="_myip"]');
    var modeSelect = document.querySelector('select[name*="mode"]');
    var fmtSelect = document.querySelector('select[name*="_link_fmt"]');
    
    var ip = ipInputs.length > 0 ? ipInputs[0].value.trim() : "0.0.0.0";
    var port = p ? p.value.trim() : "4443";
    var domain = d ? d.value.trim() : "";
    var mode = modeSelect ? modeSelect.value : "tls";
    
    var effectiveFmt = mode;
    if (mode === 'all' && fmtSelect) { effectiveFmt = fmtSelect.value; }
    
    if(!ip || !port) return;
    
    var hd=""; 
    if(domain && (effectiveFmt === 'tls' || effectiveFmt === 'all')) { 
        for(var n=0;n<domain.length;n++) hd+=domain.charCodeAt(n).toString(16); 
    }
    
    document.querySelectorAll('.cbi-section-table-row').forEach(function(row){
        var secInp = row.querySelector('input[name*="secret"]');
        var linkOut = row.querySelector('.user-link-out');
        if(secInp && linkOut) {
            var val = secInp.value.trim();
            if(/^[0-9a-fA-F]{32}$/.test(val)) {
                var finalSecret = val;
                
                if (effectiveFmt === 'tls' || effectiveFmt === 'all') { 
                    finalSecret = "ee" + val + hd; 
                } else if (effectiveFmt === 'dd') { 
                    finalSecret = "dd" + val; 
                }
                
                linkOut.value = "tg://proxy?server="+ip+"&port="+port+"&secret="+finalSecret;
                linkOut.classList.remove('user-link-err');
            } else {
                linkOut.value = "Error: 32 hex chars required!";
                linkOut.classList.add('user-link-err');
            }
        }
    });
    
    var mIp = document.getElementById('mirrored_ip');
    if(mIp) mIp.innerText = ip;
}

function copyProxyLink(btn) {
    var input = btn.parentNode.querySelector('.user-link-out');
    if (input && !input.classList.contains('user-link-err')) {
        input.select();
        try { if(document.execCommand('copy')) { var oldVal = btn.value; btn.value = '✔'; setTimeout(function(){ btn.value = oldVal; }, 1500); } } catch(e) {}
    }
}

function fetchIPViaWget(btn) {
    var oldVal = btn.value; btn.value = '...';
    var fetchUrl = location.href.split('#')[0];
    fetchUrl += (fetchUrl.indexOf('?') > -1 ? '&' : '?') + 'get_wan_ip=1&_t=' + new Date().getTime();
    
    fetch(fetchUrl)
        .then(function(res) { return res.text(); })
        .then(function(txt) {
            var match = txt.match(/\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b/);
            if (match) {
                document.querySelectorAll('input[name*="_myip"]').forEach(function(inp) { inp.value = match[0]; });
                updateLinks();
            }
            btn.value = oldVal;
        }).catch(function() { btn.value = oldVal; });
}

function fixTabIsolation() {
    var warnElem = document.getElementById('cbi-telemt-general-_user_warn');
    var userTable = document.getElementById('cbi-telemt-user');
    if (warnElem && userTable) {
        var targetContainer = warnElem.closest('.cbi-tabcontainer');
        if (!targetContainer) targetContainer = warnElem.parentNode;
        if (userTable.parentNode !== targetContainer) targetContainer.appendChild(userTable);
    }
}

function injectUI() {
    fixTabIsolation();
    var btnAdd = document.querySelector('.cbi-button-add');
    if (btnAdd && btnAdd.value !== 'Add user') btnAdd.value = 'Add user';

    var newNameInp = document.querySelector('.cbi-section-create-name');
    if(newNameInp && !newNameInp.dataset.maxInjected) {
        newNameInp.dataset.maxInjected = "1"; newNameInp.maxLength = 15; newNameInp.placeholder = "a-z, 0-9, -, _";
    }

    document.querySelectorAll('input[name*="_myip"]').forEach(function(ipFld) {
        if(!ipFld.dataset.refBtnInjected && ipFld.type !== "hidden") {
            ipFld.dataset.refBtnInjected = "1";
            ipFld.parentNode.style.display = 'flex'; ipFld.parentNode.style.alignItems = 'center'; ipFld.style.flex = '0 1 250px';
            var btn = document.createElement('input');
            btn.type = 'button'; btn.className = 'cbi-button cbi-button-neural'; btn.value = '↻'; btn.title = 'Check IP via wget'; 
            btn.style.marginLeft = '5px'; btn.style.padding = '0 10px'; btn.style.height = ipFld.offsetHeight > 0 ? ipFld.offsetHeight + 'px' : '32px';
            btn.onclick = function() { fetchIPViaWget(this); };
            ipFld.parentNode.appendChild(btn);
        }
    });

    document.querySelectorAll('.cbi-section-table-row').forEach(function(row){
        var secInp = row.querySelector('input[name*="secret"]');
        if(secInp && !secInp.dataset.btnInjected) {
            secInp.dataset.btnInjected = "1"; secInp.dataset.prevVal = secInp.value;
            var grp = document.createElement('div'); grp.className = 'user-btn-group';
            var bG = document.createElement('input'); bG.type = 'button'; bG.className = 'cbi-button cbi-button-apply'; bG.value = 'Generate';
            bG.onclick = function() { secInp.value = genRandHex(); updateLinks(); };
            var bR = document.createElement('input'); bR.type = 'button'; bR.className = 'cbi-button cbi-button-reset'; bR.value = 'Revert';
            bR.onclick = function() { secInp.value = secInp.dataset.prevVal; updateLinks(); };
            grp.appendChild(bG); grp.appendChild(bR); secInp.parentNode.insertBefore(grp, secInp.nextSibling);
        }

        row.querySelectorAll('input[name*="max_tcp_conns"], input[name*="data_quota"]').forEach(function(ni){
            if(!ni.dataset.defInjected) {
                ni.dataset.defInjected = "1"; ni.style.width = '80px'; ni.style.minWidth = '80px';
                var grp = document.createElement('div'); grp.className = 'user-btn-group';
                var bD = document.createElement('input'); bD.type = 'button'; bD.className = 'cbi-button cbi-button-neural'; bD.value = 'Default';
                bD.onclick = function() { ni.value = ''; ni.dispatchEvent(new Event('change', {bubbles:true})); };
                grp.appendChild(bD); ni.parentNode.appendChild(grp);
            }
        });

        var linkWrap = row.querySelector('.link-wrapper');
        if(linkWrap && !linkWrap.dataset.copyInjected) {
            linkWrap.dataset.copyInjected = "1";
            var bC = document.createElement('input'); bC.type = 'button'; bC.className = 'cbi-button cbi-button-action btn-copy-custom'; 
            bC.value = 'Copy'; bC.onclick = function() { copyProxyLink(this); };
            linkWrap.appendChild(bC);
        }
    });
}

function initTelemt() {
    injectUI(); updateLinks(); setInterval(function(){ injectUI(); updateLinks(); }, 1000);
    document.querySelectorAll('input, select').forEach(function(i){
        i.addEventListener('keyup', updateLinks); i.addEventListener('change', updateLinks);
    });
}

if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', initTelemt); } else { initTelemt(); }
</script>]]

m = Map("telemt", "Telegram Proxy (MTProto)", css_style .. js_logic .. "Multi-user proxy server based on <a href='https://github.com/telemt/telemt' target='_blank'>telemt</a>.<br><b>Warning: Requires binary version 3.0.0 or higher.</b>")

s = m:section(NamedSection, "general", "telemt")
s:tab("general", "General Settings")
s:tab("advanced", "ME Proxy & Advanced")
s:tab("users", "Users")
s:tab("log", "Diagnostics")
s.anonymous = true

local function check_fw(port) 
    if not port then return "---" end 
    local cmd = (sys.call("which nft >/dev/null 2>&1") == 0) and "nft list ruleset | grep -q 'port " .. port .. "'" or "iptables -L INPUT -n | grep -q 'dpt:" .. port .. "'" 
    return (sys.call(cmd) == 0) and "<span style='color:green; font-weight:bold'>OPEN (OK)</span>" or "<span style='color:red; font-weight:bold'>CLOSED (Check Firewall)</span>" 
end

s:taboption("general", Flag, "enabled", "Enable Service")
local ctrl = s:taboption("general", DummyValue, "_controls", "Controls")
ctrl.rawhtml = true
ctrl.default = string.format([[<div class="btn-controls"><input type="button" class="cbi-button cbi-button-apply" value="Start" onclick="location.href='%s?start=1'" /><input type="button" class="cbi-button cbi-button-reset" value="Stop" onclick="location.href='%s?stop=1'" /><input type="button" class="cbi-button cbi-button-reload" value="Restart" onclick="location.href='%s?restart=1'" /></div>]], current_url, current_url, current_url)

local st = s:taboption("general", DummyValue, "_status", "Process Status")
st.rawhtml = true; st.value = process_status

local mode = s:taboption("general", ListValue, "mode", "Protocol Mode" .. tip("FakeTLS: HTTPS masking. DD: Old obfuscation. Classic: MTProto without masking."))
mode:value("tls", "FakeTLS (Recommended)")
mode:value("dd", "DD (Random Padding)")
mode:value("classic", "Classic")
mode:value("all", "All together (Debug)")
mode.default = "tls"

local lfmt = s:taboption("general", ListValue, "_link_fmt", "Link Format to Display" .. tip("Select which protocol link to show in the Users tab for copying."))
lfmt:depends("mode", "all")
lfmt:value("tls", "FakeTLS (Recommended)")
lfmt:value("dd", "Secure (DD)")
lfmt:value("classic", "Classic")
lfmt.default = "tls"

local dom = s:taboption("general", Value, "domain", "FakeTLS Domain" .. tip("Unauthenticated DPI traffic will be routed here."))
dom.default = "google.com"
dom.description = "<span class='warn-txt'>Warning: Change the default domain!</span>"
dom:depends("mode", "tls")
dom:depends("mode", "all")

local saved_ip = m.uci:get("telemt", "general", "_myip") or ""
local myip = s:taboption("general", Value, "_myip", "External IP / DynDNS" .. tip("IP address or domain used for generating tg:// links below."))
myip.datatype = "or(ip4addr, hostname)"; myip.default = saved_ip

local saved_port = m.uci:get("telemt", "general", "port")
local p = s:taboption("general", Value, "port", "Proxy Port")
p.datatype = "port"; p.rmempty = false
p.description = "<span class='warn-txt'>Important: Open this port in Firewall / Traffic Rules!</span>"

local fw = s:taboption("general", DummyValue, "_fw", "Firewall Status")
fw.rawhtml = true; fw.value = check_fw(saved_port)

local hs = s:taboption("general", DummyValue, "_head_s")
hs.rawhtml = true; hs.default = "<h3>SOCKS5 Upstream</h3>"
local us = s:taboption("general", Flag, "use_socks", "Enable SOCKS5" .. tip("Route outgoing Telegram traffic through a SOCKS5 proxy."))

local sa = s:taboption("general", Value, "socks_addr", "Server Address" .. tip("Format: IP:PORT or HOST:PORT"))
sa:depends("use_socks", "1"); sa.datatype = "hostport"

local su = s:taboption("general", Value, "socks_user", "Username" .. tip("Optional. For authenticated SOCKS."))
su:depends("use_socks", "1")

local sp = s:taboption("general", Value, "socks_pass", "Password" .. tip("Optional."))
sp:depends("use_socks", "1"); sp.password = true

-- ==========================================
-- [TAB: ADVANCED]
-- ==========================================
local hme = s:taboption("advanced", DummyValue, "_head_me")
hme.rawhtml = true; hme.default = "<h3>Middle-End Proxy (v3.0+)</h3>"

local mp = s:taboption("advanced", Flag, "use_middle_proxy", "Use ME Proxy" .. tip("Allows Media/CDN (DC=203) to work correctly."))
mp.default = "0"
mp.description = "<span class='warn-txt'>Requires public IP on interface OR NAT 1:1 with STUN enabled.</span>"

local stun = s:taboption("advanced", Flag, "use_stun", "Enable STUN-probing" .. tip("Enable ONLY if your server is behind NAT 1:1."))
stun:depends("use_middle_proxy", "1")

local hadv = s:taboption("advanced", DummyValue, "_head_adv")
hadv.rawhtml = true; hadv.default = "<h3>Additional Options</h3>"

local ip = s:taboption("advanced", Value, "announce_ip", "Announce IP" .. tip("Force this public IP in generated links (optional)."))
ip.datatype = "ip4addr"

local ad = s:taboption("advanced", Value, "ad_tag", "Ad Tag" .. tip("Get your 32-hex promotion tag from @mtproxybot."))
ad.datatype = "hexstring"
function ad.validate(self, value)
    if value and #value > 0 and #value ~= 32 then return nil, "Ad Tag must be exactly 32 hex characters!" end
    return value
end

local p6 = s:taboption("advanced", Flag, "prefer_ipv6", "Listen on IPv6 (::)" .. tip("Enable IPv6 connectivity fallback."))

local htm = s:taboption("advanced", DummyValue, "_head_tm")
htm.rawhtml = true; htm.default = "<h3>Timeouts</h3>"

s:taboption("advanced", Value, "tm_handshake", "Handshake" .. tip("Client handshake timeout in seconds.")).default = "15"
s:taboption("advanced", Value, "tm_connect", "Connect" .. tip("Telegram DC connect timeout in seconds.")).default = "10"
s:taboption("advanced", Value, "tm_keepalive", "Keepalive" .. tip("Client keepalive interval in seconds.")).default = "60"
s:taboption("advanced", Value, "tm_ack", "ACK" .. tip("Client ACK timeout in seconds.")).default = "300"

-- ==========================================
-- [TAB: LOG]
-- ==========================================
local log_raw = sys.exec("logread -e 'telemt' | tail -n 35 2>/dev/null") or ""
local lv = s:taboption("log", DummyValue, "_lv")
lv.rawhtml = true

local log_html = [[<div style="width:100%%; box-sizing:border-box; height:500px; font-family:monospace; ]] ..
                 [[font-size:12px; padding:12px; background: #1e1e1e; ]] ..
                 [[color: #d4d4d4; border: 1px solid #333; border-radius: 4px; ]] ..
                 [[overflow-y:auto; overflow-x:auto; white-space:pre;">%s</div>]] ..
                 [[<input type="button" class="cbi-button cbi-button-neural" style="margin-top:10px;" ]] ..
                 [[value="Refresh Log" onclick="location.reload();" />]]

lv.default = string.format(log_html, xml.pcdata(log_raw:gsub("\27%[[%d;]*m", "")))

-- ==========================================
-- [TAB: USERS]
-- ==========================================
local uh = s:taboption("users", DummyValue, "_user_warn", " ")
uh.rawhtml = true
uh.default = "<div class='alert-txt' style='font-size: 1.1em; margin-bottom: 5px;'>Important: You must create at least one user for the proxy to start!</div>"

local myip_u = s:taboption("users", DummyValue, "_myip_u", "External IP / DynDNS" .. tip("Saved IP address or domain used for generating tg:// links."))
myip_u.rawhtml = true
myip_u.default = string.format([[<div style="padding-top:6px;"><span id="mirrored_ip" style="font-family:monospace; font-weight:bold; font-size:1.1em; color:var(--text-color, #333);">%s</span> <span class="hint-gray" style="display:inline; margin-left:10px;">(Update via General Settings tab)</span></div>]], saved_ip)

s2 = m:section(TypedSection, "user", "")
s2.template = "cbi/tblsection"
s2.addremove = true
s2.anonymous = false

local sec = s2:option(Value, "secret", "Secret (32 hex)" .. tip("Leave empty to auto-generate."))
sec.rmempty = false
sec.datatype = "hexstring"
function sec.validate(self, value)
    if not value or value:gsub("%s+", "") == "" then
        local uuid = sys.exec("cat /proc/sys/kernel/random/uuid") or ""
        value = uuid:gsub("%-", ""):gsub("%s+", ""):sub(1,32)
    end
    if #value ~= 32 or not value:match("^[0-9a-fA-F]+$") then 
        return nil, "Secret must be exactly 32 hex chars!" 
    end
    return value
end

local t_con = s2:option(Value, "max_tcp_conns", "Max TCP Conns" .. tip("Limit sessions (e.g. 50)"))
t_con.datatype = "uinteger"
t_con.placeholder = "unlimited"

local t_qta = s2:option(Value, "data_quota", "Data Quota (GB)" .. tip("E.g. 1.5 or 0.5"))
t_qta.datatype = "ufloat"
t_qta.placeholder = "unlimited"

local lnk = s2:option(DummyValue, "_link", "Ready-to-use link" .. tip("Click the link to copy it."))
lnk.rawhtml = true
lnk.default = [[<div class="link-wrapper"><input type="text" class="cbi-input-text user-link-out" readonly onclick="this.select()"></div>]]

return m
