#!/bin/sh
# Stage luci-app-telemt as the router filesystem consumed by owfeed/mkpkg.
#
#   tools/stage.sh [VERSION]
#
# VERSION defaults to the git tag being built, else version.txt. A tag "X.Y.Z" gives
# package version X.Y.Z-r<PKG_RELEASE>; a tag "X.Y.Z-N" gives X.Y.Z-rN.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/dist}"

if [ "$#" -gt 0 ]; then
    VERSION="$1"
elif [ "${GITHUB_REF_TYPE:-}" = "tag" ] && [ -n "${GITHUB_REF_NAME:-}" ]; then
    VERSION="$GITHUB_REF_NAME"
else
    VERSION="$(cat "$ROOT/version.txt" 2>/dev/null || echo 0.0.0)"
fi
VERSION="${VERSION#v}"

MAKE_RELEASE="$(sed -n 's/^PKG_RELEASE:=//p' "$ROOT/Makefile" | head -n1)"
case "$MAKE_RELEASE" in ''|*[!0-9]*) MAKE_RELEASE=1;; esac

case "$VERSION" in
    *-r[0-9]*) PKG_VERSION="$VERSION"; BASE_VERSION="${VERSION%-r*}" ;;
    *-[0-9]*)  BASE_VERSION="${VERSION%-*}"; PKG_VERSION="${BASE_VERSION}-r${VERSION##*-}" ;;
    *)         BASE_VERSION="$VERSION"; PKG_VERSION="${VERSION}-r${MAKE_RELEASE}" ;;
esac

# One base version everywhere: release tag, version.txt and the Makefile.
TXT_VERSION="$(tr -d '[:space:]' < "$ROOT/version.txt" 2>/dev/null || true)"
MAKE_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$ROOT/Makefile" | head -n1)"
for pair in "version.txt:$TXT_VERSION" "Makefile:$MAKE_VERSION"; do
    name=${pair%%:*}; value=${pair#*:}
    if [ -z "$value" ] || [ "$value" != "$BASE_VERSION" ]; then
        echo "version mismatch: release=$BASE_VERSION, $name=${value:-missing}" >&2
        exit 1
    fi
done

rm -rf "$OUT/root" "$OUT/scripts"
mkdir -p "$OUT/root" "$OUT/scripts"
printf '%s\n' "$PKG_VERSION" > "$OUT/VERSION"
cp -a "$ROOT/root/." "$OUT/root/"

for f in \
    usr/lib/lua/luci/controller/telemt.lua \
    usr/lib/lua/luci/model/cbi/telemt.lua \
    usr/lib/lua/luci/model/cbi/telemt_legacy.lua \
    usr/lib/lua/luci/model/cbi/telemt_memory_budget.lua \
    usr/lib/lua/luci/model/cbi/telemt_users_web.lua \
    usr/lib/lua/luci/model/cbi/telemt_web.lua \
    usr/lib/lua/luci/model/telemt_web_link.lua \
    usr/share/luci/menu.d/luci-app-telemt.json \
    usr/share/rpcd/acl.d/luci-app-telemt.json
do
    [ -f "$OUT/root/$f" ] || { echo "required payload missing: /$f" >&2; exit 1; }
    chmod 0644 "$OUT/root/$f"
done

# /etc/config/telemt belongs to the telemt core package.
[ ! -e "$OUT/root/etc/config/telemt" ] || { echo "payload must not ship /etc/config/telemt" >&2; exit 1; }

for s in preinst postinst prerm postrm; do
    src="$ROOT/scripts/$s"
    [ -f "$src" ] || continue
    sed -e '1s/^\xef\xbb\xbf//' -e 's/\r$//' "$src" > "$OUT/scripts/$s"
    chmod 0755 "$OUT/scripts/$s"
done

echo "staged luci-app-telemt $PKG_VERSION"
