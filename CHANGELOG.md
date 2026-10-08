# Changelog / История изменений

Версия пакета / package version: `X.Y.Z-rN` (`X.Y.Z` — версия LuCI-приложения, совпадает с версией ядра `telemt`, которое оно поддерживает; `rN` — ревизия упаковки).

## 3.5.14-r1 — RC preparation (unreleased, 2026-10-08)

- Align package version and WEB UI description with upstream Telemt **3.5.14**.
- When the named `telemt.general` UCI section is missing or malformed, display a clear configuration diagnostic rather than silently presenting only the Upstreams/Users tables (issue #25 candidate cause). Do not mutate UCI merely by opening LuCI.
- The matching core package restores a missing `general` section on upgrade while preserving all existing options. A wrong-type section is reported for manual review.
- No changes to the router policy for service shutdown or hot reload.


## Unreleased

**RU**
- В релиз LuCI автоматически прикладываются пакеты ядра `telemt` той же базовой версии (`tools/bundle-core.sh`): без изменений, с подписями автора ядра. Релизить нужно по очереди: сначала ядро, потом LuCI. См. [RELEASING.md](RELEASING.md).

**EN**
- A LuCI release now carries the `telemt` core packages of the same base version (`tools/bundle-core.sh`), unchanged and with the core author's signatures. Release in order: core first, then LuCI. See [RELEASING.md](RELEASING.md).

## 3.5.8-r1 — 2026-09-29

**RU**
- Требуется ядро **telemt 3.5.8+** (см. [telemt_owrt](https://github.com/Medvedolog/telemt_owrt)). Для 3.4.15–3.5.7 бейдж показывает «Limited»: Classic/DD/FakeTLS работают, WEB и sideband — нет.
- Вкладка **WEB Proxy**: диагностика `[web.debug]` — «WEB diagnostics», «Diagnostic sideband», «Capture lifecycle events» (всё выключено по умолчанию; изменение перезапускает Telemt).
- Пакеты собираются через **owfeed**: IPK (24.10) и APKv3 (25.12), `noarch`, проверка установки на реальном OpenWrt (`owlab`), подписанный релиз с `manifest.txt`. nFPM больше не используется. См. [RELEASING.md](RELEASING.md).
- Раскладка репозитория: `usr/` → `root/usr/`, добавлены `Makefile`, `owfeed.yml`, `tools/`. Лицензия GPL-2.0-or-later (`LICENSE`).
- Ссылки на ядро ведут на `Medvedolog/telemt_owrt`.

**EN**
- Requires **telemt core 3.5.8+** (see [telemt_owrt](https://github.com/Medvedolog/telemt_owrt)). For 3.4.15–3.5.7 the badge reads "Limited": Classic/DD/FakeTLS keep working, WEB and sideband do not.
- **WEB Proxy** tab: `[web.debug]` diagnostics — "WEB diagnostics", "Diagnostic sideband", "Capture lifecycle events" (all off by default; changing them restarts Telemt).
- Packages are built with **owfeed**: IPK (24.10) and APKv3 (25.12), `noarch`, install verified on real OpenWrt (`owlab`), signed release with `manifest.txt`. nFPM is no longer used. See [RELEASING.md](RELEASING.md).
- Repository layout: `usr/` → `root/usr/`; added `Makefile`, `owfeed.yml`, `tools/`. Licence GPL-2.0-or-later (`LICENSE`).
- Links to the core now point to `Medvedolog/telemt_owrt`.
