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
end
