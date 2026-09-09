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
