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
        <li><b>Автономный Telegram-бот:</b> Sidecar-демон для управления прокси (создание юзеров, графики нагрузки, алерты) прямо со смартфона.</li>
        <li><b>Умный Firewall и Жизненный цикл:</b> Атомарная генерация TOML, Graceful shutdown (сохранение статистики при рестарте) и авто-открытие портов в RAM.</li>
        <li><b>Продвинутая Диагностика:</b> Раздельные бейджи маршрутизации (TG PATH / EGRESS), консоль <i>Runtime Info</i> и мониторинг уникальных IP пользователей.</li>
        <li><b>Управление базой:</b> Экспорт и импорт пользователей списком через CSV-файлы прямо в браузере.</li>
        <li><b>Маскировка:</b> Нативная поддержка PROXY protocol (для Nginx/HAProxy) и генерация FakeTLS ссылок (QR-коды).</li>
      </ul>
    </td>
    <td valign="top">
      A powerful LuCI web interface for managing the <a href="https://github.com/telemt/telemt">Telemt</a> MTProto proxy on OpenWrt routers.<br><br>
      Starting with v3.3.x, the project embraces a <b>micro-service architecture</b>. This package acts as a smart configuration generator for <code>telemt.toml</code> and bulletproof lifecycle manager via <code>procd</code>, communicating with the core engine through the new <b>Control API v1</b>.<br><br>
      It features a full dashboard with live traffic statistics, zero-downtime quota management, DPI scanner monitoring, and an integrated Telegram Bot sidecar.
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
        <li><b>Autonomous Telegram Bot:</b> A standalone sidecar daemon to manage your proxy, view CPU/RAM load, and receive alerts directly from your phone.</li>
        <li><b>Bulletproof Lifecycle:</b> Atomic TOML generation, graceful shutdowns (zero traffic loss), and smart RAM-based port forwarding.</li>
        <li><b>Advanced Diagnostics:</b> Independent routing badges (TG PATH / EGRESS), <i>Runtime Info</i> console, and unique IP tracking per user.</li>
        <li><b>Database Management:</b> Bulk export and import users using CSV files directly from the browser.</li>
        <li><b>Stealth:</b> Native PROXY protocol support (for HAProxy/Nginx) and one-click FakeTLS link/QR-code generation.</li>
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
opkg install luci-app-telemt_3.3.26_all.ipk
```

**Для OpenWrt 25.xx и новее (через apk):**
```bash
apk update
apk add --allow-untrusted luci-app-telemt_3.3.26_noarch.apk
```

<br>

<h2 align="center">📋 История главных релизов / Changelog</h2>

<table width="100%">
  <tr>
    <th width="15%">Версия</th>
    <th width="85%">Изменения / Highlights</th>
  </tr>
  <tr>
    <td valign="top"><b>3.3.26</b><br><small>Latest Stable</small></td>
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
    <td valign="top"><b>3.1.2</b></td>
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
      <img src="https://github.com/user-attachments/assets/4ef2530a-36d1-4722-b7b0-d223914f2579" width="100%" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>Advanced Tuning and ME</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/32e216d6-a46e-4485-b4e8-a20d9b114692" width="100%" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>Users Management & Hot-Reload</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/540a81b8-de08-4383-a906-79a3056caeb6" width="100%" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>Diagnostics & TG Path Matrix</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/e064960a-2c28-4ca0-aee2-bd5e56943544" width="100%" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
  </tr>
</table>
<br>
<p align="center">
  Создано медведями-вайберами со слезами и горшочком мёда для экосистемы OpenWrt (21.02 — 25.x) 🚀🐻🍯
</p>
