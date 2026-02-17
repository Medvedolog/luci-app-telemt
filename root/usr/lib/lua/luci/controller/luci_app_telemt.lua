module("luci.controller.luci_app_telemt", package.seeall)
function index()
    if not nixio.fs.access("/etc/config/telemt") then return end
    entry({"admin", "services", "luci-app-telemt"}, cbi("telemt"), _("Telegram Proxy (MTProto)"), 100).dependent = true
end
