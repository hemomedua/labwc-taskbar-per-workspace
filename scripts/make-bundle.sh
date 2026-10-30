#!/bin/bash
# Creates the self-contained offline bundle (run in CI after scripts/build.sh, inside debian:trixie
# with the Raspberry Pi apt repository enabled).
set -euxo pipefail

DEB=$(ls out/labwc-taskbar-workspace_*_arm64.deb | head -1)
VER=$(basename "$DEB" | sed -E 's/.*_([^_]+)_arm64\.deb/\1/')
B=out/bundle/ws-switcher
rm -rf out/bundle
mkdir -p "$B/files/deps" "$B/source/patches"

# 1. the patched labwc
cp "$DEB" "$B/files/"

# 2. small dependencies for Debian trixie arm64 (used only if apt cannot provide them)
( cd "$B/files/deps" && apt-get download wtype xfce4-genmon-plugin xdotool libxdo3 )

# 3. installer and documentation
cp install.sh "$B/install.sh"
cp docs/OFFLINE.md "$B/README.txt"

# 4. complete corresponding source (GPL): upstream labwc 0.9.8 + our patches + build scripts
rm -rf /tmp/labwc-src
git clone --depth 1 --branch 0.9.8 https://github.com/labwc/labwc /tmp/labwc-src
cp /tmp/labwc-src/COPYING "$B/LICENSE-labwc-GPL-2.0.txt"
git -C /tmp/labwc-src archive --format=tar.gz --prefix=labwc-0.9.8/ HEAD > "$B/source/labwc-0.9.8-upstream-src.tar.gz"
cp patches/*.patch "$B/source/patches/"
cp scripts/build.sh scripts/ci-setup.sh "$B/source/"

# 5. checksums (verified by install.sh)
( cd "$B" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS )

tar czf "out/ws-switcher-offline_${VER}.tar.gz" -C out/bundle ws-switcher
ls -la out
