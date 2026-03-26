<h1 align="center">🌌 luci-app-telemt</h1>
<p align="center"><b>OpenWrt Web Interface for Telemt MTProxy service</b></p>
<br>

<table width="100%">
  <tr>
    <th width="50%">🇷🇺 Русский</th>
    <th width="50%">🇬🇧 English</th>
  </tr>
  <tr>
    <td valign="top">
      Веб-интерфейс (LuCI) для управления продвинутым MTProto прокси <a href="https://github.com/telemt/telemt">Telemt</a> на маршрутизаторах OpenWrt.<br><br>
      С версии 3.3.x проект перешел на <b>микросервисную архитектуру</b>. Пакет работает как умный генератор конфигурации <code>telemt.toml</code> и надежно управляет жизненным циклом демона через подсистему <code>procd</code>, взаимодействуя с ядром через новый <b>Control API v1</b>.<br><br>
      Реализована полноценная панель управления (Dashboard) с живой статистикой трафика, управлением квотами пользователей (без разрыва соединений), мониторингом DPI-сканеров и встроенным Telegram-ботом.
      <br><br>
      <b>Микросервисная архитектура</b> — три независимых компонента:
      <ul>
        <li><b><a href="https://github.com/afadillo-a11y/telemt_wrt">telemt_wrt</a></b> — Headless ядро: Rust-бинарник MTProto прокси + init.d бэкенд (генерация TOML, lifecycle через procd)</li>
        <li><b>luci-app-telemt</b> — Веб-интерфейс LuCI: CBI-модель, Zero-CORS API proxy, Diagnostics dashboard</li>
        <li><b><a href="https://github.com/Medvedolog/telemt-bot">telemt-bot</a></b> — Telegram-бот на чистом BusyBox ash (POSIX sh): 0 зависимостей, 3–5 MB RAM, 3-tier failover (SOCKS→Direct→Emergency), inline keyboards, edit-in-place, health daemon. Работает на любом OpenWrt от MIPS до aarch64.</li>
      </ul>
      Каждый компонент устанавливается отдельным IPK/APK, имеет свой lifecycle и может работать автономно.
      <br><br>
      📖 <b>Архитектура проекта:</b> Подробное описание логики работы модулей и процесса инсталляции доступно в <a href="STRUCTURE_RUS.md">STRUCTURE_RUS.md</a>.
      <br><br>
      <b>Требования:</b>
      <ul>
        <li><b>ОС:</b> OpenWrt 21.02 — 25.xx (полная поддержка VDOM и APK-пакетов)</li>
        <li><b>Зависимости:</b> <code>luci-base</code>, <code>luci-compat</code>, <code>ca-bundle</code>, <code>qrencode</code> (для QR-кодов)</li>
        <li><b>Движок:</b> бинарный файл <code>telemt</code> <b>версии 3.3.15+</b> (<a href="https://github.com/afadillo-a11y/telemt_wrt/releases">Скачать telemt ядро</a>).</li>
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
      </ul>
    </td>
    <td valign="top">
      A powerful LuCI web interface for managing the <a href="https://github.com/telemt/telemt">Telemt</a> MTProto proxy on OpenWrt routers.<br><br>
      Starting with v3.3.x, the project embraces a <b>micro-service architecture</b>. This package acts as a smart configuration generator for <code>telemt.toml</code> and bulletproof lifecycle manager via <code>procd</code>, communicating with the core engine through the new <b>Control API v1</b>.<br><br>
      It features a full dashboard with live traffic statistics, zero-downtime quota management, DPI scanner monitoring, and an integrated Telegram Bot sidecar.
      <br><br>
      <b>Micro-service architecture</b> — three independent components:
      <ul>
        <li><b><a href="https://github.com/afadillo-a11y/telemt_wrt">telemt_wrt</a></b> — Headless core: Rust MTProto proxy binary + init.d backend (TOML generation, procd lifecycle)</li>
        <li><b>luci-app-telemt</b> — LuCI web interface: CBI model, Zero-CORS API proxy, Diagnostics dashboard</li>
        <li><b><a href="https://github.com/Medvedolog/telemt-bot">telemt-bot</a></b> — Telegram bot in pure BusyBox ash (POSIX sh): zero dependencies, 3–5 MB RAM, 3-tier failover (SOCKS→Direct→Emergency), inline keyboards, edit-in-place, health daemon. Runs on any OpenWrt from MIPS to aarch64.</li>
      </ul>
      Each component ships as a separate IPK/APK, has its own lifecycle, and can run standalone.
      <br><br>
      📖 <b>Project Architecture:</b> For an in-depth look at module workflows and the installation process, see <a href="STRUCTURE.md">STRUCTURE.md</a>.
      <br><br>
      <b>Requirements:</b>
      <ul>
        <li><b>OS:</b> OpenWrt 21.02 — 25.xx (full VDOM and APK package support)</li>
        <li><b>Dependencies:</b> <code>luci-base</code>, <code>luci-compat</code>, <code>ca-bundle</code>, <code>qrencode</code> (for QR generation)</li>
        <li><b>Engine:</b> <code>telemt</code> binary <b>version 3.3.15+</b> (<a href="https://github.com/afadillo-a11y/telemt_wrt/releases">Download core</a>).</li>
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
      </ul>
    </td>
  </tr>
