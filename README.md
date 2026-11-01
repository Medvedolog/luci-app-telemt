<h1 align="center">🌌 luci-app-telemt</h1>
<p align="center"><b>OpenWrt Web Interface for Telemt MTProxy service</b></p>
<br>

<blockquote>
<p><b>🧪 Актуальный тестовый выпуск / Latest test release: Telemt 3.5.16 RC1 (<code>3.5.16-r1</code>)</b></p>
<p>Подписанные <b>IPK для OpenWrt 24.10</b> и <b>APK для OpenWrt 25.12</b>: <a href="https://github.com/Medvedolog/telemt_owrt/releases/tag/3.5.16-rc1">Core</a> · <a href="https://github.com/Medvedolog/luci-app-telemt/releases/tag/3.5.16-rc1">LuCI</a>. <b>GitHub Latest — тестовый RC1, не стабильная версия.</b> Обновлён upstream-движок (ME, WEB, SOCKS и relay); UCI остаётся источником конфигурации, расширенные WEB-функции не включаются по умолчанию. Перед установкой сохраните <code>/etc/config/telemt</code> и возможность отката. Проверяйте Direct/ME/WEB, полный restart, WAN/DNS recovery, CPU/RAM и сохранность пользователей/квот на реальных роутерах.</p>
<p><small>RC1 is tagged Latest for easy access, but remains an experimental test build pending real-router acceptance. Configuration: UCI → generated TOML → procd. <a href="https://github.com/Medvedolog/luci-app-telemt/issues/29">Отчёты тестеров / Test reports</a> (без секретов). История изменений: <a href="https://github.com/Medvedolog/telemt_owrt/releases">Core Releases</a> · <a href="https://github.com/Medvedolog/luci-app-telemt/releases">LuCI Releases</a>.</small></p>
</blockquote>

