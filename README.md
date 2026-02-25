# luci-app-telemt - OpenWrt Web Interface for telemt MTProxy service


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
      <b>Требования:</b>
      <ul>
        <li><b>ОС:</b> OpenWrt 21.02 — 25.xx (полная поддержка VDOM)</li>
        <li><b>Зависимости:</b> <code>luci-base</code>, <code>luci-compat</code>, <code>ca-bundle</code>, <code>qrencode</code> (для генерации QR-кодов)</li>
        <li><b>Движок:</b> бинарный файл <code>telemt</code> <b>версии 3.0.15 или 3.1.0 LTS</b>.</li>[https://github.com/Medvedolog/telemt/releases]
      </ul>
      <b>Ключевые возможности:</b>
      <ul>
        <li><b>Умный Firewall (Magic):</b> Автоматическое открытие портов в оперативной памяти средствами <code>procd</code> без захламления основного конфига Firewall.</li>
        <li><b>Пользователи и Квоты:</b> Индивидуальные лимиты по трафику (GB), количеству сессий (TCP Conns), числу уникальных IP и дате истечения подписки.</li>
        <li><b>Живая статистика:</b> Встроенный парсер Prometheus-метрик. Показывает текущий онлайн, скорость и суммарный трафик по каждому юзеру. Данные сохраняются при перезагрузке сервиса.</li>
        <li><b>Управление базой:</b> Экспорт и импорт пользователей списком через CSV-файлы прямо в браузере.</li>
        <li><b>Удобство:</b> Генерация FakeTLS ссылок (в т.ч. QR-кодов) в один клик с полуавтоматическим определением WAN IP.</li>
      </ul>
      <b>Поддерживаемые секции TOML:</b>
      <ul>
        <li><code>[general]</code>: Режимы (tls, secure, classic), продвинутый Middle-End Proxy (warm standby, hardswap, pool size), авто-деградация (auto-degradation), спонсорский <code>ad_tag</code>.</li>
        <li><code>[server]</code>: Назначение портов (в т.ч. метрик), IPv4/IPv6, <code>announce_ip</code>.</li>
        <li><code>[timeouts]</code> & <code>[access]</code>: Тонкая настройка таймаутов, <code>replay_window_secs</code>, длина FakeTLS сертификатов (<code>fake_cert_len</code>).</li>
        <li><code>[upstreams]</code>: Выбор маршрутизации (Direct или SOCKS5 с авторизацией).</li>
      </ul>
    </td>
    <td valign="top">
      A powerful LuCI web interface for managing the <a href="https://github.com/telemt/telemt">Telemt</a> MTProto proxy on OpenWrt routers.<br><br>
      This package acts as a smart configuration generator for <code>telemt.toml</code> and manages the daemon's lifecycle via the <code>procd</code> init system.<br>
      It features a full dashboard with process status, live traffic statistics, user quota management, and automatic port forwarding.
      <br><br>
      <b>Requirements:</b>
      <ul>
        <li><b>OS:</b> OpenWrt 21.02 — 25.xx (full VDOM compatibility)</li>
        <li><b>Dependencies:</b> <code>luci-base</code>, <code>luci-compat</code>, <code>ca-bundle</code>, <code>qrencode</code> (for QR generation)</li>
        <li><b>Engine:</b> <code>telemt</code> binary <b>version 3.0.15 or 3.1.0 LTS</b>.</li>[https://github.com/Medvedolog/telemt/releases]
      </ul>
      <b>Key Features:</b>
      <ul>
        <li><b>Smart Firewall (Magic):</b> Automatically opens necessary ports in RAM via the <code>procd</code> API without cluttering your main firewall rules.</li>
        <li><b>Users & Quotas:</b> Set individual limits for data usage (GB), max TCP connections, max unique IPs, and subscription expiration dates.</li>
        <li><b>Live Statistics:</b> Built-in Prometheus metrics parser. Displays online status, bandwidth, and total traffic per user. Stats survive service restarts.</li>
        <li><b>Database Management:</b> Bulk export and import users using CSV files directly from the browser.</li>
        <li><b>Convenience:</b> One-click FakeTLS link and QR-code generation with semi-automatic WAN IP detection.</li>
      </ul>
      <b>Supported TOML Sections:</b>
      <ul>
        <li><code>[general]</code>: Protocol modes (tls, secure, classic), advanced Middle-End Proxy tuning (warm standby, hardswap, pool size), auto-degradation, and <code>ad_tag</code>.</li>
        <li><code>[server]</code>: Port binding, IPv4/IPv6 listeners, metrics whitelist, and <code>announce_ip</code>.</li>
        <li><code>[timeouts]</code> & <code>[access]</code>: Timeout adjustments, <code>replay_window_secs</code>, and FakeTLS certificate tuning (<code>fake_cert_len</code>).</li>
        <li><code>[upstreams]</code>: Routing selection (Direct or SOCKS5 with authentication).</li>
      </ul>
    </td>
  </tr>
</table>
