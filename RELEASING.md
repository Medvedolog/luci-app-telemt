# Релизы luci-app-telemt через owfeed

Репозиторий собирает два нативных для OpenWrt формата из одного staged tree:

- OpenWrt 25.12+ — APKv3 (`dist/noarch/*.apk`);
- OpenWrt 24.10 — IPK (`dist/all/*.ipk`).

`owfeed` заменил nFPM. Версия релиза берётся из git tag, нормализуется до `X.Y.Z-rN`, а содержимое пакета формируется из `root/` и `scripts/` через `tools/stage.sh`. Схема повторяет `luci-app-podkop-bot`.

`/etc/config/telemt` пакетом **не** поставляется: единственный владелец UCI-конфига — ядро (`telemt`, репозиторий `telemt_owrt`).

## Однократная настройка подписей

Нужны два постоянных ключа. Их нельзя генерировать в CI на каждый релиз: feed один раз закрепляет публичный ключ автора и проверяет им все последующие релизы.

На доверенной машине с `gh` (нужны права на репозиторий):

```sh
./tools/setup-keys.sh
```

Скрипт создаст и загрузит в GitHub Secrets:

- `TELEMT_LUCI_SIGN_KEY` — EC prime256v1, подпись пакета;
- `TELEMT_LUCI_USIGN_KEY` — usign, подпись `manifest.txt` и release assets.

Приватные файлы из `keys-setup/` сохраните вне git (менеджер секретов) и удалите каталог. Публичные половины скрипт копирует в `keys/telemt-luci-sign.pub.pem` и `keys/telemt-luci-release.pub` — их нужно **закоммитить до первого тега**. Без них `release-preflight` не даст выпустить релиз. Обычный релиз не повод вращать ключи: feed закрепляет публичную половину.

## Pipeline

```text
sources -> build -> verify -> release
```

- `sources` — Lua 5.1 syntax, JSON, shell, согласованность `version.txt` и `Makefile` (`tools/check-sources.sh`);
- `build` — `tools/stage.sh`, `owfeed plan`, `owfeed check`, `owfeed build`, затем `tools/check-package.sh` смотрит внутрь собранного IPK;
- `verify` — OpenWrt userspace через `owlab`: ставит собранный пакет на 25.12.5 (APK) и 24.10.8 (IPK) и проверяет файлы;
- `release` — только для тега, после успешных build+verify: reusable workflow owfeed подписывает пакеты и manifest и публикует GitHub Release.

В build/verify секретов нет; они доступны только job `release`.

## Совместимость и стабильность версий

Стабильный LuCI-релиз выпускается только в паре с протестированным ядром той же базовой версии `X.Y.Z`. Если upstream `telemt/telemt` помечает соответствующий релиз как pre-release, OpenWrt-ядро и LuCI также должны распространяться как тестовые/pre-release и не должны попадать в стабильный feed. Прежде чем выпускать релиз, проверьте фактический статус upstream-тега, а не только номер версии.

Для парных RC используйте отдельные ветки обоих репозиториев и не переносите изменения в `main` до проверки сохранности `/etc/config/telemt`, регрессий LuCI и реальных подключений Direct/ME/WEB. Сначала публикуется ядро, потом LuCI; автоматическое прикрепление ядра (`bundle-core`) само по себе не подтверждает аппаратную совместимость.

## Создание релиза

Перед тегом версия должна совпадать в `version.txt` и `PKG_VERSION` в `Makefile`.

Тег ставьте с ревизией: `X.Y.Z-N` (например `3.5.8-2`) → пакеты `X.Y.Z-rN`. Голый `X.Y.Z` даёт `X.Y.Z-r<PKG_RELEASE>` (сейчас `-r1`).

```sh
git tag 3.5.8
git push origin 3.5.8
```

Ожидаемые assets:

```text
luci-app-telemt-3.5.8-r1.apk
luci-app-telemt_3.5.8-r1_all.ipk
manifest.txt
*.sig
```

## Парное ядро в релизе

После публикации релиза job `bundle-core` (`tools/bundle-core.sh`) берёт релиз ядра [`Medvedolog/telemt_owrt`](https://github.com/Medvedolog/telemt_owrt/releases) **той же базовой версии** и прикладывает его пакеты к релизу LuCI:

- для тега `X.Y.Z` (или `X.Y.Z-N`) выбирается самая свежая ревизия ядра среди тегов `X.Y.Z`, `X.Y.Z-2`, … (pre-release считаются, черновики нет);
- манифест ядра проверяется подписью автора ядра (`keys/telemt-core-release.pub`, id закреплён в скрипте), каждый файл сверяется с ним по размеру и sha256;
- файлы загружаются **без изменений**, с оригинальными `.sig`; манифест ядра лежит как `core-manifest.txt` (+ `.sig`), чтобы не затирать `manifest.txt` LuCI. Через owfeed-релиз LuCI ядро не пропускается: иначе оно было бы подписано ключом LuCI и попало бы в его `manifest.txt`. Заявка в owfeed-packages от этого не меняется;
- если релиза ядра с такой базовой версией ещё нет, job ничего не делает (в логе `notice`). **Поэтому релизим по очереди: сначала ядро, потом LuCI.**

Проверка без загрузки: `sh tools/bundle-core.sh 3.5.8` (нужны `owfeed`, `jq`, `curl`). Если публичный ключ ядра когда-либо будет заменён, обновите `keys/telemt-core-release.pub` и `CORE_KEY_ID` в `tools/bundle-core.sh`; `tools/check-sources.sh` следит, чтобы они совпадали. Для уже вышедшего релиза бандл можно догрузить: GitHub → Actions → **Attach core packages** → Run workflow, в поле `tag` указать тег релиза (например `3.5.8`); либо локально `UPLOAD=1 sh tools/bundle-core.sh 3.5.8`.

## Добавление в owfeed-packages

Intake — signed upstream manifest: feed ничего не пересобирает, а забирает опубликованный пакет, проверяет manifest и подпись автора и включает те же байты в индекс. После первого подписанного релиза в PR в `owfeed/owfeed-packages` кладутся публичный ключ `keys/telemt-luci-release.pub` и `packages/luci-app-telemt/upstream.sh`:

```sh
KIND="manifest"
REPO="Medvedolog/luci-app-telemt"
VERSION="3.5.8-r1"
TAG="3.5.8"
SIG_KEY="keys/telemt-luci-release.pub"
SIG_KEY_ID="<id из usign-ключа>"
AUTO_MERGE="yes"
```

Формат intake — внешний контракт: перед PR сверьтесь с актуальным `CONTRIBUTING.md` в owfeed-packages. Лицензия: `GPL-2.0-or-later`.

## Локальная проверка

Нужны `owfeed`, доступ к `downloads.openwrt.org` и `OWFEED_SIGN_KEY` в окружении:

```sh
./tools/check-sources.sh
./tools/stage.sh 3.5.8
owfeed plan && owfeed check && owfeed build
./tools/check-package.sh
```

`dist/` — build output, в git не коммитится. `owfeed.lock` коммитится; обновлять: `owfeed lock --update`.