<table width="100%">
  <tr>
    <th width="50%">🇷🇺 Русский</th>
    <th width="50%">🇬🇧 English</th>
  </tr>
  <tr>
    <td valign="top">
      Веб-интерфейс (LuCI) для управления продвинутым MTProto прокси <a href="https://github.com/telemt/telemt">Telemt</a> на маршрутизаторах OpenWrt.<br><br>
      С версии 3.3.x проект перешел на независимую сервисную архитектуру. Пакет работает как умный генератор конфигурации <code>telemt.toml</code> и надежно управляет жизненным циклом демона через подсистему <code>procd</code>, взаимодействуя с ядром через новый <b>Control API v1</b>.<br><br>
      Реализована полноценная панель управления (Dashboard) с живой статистикой трафика, управлением квотами пользователей (без разрыва соединений), мониторингом DPI-сканеров и встроенным Telegram-ботом.
      <br><br>
      <b>Раздельная архитектура</b> — три независимых компонента:
      <ul>
        <li><b><a href="https://github.com/Medvedolog/telemt_owrt">telemt_owrt</a></b> — Headless ядро: Rust-бинарник MTProto прокси + init.d бэкенд (генерация TOML, lifecycle через procd)</li>
        <li><b>luci-app-telemt</b> — Веб-интерфейс LuCI: CBI-модель, Zero-CORS API proxy, Diagnostics dashboard</li>
        <li><b><a href="https://github.com/Medvedolog/telemt-bot">telemt-bot</a></b> — Telegram-бот на чистом BusyBox ash (POSIX sh): 0 зависимостей, 3–5 MB RAM, 3-tier failover (SOCKS→Direct→Emergency), inline keyboards, edit-in-place, health daemon. Работает на любом OpenWrt от MIPS до aarch64.</li>
      </ul>
      Каждый компонент устанавливается отдельным IPK/APK, имеет свой lifecycle и может работать автономно.
      <br><br>
      📖 <b>Архитектура проекта:</b> Подробное описание логики работы модулей и процесса инсталляции доступно в <a href="STRUCTURE_RUS.md">STRUCTURE_RUS.md</a>.
      <br><br>
      <b>Требования:</b>
      <ul><li><b>Сеть:</b> Белый уличный статический или динамический IP адрес
        <li><b>ОС:</b> Подписанные пакеты RC1: OpenWrt 24.10 (IPK) и 25.12 (APK)</li>
        <li><b>Зависимости:</b> <code>luci-base</code>, <code>luci-compat</code>, <code>ca-bundle</code>, <code>qrencode</code>, <code>curl</code> (для QR-кодов)</li>
        <li><b>Движок:</b> бинарный файл <code>telemt</code> <b>версии 3.5.16 (RC1)</b> (<a href="https://github.com/Medvedolog/telemt_owrt/releases">Скачать telemt ядро</a>).</li>
      </ul>
      <b>Ключевые возможности:</b>
      <ul>
        <li><b>Zero-Downtime Hot-Reload:</b> Обновление лимитов и добавление пользователей на лету без перезапуска процесса и разрыва текущих сессий.</li>
        <li><b>Автономный <a href="https://github.com/Medvedolog/telemt-bot">Telegram-бот</a>:</b> Sidecar на чистом BusyBox ash — управление прокси, создание юзеров, алерты, адаптивный Runtime Info — прямо со смартфона. 3-tier failover SOCKS→Direct→Emergency.</li>
        <li><b>Умный Firewall и Жизненный цикл:</b> Атомарная генерация TOML, Graceful shutdown (сохранение статистики при рестарте) и авто-открытие портов в RAM.</li>
        <li><b>Продвинутая Диагностика:</b> Раздельные бейджи маршрутизации (TG PATH / EGRESS), консоль <i>Runtime Info</i>, мониторинг уникальных IP пользователей, пинг до DC Telegram через каскады.</li>
        <li><b>Self-Stealth:</b> Переадресация DPI-сканеров на локальный веб-сервер (uhttpd/nginx) с настоящим сертификатом. Настраивается через <code>mask_host</code> / <code>mask_port</code>.</li>
        <li><b>Управление базой:</b> Экспорт и импорт пользователей списком через CSV-файлы прямо в браузере.</li>
        <li><b>Маскировка:</b> Нативная поддержка PROXY protocol (для Nginx/HAProxy), Shadowsocks upstream и генерация FakeTLS ссылок (QR-коды).</li>
        <li><b>Внешний доступ к метрикам и API:</b> Настраиваемые bind-адреса (<code>metrics_listen_addr</code> / <code>api_listen_addr</code>) — Loopback или All interfaces. По умолчанию loopback; доступ наружу ограничен whitelist.</li>
        <li><b>Тюнинг под DPI:</b> Глобальный <code>client_mss</code> (клампинг TCP MSS, пресеты <code>tspu</code>/<code>extreme-low</code>) и динамическая SNI-маскировка (<code>mask_dynamic</code>) — помогает пробивать TSPU-блокировки.</li>
        <li><b>Честная диагностика связи:</b> Статус апстримов по реальной достижимости DC (OK / DEGRADED), бейдж TG Path различает прямой и проксированный трафик, кнопка прямой пробы DC с роутера в обход метрик.</li>
      </ul>
    </td>
    <td valign="top">
      A powerful LuCI web interface for managing the <a href="https://github.com/telemt/telemt">Telemt</a> MTProto proxy on OpenWrt routers.<br><br>
      Starting with v3.3.x, the project embraces a <b>micro-service architecture</b>. This package acts as a smart configuration generator for <code>telemt.toml</code> and bulletproof lifecycle manager via <code>procd</code>, communicating with the core engine through the new <b>Control API v1</b>.<br><br>
      It features a full dashboard with live traffic statistics, zero-downtime quota management, DPI scanner monitoring, and an integrated Telegram Bot sidecar.
      <br><br>
      <b>Micro-service architecture</b> — three independent components:
      <ul>
        <li><b><a href="https://github.com/Medvedolog/telemt_owrt">telemt_owrt</a></b> — Headless core: Rust MTProto proxy binary + init.d backend (TOML generation, procd lifecycle)</li>
        <li><b>luci-app-telemt</b> — LuCI web interface: CBI model, Zero-CORS API proxy, Diagnostics dashboard</li>
        <li><b><a href="https://github.com/Medvedolog/telemt-bot">telemt-bot</a></b> — Telegram bot in pure BusyBox ash (POSIX sh): zero dependencies, 3–5 MB RAM, 3-tier failover (SOCKS→Direct→Emergency), inline keyboards, edit-in-place, health daemon. Runs on any OpenWrt from MIPS to aarch64.</li>
      </ul>
      Each component ships as a separate IPK/APK, has its own lifecycle, and can run standalone.
      <br><br>
      📖 <b>Project Architecture:</b> For an in-depth look at module workflows and the installation process, see <a href="STRUCTURE.md">STRUCTURE.md</a>.
      <br><br>
      <b>Requirements:</b>
      <ul>
        <li><b>OS:</b> Signed RC1 packages: OpenWrt 24.10 (IPK) and 25.12 (APK)</li>
        <li><b>Dependencies:</b> <code>luci-base</code>, <code>luci-compat</code>, <code>ca-bundle</code>, <code>qrencode</code>, <code>curl</code> (for QR generation)</li>
        <li><b>Engine:</b> <code>telemt</code> binary <b>version 3.5.16 (RC1)</b> (<a href="https://github.com/Medvedolog/telemt_owrt/releases">Download core</a>).</li>
      </ul>
      <b>Key Features:</b>
      <ul>
        <li><b>Zero-Downtime Hot-Reload:</b> Update quotas, add or remove users on the fly without restarting the daemon or dropping active connections.</li>
        <li><b>Autonomous <a href="https://github.com/Medvedolog/telemt-bot">Telegram Bot</a>:</b> Pure BusyBox ash sidecar — proxy management, user CRUD, alerts, adaptive Runtime Info — from your phone. 3-tier failover SOCKS→Direct→Emergency.</li>
        <li><b>Bulletproof Lifecycle:</b> Atomic TOML generation, graceful shutdowns (zero traffic loss), and smart RAM-based port forwarding.</li>
        <li><b>Advanced Diagnostics:</b> Independent routing badges (TG PATH / EGRESS), <i>Runtime Info</i> console, unique IP tracking per user, per-DC latency through cascades.</li>
        <li><b>Self-Stealth:</b> Redirect DPI scanners to a local web server (uhttpd/nginx) with a real certificate. Configurable via <code>mask_host</code> / <code>mask_port</code>.</li>
        <li><b>Database Management:</b> Bulk export and import users using CSV files directly from the browser.</li>
        <li><b>Stealth:</b> Native PROXY protocol support (for HAProxy/Nginx), Shadowsocks upstream, and one-click FakeTLS link/QR-code generation.</li>
        <li><b>External Metrics &amp; API access:</b> Configurable bind addresses (<code>metrics_listen_addr</code> / <code>api_listen_addr</code>) — Loopback or All interfaces. Defaults to loopback; external access is whitelist-gated.</li>
        <li><b>DPI Tuning:</b> Global <code>client_mss</code> (TCP MSS clamp, presets <code>tspu</code>/<code>extreme-low</code>) and dynamic SNI masking (<code>mask_dynamic</code>) to help punch through TSPU-style blocking.</li>
        <li><b>Honest connectivity diagnostics:</b> Upstream status reflects real DC reachability (OK / DEGRADED), the TG Path badge distinguishes direct vs proxied traffic, and an on-router DC probe button checks reachability bypassing the metrics API.</li>
      </ul>
    </td>
  </tr>
