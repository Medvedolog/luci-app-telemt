-- Telemt 3.5.6 WEB integration for the legacy Users CBI model.
-- Keeps config user as the single user database while surfacing WEB bindings,
-- WEB links/QR and atomic user+WEB-profile deletion in the existing Users tab.

local sys = require "luci.sys"
local dsp = require "luci.dispatcher"
local uci = require("luci.model.uci").cursor()

local M = {}

local function jsq(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n")
    s = s:gsub("<", "\\u003c"):gsub(">", "\\u003e"):gsub("&", "\\u0026")
    return '"' .. s .. '"'
end

local function build_web_data()
    local vhosts = {}
    uci:foreach("telemt", "web_vhost", function(s)
        local name = tostring(s.name or "")
        local host = tostring(s.host or ""):lower()
        if name ~= "" and host ~= "" and tostring(s.enabled or "1") ~= "0" then
            vhosts[name] = host
        end
    end)

    local users = {}
    uci:foreach("telemt", "web_profile", function(p)
        local user = tostring(p.user or "")
        if user == "" then return end
        local list = users[user]
        if not list then list = {}; users[user] = list end

        local sid = tostring(p[".name"] or "")
        local vhost = tostring(p.vhost or "")
        local mode = tostring(p.secret_mode or "dd")
        local enabled = tostring(p.enabled or "1") ~= "0"
        local host = vhosts[vhost]
        local ud = uci:get_all("telemt", user)
        local secret = ud and tostring(ud.secret or "") or ""
        local user_enabled = ud and tostring(ud.enabled or "1") ~= "0"
        local link = nil

        if enabled and user_enabled and host and #secret == 32 and secret:match("^[0-9A-Fa-f]+$") and (mode == "plain" or mode == "dd") then
            link = "tg://webproxy?server=" .. host .. "&secret=" .. (mode == "dd" and "dd" or "") .. secret:lower()
        end

        list[#list + 1] = {
            section = sid,
            vhost = vhost,
            host = host or "",
            mode = mode,
            enabled = enabled,
            link = link
        }
    end)
    return users
end

local function web_data_js(users)
    local out = { "{" }
    local first_user = true
    for user, profiles in pairs(users) do
        if not first_user then out[#out + 1] = "," end
        first_user = false
        out[#out + 1] = jsq(user) .. ":["
        for i, p in ipairs(profiles) do
            if i > 1 then out[#out + 1] = "," end
            out[#out + 1] = "{section:" .. jsq(p.section) .. ",vhost:" .. jsq(p.vhost) .. ",host:" .. jsq(p.host) .. ",mode:" .. jsq(p.mode) .. ",enabled:" .. (p.enabled and "true" or "false") .. ",link:" .. (p.link and jsq(p.link) or "null") .. "}"
        end
        out[#out + 1] = "]"
    end
    out[#out + 1] = "}"
    return table.concat(out)
end

function M.attach(m)
    if not m then return m end

    local user_section = nil
    for _, child in ipairs(m.children or {}) do
        if child.sectiontype == "user" then user_section = child; break end
    end

    if user_section then
        local base_remove = user_section.remove
        user_section.remove = function(self, section)
            local doomed = {}
            self.map.uci:foreach("telemt", "web_profile", function(p)
                if tostring(p.user or "") == tostring(section or "") then
                    doomed[#doomed + 1] = p[".name"]
                end
            end)
            for _, sid in ipairs(doomed) do self.map.uci:delete("telemt", sid) end
            if #doomed > 0 then
                sys.call(string.format("logger -t telemt %q", "WebUI: deleting user " .. tostring(section) .. " with " .. #doomed .. " WEB binding(s)"))
            end
            if base_remove then return base_remove(self, section) end
            return nil
        end
    end

    local data = build_web_data()
    local data_js = web_data_js(data)
    local qr_base = dsp.build_url("admin", "services", "telemt", "web_qr")

    local html = [[
<style>
.telemt-web-user-box { margin-top:6px; padding-top:6px; border-top:1px dashed rgba(128,128,128,.25); font-size:11px; }
.telemt-web-user-summary { display:flex; align-items:center; gap:5px; cursor:pointer; user-select:none; }
.telemt-web-user-badge { display:inline-block; padding:2px 6px; border-radius:4px; border:1px solid rgba(0,105,214,.35); background:rgba(0,105,214,.08); color:#0069d6; font-weight:bold; white-space:nowrap; }
.telemt-web-user-none { opacity:.55; font-size:11px; margin-top:5px; }
.telemt-web-profile-row { margin-top:5px; padding:5px; border-radius:4px; background:rgba(128,128,128,.05); border:1px solid rgba(128,128,128,.15); }
.telemt-web-profile-meta { opacity:.75; margin-bottom:3px; white-space:normal; }
.telemt-web-link-out { width:100%; box-sizing:border-box; font-family:monospace; font-size:10px; height:28px; background:transparent; color:inherit; border:1px solid rgba(128,128,128,.4); }
.telemt-web-link-actions { display:flex; gap:4px; margin-top:3px; }
.telemt-web-link-actions .cbi-button { height:24px !important; min-height:24px !important; line-height:22px !important; padding:0 8px !important; font-size:11px !important; }
</style>
<script type="text/javascript">
(function(){
    var webUsers = ]] .. data_js .. [[;
    var qrBase = ]] .. jsq(qr_base) .. [[;

    function userFromRow(row) {
        var sec = row && row.querySelector('input[name*=".secret"]');
        if (!sec) return null;
        var m = sec.name.match(/cbid\.telemt\.([^.]+)\.secret/);
        return m ? m[1] : null;
    }

    function copyText(text, btn) {
        if (!text) return;
        function done(){ var old=btn.value; btn.value='Copied!'; setTimeout(function(){btn.value=old;},1200); }
        if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(text).then(done).catch(function(){});
        else {
            var ta=document.createElement('textarea'); ta.value=text; ta.style.position='fixed'; ta.style.left='-9999px'; document.body.appendChild(ta); ta.select();
            try { document.execCommand('copy'); done(); } catch(e){} document.body.removeChild(ta);
        }
    }

    function injectWebUsers() {
        var rows=document.querySelectorAll('#cbi-telemt-user .cbi-section-table-row:not(.cbi-row-template), #cbi-telemt-user tr.cbi-row:not(.cbi-row-template), #cbi-telemt-user div.cbi-row:not(.cbi-row-template)');
        rows.forEach(function(row){
            if (row.querySelector('.telemt-web-user-box') || row.querySelector('.telemt-web-user-none')) return;
            var user=userFromRow(row); if(!user) return;
            var wrap=row.querySelector('.link-wrapper'); if(!wrap) return;
            var profiles=webUsers[user] || [];
            if (!profiles.length) {
                var none=document.createElement('div'); none.className='telemt-web-user-none'; none.textContent='WEB: —'; wrap.appendChild(none); return;
            }

            var box=document.createElement('details'); box.className='telemt-web-user-box'; box.setAttribute('data-web-bindings', String(profiles.length));
            var sum=document.createElement('summary'); sum.className='telemt-web-user-summary';
            var badge=document.createElement('span'); badge.className='telemt-web-user-badge'; badge.textContent='WEB: ' + profiles.length + (profiles.length===1 ? ' profile' : ' profiles'); sum.appendChild(badge); box.appendChild(sum);

            profiles.forEach(function(p){
                var pr=document.createElement('div'); pr.className='telemt-web-profile-row';
                var meta=document.createElement('div'); meta.className='telemt-web-profile-meta';
                meta.textContent=(p.host || p.vhost || p.section) + ' · ' + String(p.mode || '').toUpperCase(); pr.appendChild(meta);
                if (p.link) {
                    var inp=document.createElement('input'); inp.type='text'; inp.readOnly=true; inp.className='telemt-web-link-out'; inp.value=p.link; inp.addEventListener('click',function(){this.select();}); pr.appendChild(inp);
                    var actions=document.createElement('div'); actions.className='telemt-web-link-actions';
                    var cp=document.createElement('input'); cp.type='button'; cp.className='cbi-button cbi-button-action'; cp.value='Copy WEB'; cp.addEventListener('click',function(){copyText(p.link,cp);}); actions.appendChild(cp);
                    var qr=document.createElement('input'); qr.type='button'; qr.className='cbi-button cbi-button-neutral'; qr.value='QR'; qr.addEventListener('click',function(){window.open(qrBase + '?profile=' + encodeURIComponent(p.section),'_blank','noopener');}); actions.appendChild(qr); pr.appendChild(actions);
                } else {
                    var off=document.createElement('div'); off.style.opacity='.6'; off.textContent=p.enabled ? 'WEB binding is not active/valid yet' : 'WEB profile disabled'; pr.appendChild(off);
                }
                box.appendChild(pr);
            });
            wrap.appendChild(box);
        });
    }

    document.addEventListener('click', function(e){
        var btn=e.target && e.target.closest ? e.target.closest('#cbi-telemt-user .cbi-button-remove') : null;
        if(!btn) return;
        var row=btn.closest('.cbi-section-table-row') || btn.closest('.cbi-row');
        var user=userFromRow(row); if(!user) return;
        var n=(webUsers[user] || []).length; if(n < 1) return;
        if(!window.confirm('User "' + user + '" is used by ' + n + ' WEB profile' + (n===1?'':'s') + '. Delete the user and all of these WEB bindings?')) {
            e.preventDefault(); e.stopPropagation(); if(e.stopImmediatePropagation) e.stopImmediatePropagation();
        }
    }, true);

    if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',injectWebUsers);
    else injectWebUsers();
    setTimeout(injectWebUsers,250); setTimeout(injectWebUsers,1200);
    if(window.MutationObserver) new MutationObserver(injectWebUsers).observe(document.body,{childList:true,subtree:true});
})();
</script>
]]
    m.description = (m.description or "") .. html
    return m
end

return M
