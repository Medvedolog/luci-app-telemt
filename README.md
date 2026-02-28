<h2 align="center">🌌 luci-app-telemt - OpenWrt Web Interface for telemt MTProxy service</h2>
   <br>
<table width="100%">
  <tr>
    <th width="50%">🇷🇺 Русский</th>
    <th width="50%">🇬🇧 English</th>
  </tr>
  <tr>
    <td valign="top">
      Веб-интерфейс (LuCI) для управления продвинутым MTProto прокси <a href="https://github.com/telemt/telemt">Telemt</a> на маршрутизаторах OpenWrt.<br><br>
      Пакет работает как умный генератор файла конфигурации <code>telemt.toml</code> и управляет жизненным циклом демона через подсистему <code>procd</code>.<br>
      Реализована полноценная панель управления (Dashboard) с отображением статуса процесса, живой статистикой трафика, управлением квотами пользователей и автоматическим открытием портов.  
      <br><br>
      📖 <b>Архитектура проекта:</b> Подробное описание логики работы модулей и процесса инсталляции доступно в <a href="STRUCTURE_RUS.md">STRUCTURE_RUS.md</a>.
      <br><br>
      <b>Требования:</b>
      <ul>
        <li><b>ОС:</b> OpenWrt 21.02 — 25.xx (полная поддержка VDOM)</li>
        <li><b>Зависимости:</b> <code>luci-base</code>, <code>luci-compat</code>, <code>ca-bundle</code>, <code>qrencode</code> (для генерации QR-кодов)</li>
        <li><b>Движок:</b> бинарный файл <code>telemt</code> <b>версии 3.1.3+</b> (<a href="https://github.com/Medvedolog/telemt/releases">Скачать релизы</a>).</li>
      </ul>
      <b>Ключевые возможности:</b>
      <ul>
        <li><b>Строгое соответствие telemt 3.1.X:</b> Генератор формирует актуальеный "плоский" TOML, с нормализацией IP/CIDR-сетей для Prometheus метрик и валидацией SOCKS5-апстримов.</li>
        <li><b>Умный Firewall (Magic):</b> Автоматическое открытие портов в оперативной памяти средствами <code>procd</code> без захламления основного конфига Firewall, проверка статуса порта</li>
        <li><b>Пользователи и Квоты:</b> Индивидуальные лимиты по трафику (GB), количеству сессий (TCP Conns), числу уникальных IP и дате истечения подписки.</li>
        <li><b>Живая статистика:</b> Встроенный парсер Prometheus-метрик. Показывает текущий онлайн, скорость и суммарный трафик по каждому юзеру. Данные сохраняются при перезагрузке сервиса.</li>
        <li><b>Управление базой:</b> Экспорт и импорт пользователей списком через CSV-файлы прямо в браузере.</li>
        <li><b>Удобство:</b> Генерация FakeTLS ссылок (в т.ч. QR-кодов) в один клик с полуавтоматическим определением WAN IP.</li>
      </ul>
      <b>Поддерживаемые секции TOML:</b>
      <ul>
        <li><code>[general]</code>: Режимы (tls, secure, classic), продвинутый Middle-End Proxy, авто-деградация и спонсорский <code>ad_tag</code>.</li>
        <li><code>[network]</code>: Современная подсистема STUN (массив серверов, TCP fallback) и выбор предпочтительного протокола (IPv4/IPv6).</li>
        <li><code>[server]</code>: Назначение портов (в т.ч. метрик), плоский формат <code>listen_addr</code>, <code>announce_ip</code>.</li>
        <li><code>[censorship]</code> & <code>[timeouts]</code>: Тонкая настройка таймаутов, длина FakeTLS сертификатов, <code>replay_window_secs</code> и <code>mask_proxy_protocol</code> (для HAProxy/Nginx).</li>
        <li><code>[upstreams]</code>: Выбор маршрутизации (Direct или SOCKS5 с авторизацией).</li>
      </ul>
    </td>
    <td valign="top">
      A powerful LuCI web interface for managing the <a href="https://github.com/telemt/telemt">Telemt</a> MTProto proxy on OpenWrt routers.<br><br>
      This package acts as a smart configuration generator for <code>telemt.toml</code> and manages the daemon's lifecycle via the <code>procd</code> init system.<br>
      It features a full dashboard with process status, live traffic statistics, user quota management, and automatic port forwarding.
      <br><br>
      📖 <b>Project Architecture:</b> For an in-depth look at module workflows and the installation process, see <a href="STRUCTURE.md">STRUCTURE.md</a>.
      <br><br>
      <b>Requirements:</b>
      <ul>
        <li><b>OS:</b> OpenWrt 21.02 — 25.xx (full VDOM compatibility)</li>
        <li><b>Dependencies:</b> <code>luci-base</code>, <code>luci-compat</code>, <code>ca-bundle</code>, <code>qrencode</code> (for QR generation)</li>
        <li><b>Engine:</b> <code>telemt</code> binary <b>version 3.1.3+</b> (<a href="https://github.com/Medvedolog/telemt/releases">Download releases</a>).</li>
      </ul>
      <b>Key Features:</b>
      <ul>
        <li><b>Strict 3.1.3 Compliance:</b> Generates perfectly modern, flat TOML files without deprecated arrays, featuring smart IP/CIDR normalization for Prometheus and strict SOCKS5 upstream validation.</li>
        <li><b>Smart Firewall (Magic):</b> Automatically opens necessary ports in RAM via the <code>procd</code> API without cluttering your main firewall rules.</li>
        <li><b>Users & Quotas:</b> Set individual limits for data usage (GB), max TCP connections, max unique IPs, and subscription expiration dates.</li>
        <li><b>Live Statistics:</b> Built-in Prometheus metrics parser. Displays online status, bandwidth, and total traffic per user. Stats survive service restarts.</li>
        <li><b>Database Management:</b> Bulk export and import users using CSV files directly from the browser.</li>
        <li><b>Convenience:</b> One-click FakeTLS link and QR-code generation with semi-automatic WAN IP detection.</li>
      </ul>
      <b>Supported TOML Sections:</b>
      <ul>
        <li><code>[general]</code>: Protocol modes (tls, secure, classic), advanced Middle-End Proxy tuning, auto-degradation, and <code>ad_tag</code>.</li>
        <li><code>[network]</code>: Modernized STUN subsystem (server arrays, TCP fallback) and preferred IP protocol selection (IPv4/IPv6).</li>
        <li><code>[server]</code>: Port binding, flat <code>listen_addr</code> formats, metrics whitelist, and <code>announce_ip</code>.</li>
        <li><code>[censorship]</code> & <code>[timeouts]</code>: Timeout adjustments, FakeTLS certificate tuning, <code>replay_window_secs</code>, and <code>mask_proxy_protocol</code> (for HAProxy/Nginx setups).</li>
        <li><code>[upstreams]</code>: Routing selection (Direct or SOCKS5 with authentication).</li>
      </ul>
    </td>
  </tr>
</table>  <br><br>
<h2 align="center">🖼️ Interface Screenshots</h2>

<table width="100%" style="border-collapse: collapse; border: none;">
  <tr>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>General Settings</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/4ef2530a-36d1-4722-b7b0-d223914f2579" width="100%" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>Advanced Tuning and ME</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/32e216d6-a46e-4485-b4e8-a20d9b114692" width="100%" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>Users Management and Dash</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/540a81b8-de08-4383-a906-79a3056caeb6" width="100%" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
    <td width="50%" valign="top" align="center" style="border: none; padding: 10px;">
      <small><b>Diagnostic LOG</b></small><br><br>
      <img src="https://github.com/user-attachments/assets/e064960a-2c28-4ca0-aee2-bd5e56943544" width="100%" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
    </td>
  </tr>
</table>
