#!/bin/sh
# Create the two signing keys and put them into GitHub secrets. Run once, ever.
#
#   ./tools/setup-keys.sh
#
# Needs `gh` (https://cli.github.com), logged in with access to this repository.
#
# WHY CI CANNOT DO THIS FOR YOU. A key generated inside a CI job and thrown away
# signs nothing anyone can check: the point of the signature is that a feed pins the
# public half ONCE and every later release verifies against that same pin. A key that
# changes every run pins to nothing. So the key has to outlive the job, which means
# it has to be a secret, which means a person creates it. That is this script.
#
# It runs on your machine rather than on a server for the same reason: the private
# halves should exist in exactly two places — a password manager, and GitHub's secret
# store, which cannot be read back out.
set -eu

REPO="${REPO:-Medvedolog/luci-app-telemt}"
OWFEED_VERSION="${OWFEED_VERSION:-v0.4.5}"
WORK="${WORK:-./keys-setup}"

command -v gh >/dev/null || { echo "gh is not installed: https://cli.github.com"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "run 'gh auth login' first"; exit 1; }

if [ -e "$WORK" ]; then
	echo "$WORK already exists. If you have already run this, the keys are in GitHub"
	echo "and in your password manager; delete $WORK rather than running this again."
	echo "Generating a SECOND key would orphan the one a feed has already pinned."
	exit 1
fi
mkdir -p "$WORK"

# The same owfeed release CI uses, so the keys are made by the tool that will use them.
if command -v owfeed >/dev/null; then
	OWFEED="$(command -v owfeed)"
else
	echo ">> fetching owfeed $OWFEED_VERSION"
	case "$(uname -m)" in
		x86_64|amd64) arch=amd64 ;;
		aarch64|arm64) arch=arm64 ;;
		*) echo "no owfeed build for $(uname -m); download it by hand" >&2; exit 1 ;;
	esac
	case "$(uname -s)" in
		Linux) os=linux ;;
		Darwin) os=darwin ;;
		*) echo "no owfeed build for $(uname -s); download it by hand" >&2; exit 1 ;;
	esac
	curl -fsSL -o "$WORK/owfeed" \
		"https://github.com/owfeed/owfeed/releases/download/$OWFEED_VERSION/owfeed-$os-$arch"
	chmod +x "$WORK/owfeed"
	OWFEED="$WORK/owfeed"
fi

# KEY 1 — EC prime256v1. Its signature goes INSIDE the .apk and travels to the
# router. apk signature blocks are additive, so a feed that re-signs this package
# adds its own beside this one: anyone can take a published package, fetch this
# public key from somewhere that is not the feed, and confirm who built it.
echo ">> package signing key (EC)"
"$OWFEED" keygen -force -o "$WORK/telemt-sign.pem"

# KEY 2 — usign. It signs manifest.txt, the inventory of the whole release. usign
# because it is the scheme OpenWrt already ships, so a router verifies it with
# nothing installed, and because opkg on 24.10 cannot verify a standalone .ipk.
echo ">> release manifest key (usign)"
"$OWFEED" keygen -force -usign -o "$WORK/telemt-release.key"

echo ">> uploading to GitHub secrets of $REPO"
gh secret set TELEMT_SIGN_KEY  --repo "$REPO" < "$WORK/telemt-sign.pem"
gh secret set TELEMT_USIGN_KEY --repo "$REPO" < "$WORK/telemt-release.key"
gh secret list --repo "$REPO"

cat <<EOF

Done. Two things left, and the first cannot be undone.

1. SAVE THE PRIVATE KEYS somewhere you will still have them in a year:

     $WORK/telemt-sign.pem
     $WORK/telemt-release.key

   A GitHub secret cannot be read back out, and neither key can be revoked. Losing
   them means a feed that has pinned the public half stops accepting releases until
   a person re-pins a new key by hand.

   Then delete $WORK — the private halves must never be committed (.gitignore
   already refuses *.pem and *.key, but an untracked copy in the tree is a copy).

2. KEEP THE PUBLIC HALVES. These are not secret, and are what a feed pins:

     $WORK/telemt-sign.pub.pem
     $WORK/telemt-release.pub

   RELEASING.md says where they go.

Releases are signed automatically from now on. Tag one:

     git tag 3.4.1 && git push origin 3.4.1
EOF