</table>

<br>

<h2 align="center">📦 Установка / Installation</h2>

В связи с переходом на микросервисную архитектуру, сначала необходимо установить ядро (`telemt_owrt`), а затем данный веб-интерфейс (`luci-app-telemt`).

**Для OpenWrt 24.10 (через opkg):**
```bash
opkg update
opkg install ./luci-app-telemt_3.5.16-r1_all.ipk
```

**Для OpenWrt 25.12 (через apk):**
```bash
apk update
apk add --allow-untrusted ./luci-app-telemt-3.5.16-r1.apk
```

<br>

<p align="center">📋 История изменений: <a href="CHANGELOG.md">CHANGELOG.md</a> · <a href="https://github.com/Medvedolog/luci-app-telemt/releases">GitHub Releases</a></p>

<h2 align="center">🖼️ Скриншоты интерфейса / Screenshots</h2>

<table width="100%" style="border-collapse: collapse; border: none;">
  <tr>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>General Settings & Dashboard</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/ee849552-1648-48ed-a328-b8c108dd888c" width="100%" alt="General" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>Diagnostics & TG Path Matrix</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/0f4bb46b-f1d8-4bd7-9d90-880ba68180a4" width="100%" alt="Diagnostics" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>Users Management & Hot-Reload</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/4beb9367-013c-47dd-818f-07cea41cda6b" width="100%" alt="Users" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>Telegram Bot</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/e0d85fd3-c213-483f-bfd6-1506c75d39c9" width="100%" alt="TG_bot" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>Upstreams (Cascades)</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/5fb6b11d-1f45-461c-9b30-ce8ff83421b0" width="100%" alt="Upstreams" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>Advanced Tuning and ME</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/9614f4ff-2b08-4e4a-81e4-daa950f41bb5" width="100%" alt="Advanced" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
  </tr>
</table>
<br>
<p align="center">
  <br>
  Создано медведями-вайберами со слезами и горшочком мёда для экосистемы OpenWrt (21.02 — 25.x) 🚀🐻🍯
