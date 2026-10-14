#!/usr/bin/env python3
"""LuCI regressions: missing general and WEB security boundaries."""
from pathlib import Path

root = Path("root/usr/lib/lua/luci")
legacy = (root / "model/cbi/telemt_legacy.lua").read_text()
controller = (root / "controller/telemt.lua").read_text()
wrapper = (root / "model/cbi/telemt.lua").read_text()
web = (root / "model/cbi/telemt_web.lua").read_text()
users = (root / "model/cbi/telemt_users_web.lua").read_text()
assert 'local general_cfg_type = uci_cursor:get("telemt", "general")' in legacy
assert 'general_cfg_type ~= "telemt"' in legacy
assert 'general_cfg_warning' in legacy
assert 'uci -q show telemt.general' in legacy
assert 'm:section(NamedSection, "general", "telemt")' in legacy
assert 'setfenv(chunk, cbi_env)' in wrapper
assert 'tg://webproxy?server=' in controller
assert 'tg://webproxy?server=' in web
assert 'tg://webproxy?server=' in users
assert 'HTTP_X_REQUESTED_WITH' in controller
assert 'act ~= "check" and act ~= "apply" and act ~= "restore"' in controller
assert 'self.map.uci:delete("telemt", sid)' in users
assert 'debug_sideband.default = debug_sideband.disabled' in web
print("LuCI regression contracts: OK")
