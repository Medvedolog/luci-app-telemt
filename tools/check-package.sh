#!/bin/sh
# What `owfeed build` left in dist/, read out of the package rather than taken from
# what the build printed.
#
# The .ipk because it is a plain tar and needs no tools to open. Both containers are
# packed from the SAME staged tree by the same build, so checking one proves the
# staging.
#
# `owfeed doctor` already covers what is generic — a config file shipped without being
# declared, a version apk cannot parse, JSON and shell in the payload that do not
# parse. What is left here is specific to this package: that the four files LuCI and
# rpcd look for are present under the names they look for, and that the dependency
# list did not quietly lose an entry.
#
# luci-compat is the one that is easy to lose and hard to diagnose: without it the CBI
# page 500s on 23.05 and later, and nothing in the build says so.
set -eu
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/control" "$work/data"

tar xzf dist/all/*.ipk -C "$work"
tar xzf "$work/control.tar.gz" -C "$work/control"
tar xzf "$work/data.tar.gz" -C "$work/data"

echo "--- control ---"; cat "$work/control/control"
echo "--- payload ---"; (cd "$work/data" && find . -type f | sort)

for f in \
	./usr/lib/lua/luci/controller/telemt.lua \
	./usr/lib/lua/luci/model/cbi/telemt.lua \
	./usr/share/luci/menu.d/luci-app-telemt.json \
	./usr/share/rpcd/acl.d/luci-app-telemt.json \
	./etc/config/telemt
do
	[ -f "$work/data/$f" ] || { echo "missing from the package: $f"; exit 1; }
done

# The UCI defaults are shipped AND declared. Both halves matter: without the file a
# fresh install renders empty CBI tabs, and without the declaration the package manager
# replaces the admin's whole proxy configuration with these defaults on every upgrade.
grep -qx '/etc/config/telemt' "$work/control/conffiles"

grep -q '^Depends: libc, luci-base, luci-compat, qrencode, ca-bundle$' "$work/control/control"

# All three hooks reached the container and are executable. opkg calls them postinst,
# prerm and postrm; owfeed maps post-install, pre-deinstall and post-deinstall onto
# those.
for h in postinst prerm postrm; do
	[ -x "$work/control/$h" ] || { echo "hook missing or not executable: $h"; exit 1; }
done

echo "the package contains what it should."
