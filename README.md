
# luci-app-telemt - OpenWRT WEB interface

<table width="100%">
  <tr>
    <th width="50%">🇷🇺 Русский</th>
    <th width="50%">🇬🇧 English</th>
  </tr>
  <tr>
    <td valign="top">
      Веб-интерфейс (LuCI) для управления MTProto-прокси <a href="https://github.com/telemt/telemt">Telemt</a> на маршрутизаторах OpenWrt. 
      Пакет работает как генератор файла конфигурации <code>telemt.toml</code> и управляет жизненным циклом демона через подсистему <code>procd</code>.
      <br><br>
      <b>Требования:</b>
      <ul>
        <li>ОС: OpenWrt 18.06 — 24.10</li>
        <li>Зависимости: <code>luci-base</code>, <code>luci-compat</code>, <code>ca-bundle</code></li>
        <li>Движок: бинарный файл <code>telemt</code> <b>версии 3.0.0 и выше</b>.</li>
      </ul>
      <b>Реализация функций движка (~90%)</b><br>
      Интерфейс покрывает подавляющее большинство параметров оригинального конфигурационного файла. Поддерживаемые секции TOML:
      <ul>
        <li><code>[general]</code>: Выбор режимов (tls, secure, classic), включение Middle-End Proxy (<code>use_middle_proxy</code>), <code>stun_probing</code>, поддержка IPv6 (<code>prefer_ipv6</code>) и спонсорского <code>ad_tag</code>.</li>
        <li><code>[server]</code>: Назначение порта, протокола (IPv4/IPv6), форсирование <code>announce_ip</code>.</li>
        <li><code>[timeouts]</code>: Пользовательские значения для <code>client_handshake</code>, <code>tg_connect</code>, <code>client_keepalive</code> и <code>client_ack</code>.</li>
        <li><code>[censorship]</code>: Выбор домена <code>tls_domain</code> для маскировки FakeTLS.</li>
        <li><code>[access]</code>: Управление списком пользователей <code>access.users</code>, настройка индивидуальных парметров <code>user_max_tcp_conns</code> и <code>user_data_quota</code>.</li>
        <li><code>[dc_overrides]</code>: Автоматическая маршрутизация медиа/CDN (DC 203), если ME-режим отключен.</li>
        <li><code>[upstreams]</code>: Выбор между <code>direct</code> и <code>socks5</code> (включая авторизацию по логину/паролю).</li>
      </ul>
    </td>
    <td valign="top">
      A LuCI web interface for managing the <a href="https://github.com/telemt/telemt">Telemt</a> MTProto proxy on OpenWrt routers. 
      This package acts as a configuration generator for <code>telemt.toml</code> and manages the daemon's lifecycle via <code>procd</code>.
      <br><br>
      <b>Requirements:</b>
      <ul>
        <li>OS: OpenWrt 18.06 — 24.10</li>
        <li>Dependencies: <code>luci-base</code>, <code>luci-compat</code>, <code>ca-bundle</code></li>
        <li>Engine: <code>telemt</code> binary <b>version 3.0.0 or higher</b>.</li>
      </ul>
      <b>Engine Features Implementation (~90%)</b><br>
      The GUI covers the vast majority of parameters from the original TOML configuration. Supported sections include:
      <ul>
        <li><code>[general]</code>: Protocol modes (tls, secure, classic), Middle-End Proxy toggle (<code>use_middle_proxy</code>), <code>stun_probing</code>, IPv6 support (<code>prefer_ipv6</code>), and <code>ad_tag</code>.</li>
        <li><code>[server]</code>: Port binding, IPv4/IPv6 listeners, and <code>announce_ip</code>.</li>
        <li><code>[timeouts]</code>: Custom values for <code>client_handshake</code>, <code>tg_connect</code>, <code>client_keepalive</code>, and <code>client_ack</code>.</li>
        <li><code>[censorship]</code>: Specifying the <code>tls_domain</code> for FakeTLS masking.</li>
        <li><code>[access]</code>: Managing <code>access.users</code>, defining individual <code>user_max_tcp_conns</code>, and <code>user_data_quota</code>.</li>
        <li><code>[dc_overrides]</code>: Automatic media/CDN (DC 203) routing if ME mode is disabled.</li>
        <li><code>[upstreams]</code>: Toggling between <code>direct</code> and <code>socks5</code> routing (including user/pass authentication).</li>
      </ul>
    </td>
  </tr>
</table>

## Installation / Установка (OpenWrt CLI)

You can download and install the pre-compiled packages directly to your router via SSH. 
Change `aarch64_generic` to your router's architecture if necessary.

```bash
opkg update
opkg install unzip
# 1. Download the rollup archived package
cd /tmp
wget https://github.com/Medvedolog/luci-app-telemt/releases/download/v3.0.0/luci-app-telemt_3.0.0-3_all.ipk
# 2. Unzip the archive
unzip Owrt_telemt_3.0.0_aarch64_cortex-a53.zip
# 3. Install packages
opkg install /tmp/telemt_*.ipk
opkg install /tmp/luci-app-telemt_*.ipk
