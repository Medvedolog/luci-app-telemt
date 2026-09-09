local legacy = require "luci.model.cbi.telemt_legacy"
local memory_budget = require "luci.model.cbi.telemt_memory_budget"
local web_users = require "luci.model.cbi.telemt_users_web"
legacy = memory_budget.attach(legacy)
return web_users.attach(legacy)
