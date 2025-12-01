#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${1:-/tmp/ci-output}"
SRCVER="${SRCVER:-3.6.0}"
PKGNAME="${PKGNAME:-openssl-pro-static}"
ARCH="${ARCH:-arm64}"
AARCH64_PREFIX="aarch64-linux-gnu-"

mkdir -p "$OUTDIR/stage" "$OUTDIR/debs"

cd "$OUTDIR"
# download source
wget -q "https://github.com/openssl/openssl/releases/download/openssl-${SRCVER}/openssl-${SRCVER}.tar.gz" -O "openssl-${SRCVER}.tar.gz"
tar -xf "openssl-${SRCVER}.tar.gz"
cd "openssl-${SRCVER}"

# set cross compile env
export CROSS_COMPILE="${AARCH64_PREFIX}"
export CC="${AARCH64_PREFIX}gcc"
export AR="${AARCH64_PREFIX}ar"
export RANLIB="${AARCH64_PREFIX}ranlib"
export STRIP="${AARCH64_PREFIX}strip"

# configure & build
./Configure linux-aarch64 no-shared no-dso no-tests no-ssl2 no-ssl3 no-comp --prefix=/usr -static
make -j"$(nproc)"
make install_sw DESTDIR="$OUTDIR/stage"

# strip binary if present
if [ -x "$OUTDIR/stage/usr/bin/openssl" ]; then
  "${STRIP}" "$OUTDIR/stage/usr/bin/openssl" || true
fi

# package structure
PKG_DIR="$OUTDIR/deb-${PKGNAME}-${ARCH}"
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/DEBIAN" "$PKG_DIR/usr/bin" "$PKG_DIR/usr/lib" "$PKG_DIR/usr/include"

cp -a "$OUTDIR/stage/usr/bin/"* "$PKG_DIR/usr/bin/" 2>/dev/null || true
cp -a "$OUTDIR/stage/usr/lib/"* "$PKG_DIR/usr/lib/" 2>/dev/null || true
cp -a "$OUTDIR/stage/usr/include/"* "$PKG_DIR/usr/include/" 2>/dev/null || true

cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: ${PKGNAME}
Version: ${SRCVER}
Architecture: ${ARCH}
Maintainer: CI Builder <ci@example.com>
Description: OpenSSL ${SRCVER} static build for Termux (aarch64)
EOF

cat > "$PKG_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
chmod +x /data/data/com.termux/files/usr/bin/openssl 2>/dev/null || true
exit 0
EOF
chmod 755 "$PKG_DIR/DEBIAN/postinst"

# md5sums
cd "$PKG_DIR"
find usr -type f -exec md5sum {} \; > DEBIAN/md5sums || true
cd -

# build .deb (fakeroot to not require root)
DEB_OUT="$OUTDIR/${PKGNAME}_${SRCVER}_${ARCH}.deb"
fakeroot dpkg-deb --build "$PKG_DIR" "$DEB_OUT"
cp "$DEB_OUT" "$OUTDIR/debs/"

echo "[ci] Built: $DEB_OUT"
