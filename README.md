<h1 align="center">luci-app-telemt v3.0</h1>

<p align="center">
  A clean, fast, and feature-rich LuCI web interface for the <a href="https://github.com/telemt/telemt">Telemt MTProto Proxy</a> on OpenWrt routers.
</p>

<table width="100%">
  <tr>
    <th width="50%">🇷🇺 Русский</th>
    <th width="50%">🇬🇧 English</th>
  </tr>
  <tr>
    <td valign="top">
      <b>✨ Особенности веб-интерфейса (LuCI)</b>
      <ul>
        <li><b>Умный сканер IP:</b> Мгновенное получение внешнего WAN IP без зависаний админки роутера.</li>
        <li><b>Управление пользователями:</b> Удобное добавление клиентов, автогенерация 32-hex секретов и готовых <code>tg://</code> ссылок.</li>
        <li><b>Продвинутая маршрутизация:</b> SOCKS5 апстрим для обхода жестких DPI (ТСПУ) и поддержка IPv6.</li>
        <li><b>Темная тема:</b> Полная совместимость с темами вроде Argon (OpenWrt 18.06 - 24.10).</li>
      </ul>
      <b>🚀 Telemt 3: Middle-End Proxy</b><br>
      Новая версия движка поддерживает ME Proxy, что дает:
      <ul>
        <li>Функциональные медиа (включая быструю загрузку картинок и видео через CDN/DC=203).</li>
        <li>Поддержку <b>Ad-tag</b> — показ спонсорского канала и сбор статистики через официального бота.</li>
        <li>Новый подход к безопасности и асинхронности.</li>
      </ul>
      <b>⚙️ Требования для работы ME Proxy:</b>
      <ul>
        <li>Бинарный файл <code>telemt</code> версии ≥ 3.0.0.</li>
        <li>Публичный IP на интерфейсе для исходящих соединений <b>ИЛИ</b> использование NAT 1:1 со включенным STUN-пробингом.</li>
      </ul>
      <i>💡 Если условия не выполняются, отключите опцию "Use ME Proxy" в настройках интерфейса. В противном случае прокси отключит его по таймауту, но это сильно замедлит запуск сервиса. LuCI автоматически настроит <code>dc_overrides</code> в конфиге для работы медиа в классическом режиме.</i>
    </td>
    <td valign="top">
      <b>✨ Web Interface Features (LuCI)</b>
      <ul>
        <li><b>Smart IP Fetching:</b> Instantly fetches your external WAN IP without freezing the router interface.</li>
        <li><b>Multi-User Management:</b> Easily add users, auto-generate secure 32-hex secrets, and get ready-to-use <code>tg://</code> proxy links.</li>
        <li><b>Advanced Routing:</b> SOCKS5 upstream routing for bypassing strict DPIs and IPv6 fallback support.</li>
        <li><b>Dark Mode Ready:</b> Fully compatible with popular LuCI themes like Argon (OpenWrt 18.06 - 24.10).</li>
      </ul>
      <b>🚀 Telemt 3: Middle-End Proxy</b><br>
      The new core version supports ME Proxy, which means:
      <ul>
        <li>Functional media (including fast image/video loading via CDN/DC=203).</li>
        <li><b>Ad-tag</b> support to promote a sponsored channel and collect stats.</li>
        <li>New approach to security and asynchronicity.</li>
      </ul>
      <b>⚙️ Requirements for ME Proxy:</b>
      <ul>
        <li><code>telemt</code> binary version ≥ 3.0.0.</li>
        <li>A public IP assigned to the outbound network interface <b>OR</b> using 1:1 NAT with STUN probing enabled.</li>
      </ul>
      <i>💡 If conditions aren't met, disable the "Use ME Proxy" option in the GUI. Otherwise, it will be disabled automatically after a timeout, significantly increasing startup time. LuCI handles <code>dc_overrides</code> automatically for classic mode media routing.</i>
    </td>
  </tr>
</table>

## 📦 Installation / Установка

1. Go to the [Releases](../../releases) page / Перейдите в раздел Релизов.
2. Download the `luci-app-telemt` IPK and the correct `telemt` binary IPK for your router's CPU architecture (e.g., `aarch64_generic`).
3. Upload them to your router (e.g., to `/tmp/`) and install via SSH:
   ```bash
   opkg update
   opkg install /tmp/telemt_*.ipk
   opkg install /tmp/luci-app-telemt_*.ipk
