-- Run with lua5.1 tools/test-web-links.lua
package.path = "root/usr/lib/lua/?.lua;root/usr/lib/lua/?/init.lua;" .. package.path
local link = require "luci.model.telemt_web_link"
local secret = "00112233445566778899aabbccddeeff"
assert(link.format("proxy.example.com", "", secret, "plain") ==
    "tg://webproxy?server=proxy.example.com&secret=" .. secret)
assert(link.format("proxy.example.com", "", secret, "dd") ==
    "tg://webproxy?server=proxy.example.com&secret=dd" .. secret)
local plain = link.format("proxy.example.com", "MixedCase/path", secret, "plain")
print("plain-v2:", tostring(plain))
assert(plain and plain:find("server=proxy.example.com%2FMixedCase%2Fpath", 1, true))
assert(plain:find("secret=cAARIjNEVWZ3iJmqu8zd7v8", 1, true))
local dd = link.format("proxy.example.com", "p", secret, "dd")
print("dd-v2:", tostring(dd))
assert(dd and dd:find("secret=cN0AESIzRFVmd4iZqrvM3e7_", 1, true))
assert(link.format("proxy.example.com", "/bad", secret, "dd") == nil)
assert(link.format("proxy.example.com", "bad//path", secret, "dd") == nil)
assert(link.format("proxy.example.com", "bad/", secret, "dd") == nil)
assert(link.format("proxy.example.com", "valid", "invalid", "dd") == nil)
print("WEB v1/v2 link regression tests passed")
