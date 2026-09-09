-- ==============================================================================
-- Telemt LuCI Controller
-- Registers the application inside OpenWrt's main navigation tree.
-- ==============================================================================
module("luci.controller.telemt", package.seeall)

function index()
    -- Main legacy CBI page.
    entry({"admin", "services", "telemt"}, cbi("telemt"), _("Telemt MTProxy"), 50).dependent = true

    -- Telemt 3.5.6+ WEB Proxy configuration. Kept in a separate CBI model so the
    -- large legacy telemt.lua does not become the second source of WEB logic.
    entry({"admin", "services", "telemt", "web"}, cbi("telemt_web"), _("WEB Proxy"), 60).leaf = true

    -- AJAX-only frontend helper endpoint. It never accepts arbitrary commands:
    -- only the three fixed operations supported by the core helper are allowed.
    entry({"admin", "services", "telemt", "web_frontend_action"}, call("web_frontend_action")).leaf = true

    -- Read-only QR endpoint. The browser supplies only a UCI profile section id;
    -- the tg://webproxy link itself is assembled server-side from shared UCI data.
    entry({"admin", "services", "telemt", "web_qr"}, call("web_qr")).leaf = true
end

function web_frontend_action()
    local http = require "luci.http"
    local sys = require "luci.sys"

    if http.getenv("REQUEST_METHOD") ~= "POST" then
        http.status(405, "Method Not Allowed")
        http.prepare_content("text/plain")
        http.write("POST required\n")
        return
    end

    -- Old supported LuCI versions do not consistently provide http.formtoken().
    -- Requiring an XHR-only header prevents ordinary cross-origin HTML forms from
    -- invoking a destructive helper while preserving compatibility with 21.02+.
    if http.getenv("HTTP_X_REQUESTED_WITH") ~= "XMLHttpRequest" then
        http.status(403, "Forbidden")
        http.prepare_content("text/plain")
        http.write("XHR required\n")
        return
    end

    local act = http.formvalue("action") or ""
    if act ~= "check" and act ~= "apply" and act ~= "restore" then
        http.status(400, "Bad Request")
        http.prepare_content("text/plain")
        http.write("Unsupported action\n")
        return
    end

    local helper = "/usr/libexec/telemt-web-frontend"
    if sys.call("test -x " .. helper .. " >/dev/null 2>&1") ~= 0 then
        http.status(503, "Service Unavailable")
        http.prepare_content("text/plain")
        http.write("Core helper is missing: " .. helper .. "\n")
        return
    end

    -- act is whitelisted above; no user-controlled shell fragment reaches sh.
    local raw = sys.exec(helper .. " " .. act .. " 2>&1; rc=$?; printf '\n__TELEMT_RC__%s\n' \"$rc\"") or ""
    local rc = tonumber(raw:match("\n__TELEMT_RC__(%d+)%s*$")) or 1
    raw = raw:gsub("\n__TELEMT_RC__%d+%s*$", "")

    sys.call(string.format("logger -t telemt 'WebUI: WEB frontend %s rc=%d'", act, rc))
    if rc ~= 0 then http.status(409, "Frontend Action Failed") end
    http.prepare_content("text/plain")
    http.write(raw ~= "" and (raw .. "\n") or (rc == 0 and "OK\n" or "FAILED\n"))
end

function web_qr()
    local http = require "luci.http"
    local sys = require "luci.sys"
    local uci = require("luci.model.uci").cursor()

    local profile = http.formvalue("profile") or ""
    if not profile:match("^[A-Za-z0-9_]+$") then
        http.status(400, "Bad Request")
        http.prepare_content("text/plain")
        http.write("Invalid profile id\n")
        return
    end

    local p = uci:get_all("telemt", profile)
    if not p or p[".type"] ~= "web_profile" then
        http.status(404, "Not Found")
        http.prepare_content("text/plain")
        http.write("WEB profile not found\n")
        return
    end

    local user = tostring(p.user or "")
    local vhost_name = tostring(p.vhost or "")
    local mode = tostring(p.secret_mode or "dd")
    if not user:match("^[A-Za-z0-9_]+$") or not vhost_name:match("^[A-Za-z0-9_-]+$") or (mode ~= "plain" and mode ~= "dd") then
        http.status(409, "Invalid Profile")
        http.prepare_content("text/plain")
        http.write("WEB profile is incomplete\n")
        return
    end

    local u = uci:get_all("telemt", user)
    local secret = u and tostring(u.secret or "") or ""
    if not u or u[".type"] ~= "user" or #secret ~= 32 or not secret:match("^[0-9A-Fa-f]+$") then
        http.status(409, "Invalid User")
        http.prepare_content("text/plain")
        http.write("Shared user or secret is invalid\n")
        return
    end

    local host = nil
    uci:foreach("telemt", "web_vhost", function(s)
        if not host and tostring(s.name or "") == vhost_name then
            local h = tostring(s.host or ""):lower()
            if h:match("^[A-Za-z0-9][A-Za-z0-9%.%-]*[A-Za-z0-9]$") and h:find("%.") then host = h end
        end
    end)
    if not host then
        http.status(409, "Invalid VHost")
        http.prepare_content("text/plain")
        http.write("WEB vhost is missing or invalid\n")
        return
    end

    if sys.call("command -v qrencode >/dev/null 2>&1") ~= 0 then
        http.status(503, "Service Unavailable")
        http.prepare_content("text/plain")
        http.write("qrencode is not installed\n")
        return
    end

    local web_secret = (mode == "dd" and "dd" or "") .. secret:lower()
    local link = "tg://webproxy?server=" .. host .. "&secret=" .. web_secret
    -- host and secret are strictly validated above; %q additionally quotes the
    -- complete fixed-format argument for the shell invoked by luci.sys.exec().
    local png = sys.exec(string.format("qrencode -t PNG -o - %q 2>/dev/null", link)) or ""
    if png == "" then
        http.status(500, "QR Generation Failed")
        http.prepare_content("text/plain")
        http.write("qrencode failed\n")
        return
    end

    http.header("Cache-Control", "no-store")
    http.header("Pragma", "no-cache")
    http.prepare_content("image/png")
    http.write(png)
end