</table>

<br>

<h2 align="center">📦 Установка / Installation</h2>

В связи с переходом на микросервисную архитектуру, сначала необходимо установить ядро (`telemt_wrt`), а затем данный веб-интерфейс (`luci-app-telemt`).

**Для OpenWrt 21.02 — 24.10 (через opkg):**
```bash
opkg update
opkg install luci-app-telemt_3.3.30_all.ipk
```

**Для OpenWrt 25.xx и новее (через apk):**
```bash
apk update
apk add --allow-untrusted luci-app-telemt_3.3.30_noarch.apk
```

<br>

<h2 align="center">📋 История главных релизов / Changelog</h2>

<table width="100%">
  <tr>
    <th width="15%">Версия</th>
    <th width="85%">Изменения / Highlights</th>
  </tr>
  <tr>
    <td valign="top"><b>3.3.30</b><br><small>Release Candidate</small></td>
    <td valign="top">
      <b>Self-Stealth, Shadowsocks Upstream, API Integration & Stability Hardening</b><br>
      <ul>
        <li><b>Self-Stealth:</b> Новые поля <code>mask_port</code> и <code>mask_host</code> — перенаправление TLS-сканеров на локальный веб-сервер с настоящим сертификатом.</li>
        <li><b>Shadowsocks upstream:</b> Новый тип в Protocol dropdown с полем SIP002 URL. Требует <code>use_middle_proxy = false</code>.</li>
        <li><b>API Integration:</b> Per-DC latency в карточке Upstreams, IP-тултипы на вкладке Users, health-бейджи на вкладке Upstreams, Live connections + Users online + Unique IPs.</li>
        <li><b>Formatted Beobachten:</b> Кнопка Scanner выводит категоризированный список DPI-сканеров с IP и счётчиками.</li>
        <li><b>Cascade UX:</b> Заголовок показывает протокол (<code>socks5://addr</code>). Health badge виден при свёрнутой карточке. Динамический placeholder для Address.</li>
        <li><b>PID Stability:</b> Null-byte safe <code>/proc/cmdline</code>, метрики (9092) без PID, frontend state machine (RUNNING / STARTING / PID UNKNOWN / STOPPED).</li>
        <li><b>Polling fix:</b> <code>stopTimers()</code> убран из раннего выхода — polling не умирает при медленном рендере.</li>
        <li><b>Lua safety:</b> Regex с <code>[[</code>/<code>]]</code> переписаны через <code>String.fromCharCode()</code>. ES2018 <code>/is</code> → совместимый <code>/i</code>.</li>
        <li><b>Dark theme:</b> Заменены ~15 hardcoded серых цветов на <code>inherit</code> / <code>opacity</code>.</li>
        <li><b>IPK packaging:</b> <code>nfpm.yaml</code> ставит <code>/etc/config/telemt</code>. Postinst: fallback-конфиг + полная очистка кеша (21.x–25.x).</li>
        <li><b>Init.d (зеркально):</b> <code>mask_port</code>/<code>mask_host</code> из UCI → TOML. Shadowsocks <code>url</code> в upstream handler. <code>data_path</code> (gated ≥ 3.3.19).</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td valign="top"><b>3.3.26</b></td>
    <td valign="top">
      <b>Глобальная переработка диагностики, поддержка OpenWrt 25+ и укрепление жизненного цикла (Lifecycle)</b><br>
      <ul>
        <li><b>Новая информационная модель:</b> Старый бейдж <code>MODE</code> разделен на два точных индикатора: <b>TG PATH</b> (Direct-DC/ME/Fallback) и <b>EGRESS</b> (Direct/SOCKS5). Правая карточка динамически адаптируется под тип апстрима.</li>
        <li><b>Консоль Runtime Info:</b> Добавлена кнопка для вывода удобочитаемой сводки о здоровье прокси, апстримах и трафике юзеров.</li>
        <li><b>Трекинг уникальных IP:</b> Вкладка пользователей теперь парсит метрики уникальных IP из Prometheus (формат <code>● 14 IP 7/10</code>).</li>
        <li><b>Укрепленный Init.d:</b> Атомарная генерация TOML (устраняет падения при hot-reload), <code>rc_procd</code> без гонки состояний, Graceful Shutdown (<code>SIGTERM</code> → <code>run_save_stats</code> → <code>SIGKILL</code>). Безопасное обнаружение PID бота.</li>
        <li><b>Очистка конфигурации:</b> Удалены 8 фантомных параметров Middle-End, которые теперь настраиваются автоматически бинарником.</li>
        <li><b>OpenWrt 25+ Compat:</b> Инъекция имени пользователя в DOM новой архитектуры LuCI. Исправлена верстка и цветовые пороги памяти.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td valign="top"><b>3.3.16</b></td>
    <td valign="top">
      <b>Исправления безопасности и полировка UI</b><br>
      <ul>
        <li>Исправлен серверный механизм валидации CSRF токенов, ломавший сохранение на старых версиях OpenWrt.</li>
        <li>Кнопки управления сервисом переведены в режим "тонких оберток", вызывающих напрямую <code>init.d</code> скрипт.</li>
        <li>Добавлен визуальный статус <code>STARTING... / STOPPING...</code> с защитой от двойного клика.</li>
        <li>Реорганизован порядок вкладок и добавлена выделенная панель кнопок для работы с CSV базой пользователей.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td valign="top"><b>3.3.10</b></td>
    <td valign="top">
      <b>Переход на микросервисы и пакеты APK</b><br>
      <ul>
        <li>Полное разделение монолита на Headless Core, WebUI и Telemt Bot.</li>
        <li>Интеграция nFPM для автоматической генерации современных <code>.apk</code> пакетов (для OpenWrt 25+).</li>
        <li>Переход на высокоскоростной RAM Ring-Buffer для карантина сканеров.</li>
        <li>Внедрение мягких зависимостей: WebUI корректно работает и предупреждает, если ядро не установлено.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td valign="top"><b>3.2.1</b></td>
    <td valign="top">
      <b>Control API v1, Hot-Reload и Telegram Bot</b><br>
      <ul>
        <li>Внедрен <b>Control Plane HTTP API v1</b>. Добавление пользователей и изменение квот теперь происходит <i>на лету</i> (Zero-Downtime Hot-Reload).</li>
        <li>Встроен легковесный <code>telemt_bot</code> для автономного управления роутером через Telegram (создание юзеров, графики нагрузки).</li>
        <li>Порты разнесены аппаратно: <code>9092</code> для метрик Prometheus, <code>9091</code> для REST API.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td valign="top"><b>pre-LTS 3.1.3</b></td>
    <td valign="top">
      <b>Поддержка PROXY protocol и Smart STUN Fallback</b><br>
      <ul>
        <li>Внедрена поддержка <code>mask_proxy_protocol</code> (v1/v2) для работы за HAProxy/Nginx.</li>
        <li>Устранен баг с потерей статистики трафика при нажатии "Save & Apply". Установлен синхронный дамп метрик из RAM на диск перед перезапуском демона.</li>
        <li>Добавлен умный фоллбек STUN для обхода строгих NAT мобильных провайдеров.</li>
      </ul>
    </td>
  </tr>
</table>

<br>

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
      <small><b>Advanced Tuning and ME</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/9614f4ff-2b08-4e4a-81e4-daa950f41bb5" width="100%" alt="Advanced" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>Users Management & Hot-Reload</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/44e4590b-733c-44f9-abc1-806c8dc3ae70" width="100%" alt="Users" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>Upstreams (Cascades)</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/5fb6b11d-1f45-461c-9b30-ce8ff83421b0" width="100%" alt="Upstreams" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>Telegram Bot</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/e0d85fd3-c213-483f-bfd6-1506c75d39c9" width="100%" alt="TG_bot" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
  </tr>
</table>
<br>
<p align="center">
  Создано медведями-вайберами со слезами и горшочком мёда для экосистемы OpenWrt (21.02 — 25.x) 🚀🐻🍯
</p>
