#!/bin/bash
# Builds patched labwc 0.9.8 for Debian trixie arm64 and packages it as a .deb.
# Run inside a debian:trixie container with the Raspberry Pi apt repository enabled.
set -euxo pipefail

WORK=${WORK:-/tmp/work}
SRC=$WORK/labwc
OUT=${OUT:-$PWD/out}
mkdir -p "$WORK" "$OUT"

git clone --depth 1 --branch 0.9.8 https://github.com/labwc/labwc "$SRC"
cd "$SRC"
for p in "$OLDPWD"/patches/*.patch; do
	git apply --verbose "$p"
done

meson setup build --prefix=/usr --buildtype=release \
	-Dxwayland=enabled -Dman-pages=disabled -Dnls=enabled
ninja -C build

rm -rf "$WORK/pkgroot" && DESTDIR="$WORK/pkgroot" ninja -C build install
file "$WORK/pkgroot/usr/bin/labwc"
ldd "$WORK/pkgroot/usr/bin/labwc" | grep -i 'not found' && exit 1 || true

# --- .deb that diverts /usr/bin/labwc (original is kept as labwc.distrib)
PKG=labwc-taskbar-workspace
VER=0.9.8+ws2
D=$WORK/deb
rm -rf "$D" && mkdir -p "$D/DEBIAN" "$D/usr/bin"
install -m755 "$WORK/pkgroot/usr/bin/labwc" "$D/usr/bin/labwc"

cat > "$D/DEBIAN/control" <<CTL
Package: $PKG
Version: $VER
Architecture: arm64
Maintainer: hemomedua <noreply@users.noreply.github.com>
Depends: labwc (>= 0.9.8), libwlroots-0.19
Section: x11
Priority: optional
Description: labwc 0.9.8 with per-workspace taskbar filtering and menu toggle state
 Adds the option <desktops><taskbarCurrentWorkspaceOnly>yes</...> so that
 panels and taskbars only see windows on the current workspace.
 The original /usr/bin/labwc is diverted to /usr/bin/labwc.distrib.
CTL

cat > "$D/DEBIAN/preinst" <<'PRE'
#!/bin/sh
set -e
case "$1" in
install|upgrade)
	dpkg-divert --package labwc-taskbar-workspace --add --rename \
		--divert /usr/bin/labwc.distrib /usr/bin/labwc
	;;
esac
PRE
cat > "$D/DEBIAN/postrm" <<'POST'
#!/bin/sh
set -e
case "$1" in
remove|abort-install|disappear)
	dpkg-divert --package labwc-taskbar-workspace --remove --rename /usr/bin/labwc
	;;
esac
POST
chmod 755 "$D/DEBIAN/preinst" "$D/DEBIAN/postrm"

dpkg-deb --root-owner-group --build "$D" "$OUT/${PKG}_${VER}_arm64.deb"
dpkg-deb -I "$OUT/${PKG}_${VER}_arm64.deb"
ls -la "$OUT"
