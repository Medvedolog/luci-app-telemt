#
# Copyright (C) 2026 Medvedolog
#
# This is free software, licensed under the GNU General Public License v2.
#
# Buildroot definition. Release packages (IPK for 24.10, APKv3 for 25.12) are built
# from the same staged tree by owfeed — see owfeed.yml and RELEASING.md.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-telemt
PKG_VERSION:=3.5.14
PKG_RELEASE:=1

PKG_MAINTAINER:=Medvedolog
PKG_LICENSE:=GPL-2.0-or-later

LUCI_TITLE:=LuCI WebUI for Telemt MTProxy (WEB Proxy, multi-user, diagnostics)
# The telemt core owns /etc/config/telemt, so it is deliberately not a hard
# dependency: the UI stays installable and repairable when feeds are unreachable.
LUCI_DEPENDS:=+luci-base +luci-compat +qrencode +ca-bundle
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
$(eval $(call BuildPackage,$(PKG_NAME)))
