#!/bin/sh

BIN_SRC="/tmp/telemt"
PKG_NAME="telemt"
PKG_VER="3.0.0-musl"
PKG_ARCH="aarch64_generic"

PKG_DIR="/tmp/build_${PKG_NAME}"
OUT_IPK="./${PKG_NAME}_${PKG_VER}_${PKG_ARCH}.ipk"

if [ ! -f "$BIN_SRC" ]; then
    echo "ERROR: Source binary $BIN_SRC not found!"
    exit 1
fi

echo "Preparing build directories..."
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/control"
mkdir -p "$PKG_DIR/data/usr/bin"

echo "2.0" > "$PKG_DIR/debian-binary"

cp "$BIN_SRC" "$PKG_DIR/data/usr/bin/telemt"
chmod 755 "$PKG_DIR/data/usr/bin/telemt"

cat > "$PKG_DIR/control/control" <<CTRL_EOF
Package: $PKG_NAME
Version: $PKG_VER
Architecture: $PKG_ARCH
Maintainer: Community
Description: Telemt MTProxy binary (v3.0.0) [Compiled for $PKG_ARCH]
CTRL_EOF

cd "$PKG_DIR/data" || exit
tar -czf ../data.tar.gz .
cd "$PKG_DIR/control" || exit
tar -czf ../control.tar.gz .
cd "$PKG_DIR" || exit
tar -czf "$OUT_IPK" debian-binary data.tar.gz control.tar.gz

rm -rf "$PKG_DIR"
echo "Done! Binary IPK generated: $OUT_IPK"
