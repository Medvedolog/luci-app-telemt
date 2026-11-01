#!/bin/sh
# Package-specific assertions against the built IPK. APK and IPK are produced from
# the same staged tree; owfeed itself validates both container formats.
set -eu
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/control" "$work/data"

ipk=$(find dist/all -maxdepth 1 -type f -name 'luci-app-telemt_*.ipk' | head -n1)
[ -n "$ipk" ] || { echo "IPK artifact not found" >&2; exit 1; }

tar xzf "$ipk" -C "$work"
tar xzf "$work/control.tar.gz" -C "$work/control"
tar xzf "$work/data.tar.gz" -C "$work/data"

echo "--- control ---"
cat "$work/control/control"

for f in \
    ./usr/lib/lua/luci/controller/telemt.lua \
    ./usr/lib/lua/luci/model/cbi/telemt.lua \
    ./usr/lib/lua/luci/model/cbi/telemt_legacy.lua \
    ./usr/lib/lua/luci/model/cbi/telemt_memory_budget.lua \
    ./usr/lib/lua/luci/model/cbi/telemt_users_web.lua \
    ./usr/lib/lua/luci/model/cbi/telemt_web.lua \
    ./usr/share/luci/menu.d/luci-app-telemt.json \
    ./usr/share/rpcd/acl.d/luci-app-telemt.json
do
    [ -f "$work/data/$f" ] || { echo "missing from package: $f" >&2; exit 1; }
done

# The telemt core package is the sole owner of the UCI config.
[ ! -e "$work/data/etc/config/telemt" ] || { echo "unexpected /etc/config/telemt in LuCI package" >&2; exit 1; }
if [ -f "$work/control/conffiles" ] && grep -qx '/etc/config/telemt' "$work/control/conffiles"; then
    echo "/etc/config/telemt unexpectedly declared as conffile" >&2; exit 1
fi

for s in postinst prerm postrm; do
    [ -f "$work/control/$s" ] || { echo "maintainer script missing: $s" >&2; exit 1; }
done

deps=$(sed -n 's/^Depends:[[:space:]]*//p' "$work/control/control" | tr ',' '\n' | sed 's/[[:space:]]//g;s/[[:space:](].*$//' | sed '/^$/d' | sort -u)
expected=$(printf '%s\n' libc luci-base luci-compat qrencode ca-bundle curl | sort -u)
[ "$deps" = "$expected" ] || {
    echo "dependency mismatch" >&2
    echo "expected:" >&2; printf '%s\n' "$expected" >&2
    echo "actual:" >&2; printf '%s\n' "$deps" >&2
    exit 1
}

echo "package checks passed: $ipk"
