#!/bin/sh

PKG_NAME="luci-app-telemt"
PKG_VER="3.0.0-3"
PKG_DIR="/tmp/${PKG_NAME}-build"
OUT_IPK="./${PKG_NAME}_${PKG_VER}_all.ipk"

echo "Preparing build environment..."
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/control"
mkdir -p "$PKG_DIR/data"

echo "2.0" > "$PKG_DIR/debian-binary"

echo "Copying root filesystem..."
cp -r root/* "$PKG_DIR/data/"
chmod 755 "$PKG_DIR/data/etc/init.d/telemt"

echo "Generating control files..."
cat > "$PKG_DIR/control/control" <<CTRL_EOF
Package: $PKG_NAME
Version: $PKG_VER
Depends: libc, luci-base, luci-compat, ca-bundle
Architecture: all
Maintainer: Community
Description: LuCI web-interface for Telemt MTProto Proxy (v3.0+)
CTRL_EOF

cat > "$PKG_DIR/control/postinst" <<'CTRL_EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
    /etc/init.d/telemt enable 2>/dev/null
    rm -rf /tmp/luci-modulecache/
    rm -f /tmp/luci-indexcache
    if [ ! -f /usr/bin/telemt ]; then
        echo "================================================================="
        echo " WARNING: The binary /usr/bin/telemt was not found!"
        echo " Please download the appropriate release for your architecture"
        echo " and make it executable: chmod +x /usr/bin/telemt"
        echo "================================================================="
    fi
}
exit 0
CTRL_EOF

cat > "$PKG_DIR/control/prerm" <<'CTRL_EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
    /etc/init.d/telemt stop 2>/dev/null
    /etc/init.d/telemt disable 2>/dev/null
}
exit 0
CTRL_EOF

cat > "$PKG_DIR/control/postrm" <<'CTRL_EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
    rm -rf /tmp/luci-modulecache/
    rm -f /tmp/luci-indexcache
    rm -f /var/etc/telemt.toml
}
exit 0
CTRL_EOF

chmod 755 "$PKG_DIR/control/postinst" "$PKG_DIR/control/prerm" "$PKG_DIR/control/postrm"

echo "Building archives..."
cd "$PKG_DIR/data" || exit
tar -czf ../data.tar.gz .
cd "$PKG_DIR/control" || exit
tar -czf ../control.tar.gz .
cd "$PKG_DIR" || exit
tar -czf "$OUT_IPK" debian-binary data.tar.gz control.tar.gz

rm -rf "$PKG_DIR"
echo "Done! Package generated: $OUT_IPK"
