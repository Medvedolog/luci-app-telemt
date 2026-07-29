#!/bin/sh
# Lay luci-app-telemt out as an OpenWrt root filesystem — the shape owfeed packages.
#
#   tools/stage.sh            # version from the newest git tag
#   tools/stage.sh 3.4.1      # or say it explicitly (this is what CI does)
#
# What it leaves behind:
#
#   dist/VERSION                 the package version, read by owfeed.yml
#   dist/root/usr/…              the LuCI app, verbatim from ./usr
#   dist/root/etc/config/telemt  the UCI defaults, from ./telemt.config
#   dist/scripts/…               the install hooks, with line endings repaired
#
# This replaces the `contents:` block of nfpm.yaml. The package is pure Lua and
# JSON, so there is nothing to compile and no OpenWrt SDK involved; `owfeed build`
# turns this directory into a .apk for 25.12+ and a .ipk for 24.10 and earlier.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/dist}"

# The version. A tag is the source of truth — there is no version file in this
# repository, and nfpm.yaml used to carry a copy that CI overwrote with `sed` on
# every run, which is a copy that is wrong in the working tree by design.
VERSION="${1:-$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null || echo 0.0.0)}"
VERSION="${VERSION#v}"

# APKv3 REQUIRES A PACKAGE REVISION and this project's tags do not carry one in a
# form apk understands. Two shapes exist in the tag history and both are handled:
#
#   3.4.0    -> 3.4.0-r1     no revision at all, so this is the first packaging
#   3.1.3-1  -> 3.1.3-r1     a revision written the Debian way; apk wants -r<n>
#
# Without this, apk refuses the package outright: after the version it accepts a
# `-r<digits>` suffix and nothing else.
case "$VERSION" in
	*-r[0-9]*) ;;
	*-[0-9]*)  VERSION="${VERSION%-*}-r${VERSION##*-}" ;;
	*)         VERSION="${VERSION}-r1" ;;
esac

# The version the package claims and the version the web interface prints must be
# the same number. They are two strings in two files, and when they disagree the
# only symptom is a user reading one version in `apk info` and another in LuCI,
# with no way to tell which is lying.
UI_VERSION="$(sed -n 's/.*LuCI App Version:.*>\([0-9][0-9.]*\)<.*/\1/p' \
	"$ROOT/usr/lib/lua/luci/model/cbi/telemt.lua" | head -n 1)"
if [ -n "$UI_VERSION" ] && [ "${VERSION%-r*}" != "$UI_VERSION" ]; then
	echo "version mismatch: packaging ${VERSION%-r*}, but the LuCI page says $UI_VERSION" >&2
	echo "update the version strings in usr/lib/lua/luci/model/cbi/telemt.lua" >&2
	exit 1
fi

rm -rf "$OUT/root" "$OUT/scripts"
mkdir -p "$OUT/root/etc/config" "$OUT/scripts"

printf '%s\n' "$VERSION" > "$OUT/VERSION"

cp -a "$ROOT/usr" "$OUT/root/usr"
cp -a "$ROOT/telemt.config" "$OUT/root/etc/config/telemt"

# CRLF AND THE UTF-8 BOM, STRIPPED FROM THE HOOKS. Both are edited on Windows from
# time to time, and OpenWrt's POSIX sh fails on either in a way that reads as a
# broken package: a CR at the end of the shebang makes the interpreter path
# "/bin/sh\r", which does not exist, and a BOM before `#!` stops it being a shebang
# at all. The old CI did this with dos2unix; sed needs no package.
#
# The hooks alone, exactly as before: the Lua and JSON payload is read by
# interpreters that do not care, and rewriting shipped files that nobody asked to
# rewrite is how a packaging step starts changing the thing it packages.
for s in postinst prerm postrm; do
	src="$ROOT/scripts/$s"
	[ -f "$src" ] || continue
	sed -e '1s/^\xef\xbb\xbf//' -e 's/\r$//' "$src" > "$OUT/scripts/$s"
	chmod 0755 "$OUT/scripts/$s"
done

echo "staged luci-app-telemt $VERSION"
find "$OUT/root" -type f | sort | sed "s|^$OUT/root||"
