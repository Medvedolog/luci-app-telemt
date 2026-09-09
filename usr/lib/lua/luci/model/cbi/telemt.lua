local legacy = require "luci.model.cbi.telemt_legacy"
local web_users = require "luci.model.cbi.telemt_users_web"
return web_users.attach(legacy)
