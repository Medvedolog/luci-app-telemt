# luci-app-telemt

A clean, fast, and feature-rich LuCI web interface for the [Telemt MTProto Proxy](https://github.com/telemt/telemt) on OpenWrt routers.

This package provides a seamless GUI to configure, manage, and monitor your Telegram proxy directly from your OpenWrt administration panel.

## ✨ Features

* **Full Telemt v3.0+ Support**: Compatible with FakeTLS, DD obfuscation, and Classic modes.
* **Smart IP Fetching**: Instantly fetches your external WAN IP (via Yandex/AWS API) without freezing the router interface.
* **Multi-User Management**: Easily add users and auto-generate secure 32-hex secrets and ready-to-use `tg://` proxy links.
* **Advanced Routing**: 
  * Middle-End (ME) Proxy & STUN support for NAT.
  * SOCKS5 upstream routing for bypassing strict DPIs.
  * IPv6 fallback support.
* **Dark Mode Ready**: Fully compatible with popular LuCI themes like Argon.

## ⚙️ Requirements

* **OpenWrt**: 18.06, 19.07, 21.02, 22.03, 23.05, or 24.10.
* **Dependencies**: `luci-base`, `luci-compat`, `ca-bundle` (automatically resolved).
* **Telemt Binary**: The core `telemt` proxy binary is required. 

## 🚀 Installation

1. Go to the [Releases](../../releases) page.
2. Download the `luci-app-telemt` IPK package and the correct `telemt` binary IPK for your router's architecture (e.g., `aarch64_generic`).
3. Upload them to your router (e.g., `/tmp/`) and install via SSH:
   ```bash
   opkg update
   opkg install /tmp/telemt_*.ipk
   opkg install /tmp/luci-app-telemt_*.ipk