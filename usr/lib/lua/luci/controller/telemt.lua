-- ==============================================================================
-- Telemt LuCI Controller
-- Registers the application inside OpenWrt's main navigation tree.
-- ==============================================================================
module("luci.controller.telemt", package.seeall)

function index()
    -- Mounts the CBI model at 'Admin -> Services -> Telemt MTProxy' with sorting weight 50.
    entry({"admin", "services", "telemt"}, cbi("telemt"), _("Telemt MTProxy"), 50).dependent = true
end

