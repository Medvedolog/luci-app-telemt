#!/bin/sh
# Source-level checks that need no OpenWrt: Lua 5.1 syntax, JSON, shell syntax.
set -eu
cd "$(dirname "$0")/.."

command -v luac5.1 >/dev/null 2>&1 && LUAC=luac5.1 || LUAC=luac
command -v "$LUAC" >/dev/null 2>&1 || { echo "luac (Lua 5.1) is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

find root -name '*.lua' -print | sort | while read -r f; do
    "$LUAC" -p "$f"
    echo "lua ok: $f"
done

find root -name '*.json' -print | sort | while read -r f; do
    jq -e . "$f" >/dev/null
    echo "json ok: $f"
done

for s in scripts/*; do
    [ -f "$s" ] || continue
    sh -n "$s"
    echo "sh ok: $s"
done

# Same base version in version.txt and the Makefile.
v="$(tr -d '[:space:]' < version.txt)"
m="$(sed -n 's/^PKG_VERSION:=//p' Makefile | head -n1)"
[ "$v" = "$m" ] || { echo "version.txt ($v) != Makefile PKG_VERSION ($m)" >&2; exit 1; }
echo "version ok: $v"

# --- Menu, ownership and WEB payload contracts -------------------------------
MENU=root/usr/share/luci/menu.d/luci-app-telemt.json
jq -e 'has("admin/services/telemt")' "$MENU" >/dev/null
jq -e 'has("admin/services/telemt/web") | not' "$MENU" >/dev/null

WEB_MODEL=root/usr/lib/lua/luci/model/cbi/telemt_web.lua
USERS_WRAPPER=root/usr/lib/lua/luci/model/cbi/telemt.lua
USERS_LEGACY=root/usr/lib/lua/luci/model/cbi/telemt_legacy.lua
USERS_WEB=root/usr/lib/lua/luci/model/cbi/telemt_users_web.lua
CONTROLLER=root/usr/lib/lua/luci/controller/telemt.lua

fail() { echo "ERROR: $*" >&2; exit 1; }

for f in "$WEB_MODEL" "$USERS_WRAPPER" "$USERS_LEGACY" "$USERS_WEB"; do [ -s "$f" ] || fail "empty or missing: $f"; done
grep -q 'cbi("telemt_web")' "$CONTROLLER"
grep -q 'WEB Proxy' "$WEB_MODEL"
grep -q 'entry({"admin", "services", "telemt", "web"}, cbi("telemt_web")).leaf = true' "$CONTROLLER"
! grep -q 'cbi("telemt_web"), _("WEB Proxy")' "$CONTROLLER" || fail 'internal WEB route must stay hidden from LuCI child navigation'
grep -q '3.5.14-r1 WEB RC' "$USERS_LEGACY"
grep -q 'local general_cfg_type = uci_cursor:get("telemt", "general")' "$USERS_LEGACY"
grep -q 'general_cfg_warning' "$USERS_LEGACY"
grep -q 'uci -q show telemt.general' "$USERS_LEGACY"
grep -q 'debug_sideband = web:taboption("settings", Flag, "debug_sideband"' "$WEB_MODEL"
grep -q 'debug_capture = web:taboption("settings", Flag, "debug_capture_lifecycle"' "$WEB_MODEL"
grep -q 'debug_sideband.default = debug_sideband.disabled' "$WEB_MODEL"
grep -q 'cmp_ver(bin_ver, "3.5.8") >= 0' "$USERS_LEGACY"
grep -q 's:tab("general", "General Settings")' "$USERS_LEGACY"
grep -q 's:tab("web_proxy", "WEB Proxy")' "$USERS_LEGACY"
grep -q 's:tab("advanced", "Advanced Tuning")' "$USERS_LEGACY"
grep -q 'telemt-main-tabs' "$WEB_MODEL"
! grep -q 'telemt-advanced-subtabs' "$WEB_MODEL" || fail 'WEB Proxy must be a top-level app tab, not an Advanced subtab'
! grep -q 'telemt_adv=1' "$WEB_MODEL" || fail 'stale Advanced-subtab deep link (telemt_adv=1) found'

# Fixed helper endpoints only; LuCI must never execute an arbitrary command.
grep -q 'call("web_frontend_action")' "$CONTROLLER"
grep -q 'act ~= "check" and act ~= "apply" and act ~= "restore"' "$CONTROLLER"
grep -q 'haproxy = "/usr/libexec/telemt-web-frontend"' "$CONTROLLER"
grep -q 'nginx = "/usr/libexec/telemt-web-nginx"' "$CONTROLLER"
grep -q 'call("web_qr")' "$CONTROLLER"
grep -q 'tg://webproxy?server=' "$CONTROLLER"
grep -q 'tg://webproxy?server=' "$WEB_MODEL"
grep -q 'X-Requested-With' "$WEB_MODEL"
grep -q 'HTTP_X_REQUESTED_WITH' "$CONTROLLER"
grep -q 'pcall(require, "luci.i18n")' "$WEB_MODEL"
grep -q 'local _ = (ok_i18n and i18n and i18n.translate)' "$WEB_MODEL"

# All four exact carrier values stay available, fixed by default, with explicit
# auto-negotiation controls.
grep -q 'carrier_policy = web:taboption("settings", ListValue, "carrier_policy"' "$WEB_MODEL"
grep -q 'carrier_policy:value("fixed"' "$WEB_MODEL"
grep -q 'carrier_policy:value("auto"' "$WEB_MODEL"
grep -q 'carrier_policy.default = "fixed"' "$WEB_MODEL"
grep -q 'carrier:value("https", "HTTPS")' "$WEB_MODEL"
grep -q 'carrier:value("https-lanes", "HTTPS lanes")' "$WEB_MODEL"
grep -q 'carrier:value("websocket", "WebSocket")' "$WEB_MODEL"
grep -q 'carrier:value("websocket-lanes", "WebSocket lanes")' "$WEB_MODEL"
grep -q 'carrier.default = "https"' "$WEB_MODEL"
grep -q 'carrier_candidates = web:taboption("settings", DynamicList, "carrier_candidate"' "$WEB_MODEL"
grep -q 'carrier_candidates:depends("carrier_policy", "auto")' "$WEB_MODEL"
grep -q 'carrier_candidates.default = { "websocket-lanes", "websocket", "https-lanes" }' "$WEB_MODEL"
grep -q 'Duplicate WEB carrier candidate' "$WEB_MODEL"
grep -q 'carrier_learning = web:taboption("settings", Flag, "carrier_learning"' "$WEB_MODEL"
grep -q 'carrier_learning.default = carrier_learning.enabled' "$WEB_MODEL"
grep -q 'carrier_aggr = web:taboption("settings", ListValue, "carrier_negotiation_aggressiveness"' "$WEB_MODEL"
grep -q 'carrier_aggr:value("conservative"' "$WEB_MODEL"
grep -q 'carrier_aggr:value("balanced"' "$WEB_MODEL"
grep -q 'carrier_aggr:value("aggressive"' "$WEB_MODEL"
grep -q 'carrier_aggr.default = "conservative"' "$WEB_MODEL"

# Users integration: CBI fragments must execute in the same injected CBI
# environment. require() loses Map/Value under ucodebridge on 24.10.
grep -q 'local function load_cbi_fragment' "$USERS_WRAPPER"
grep -q 'telemt_legacy.lua' "$USERS_WRAPPER"
grep -q 'telemt_memory_budget.lua' "$USERS_WRAPPER"
grep -q 'telemt_users_web.lua' "$USERS_WRAPPER"
grep -q 'setfenv(chunk, cbi_env)' "$USERS_WRAPPER"
grep -q 'return web_users.attach(legacy)' "$USERS_WRAPPER"
! grep -q 'require "luci.model.cbi.telemt_legacy"' "$USERS_WRAPPER" || fail 'legacy CBI must not be loaded with require() under ucodebridge'
grep -q 'uci:foreach("telemt", "web_profile"' "$USERS_WEB"
grep -q 'tg://webproxy?server=' "$USERS_WEB"
grep -q 'WEB: ' "$USERS_WEB"
grep -q 'Copy WEB' "$USERS_WEB"
grep -q 'web_qr' "$USERS_WEB"
grep -q 'self.map.uci:delete("telemt", sid)' "$USERS_WEB"
grep -q 'Delete the user and all of these WEB bindings' "$USERS_WEB"
! grep -qE 'set\("telemt".*(web_)?secret|option\([^,]+,[[:space:]]*"(web_)?secret"' "$USERS_WEB" || fail 'Users WEB integration must not create a second secret store'

# The WEB page exposes the three mutually exclusive frontend modes.
grep -q 'frontend:value("external"' "$WEB_MODEL"
grep -q 'frontend:value("haproxy"' "$WEB_MODEL"
grep -q 'frontend:value("nginx"' "$WEB_MODEL"
grep -q '"nginx_managed"' "$WEB_MODEL"
grep -q '"nginx_bind"' "$WEB_MODEL"
grep -q '"nginx_cert"' "$WEB_MODEL"
grep -q '"nginx_key"' "$WEB_MODEL"
grep -q '"nginx_auto_fw"' "$WEB_MODEL"
grep -q 'saved_frontend' "$WEB_MODEL"
grep -q '/usr/libexec/telemt-web-nginx' "$WEB_MODEL"

# WEB profiles reference the shared config user; no WEB-specific secret option.
grep -q 'pr:option(ListValue, "user"' "$WEB_MODEL"
! grep -qE 'option\([^,]+,[[:space:]]*"(web_)?secret"' "$WEB_MODEL" || fail 'WEB page must not store a duplicate secret'

# Packaging is owfeed-only: one staged tree -> 24.10/IPK and 25.12/APKv3.
[ ! -e nfpm.yaml ] || fail 'nfpm.yaml must not come back'
grep -q 'format: ipk' owfeed.yml
grep -q 'format: apk' owfeed.yml
grep -q 'arch: noarch' owfeed.yml
grep -q 'version-from: file:./dist/VERSION' owfeed.yml

# The core bundle: script parses, and the pinned core key matches the id it checks.
sh -n tools/bundle-core.sh
[ -s keys/telemt-core-release.pub ]
[ "$(tail -n1 keys/telemt-core-release.pub | base64 -d | od -An -tx1 -j2 -N8 | tr -d ' \n')" = "$(sed -n 's/^CORE_KEY_ID="\(.*\)"/\1/p' tools/bundle-core.sh)" ] || fail 'keys/telemt-core-release.pub does not match CORE_KEY_ID in tools/bundle-core.sh'
grep -q 'bundle-core' .github/workflows/ci.yml

echo 'source contracts ok'
