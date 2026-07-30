#!/bin/sh
# Everything in the source tree parses, in the interpreter that will run it.
#
# The PAYLOAD's shell and JSON are not checked here: `owfeed doctor` parses everything
# under `files:` (OWF213 and OWF212) once tools/stage.sh has staged it, which is the
# tree that actually ships. What is left is the Lua — which owfeed does not read — and
# the scripts that never reach a router.
#
# LUA 5.1 because that is what LuCI runs. A syntax error in the CBI model is not a
# subtle bug on a router: the page renders blank and the only trace is a line in the
# rpcd log. Nothing but a parser finds it before a user does.
#
# BOTH SHELL PARSERS for the hooks, because the router runs neither of the ones on this
# machine: dash is the close stand-in for the BusyBox ash that executes them, and bash
# catches a few things dash accepts.
set -eu
cd "$(dirname "$0")/.."

fail=0

for f in $(find usr -name '*.lua' | sort); do
	if luac5.1 -p "$f"; then echo "ok    lua   $f"; else echo "FAIL  lua   $f"; fail=1; fi
done

for f in $(find usr -name '*.json' | sort); do
	if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f"; then
		echo "ok    json  $f"
	else
		echo "FAIL  json  $f"; fail=1
	fi
done

for f in scripts/* tools/*.sh; do
	[ -f "$f" ] || continue
	for sh in dash bash; do
		if $sh -n "$f" 2>/tmp/owfeed-parse-err; then
			echo "ok    $sh -n $f"
		else
			echo "FAIL  $sh -n $f"; cat /tmp/owfeed-parse-err; fail=1
		fi
	done
done

# -S error only. At `warning` shellcheck reports style opinions about scripts written
# for BusyBox on purpose, and a gate nobody can get to green is a gate everyone learns
# to ignore. At `error` it reports what is wrong in any shell.
shellcheck -s sh -S error scripts/* tools/*.sh || fail=1

# CRLF AND THE UTF-8 BOM in the hooks. Either one makes OpenWrt's sh refuse to run the
# script: a CR at the end of the shebang makes the interpreter path "/bin/sh\r", and a
# BOM before `#!` stops it being a shebang at all. tools/stage.sh strips both so a
# release is never broken by them — this reports the file that keeps arriving that way,
# which the old workflow's silent `dos2unix` never did.
for f in scripts/*; do
	[ -f "$f" ] || continue
	if grep -q "$(printf '\r')" "$f"; then echo "CRLF  $f"; fail=1; fi
	if [ "$(head -c 3 "$f" | od -An -tx1 | tr -d ' ')" = "efbbbf" ]; then echo "BOM   $f"; fail=1; fi
done

[ "$fail" -eq 0 ] || { echo "sources do not parse"; exit 1; }
echo "sources parse."
