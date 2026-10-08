#!/bin/bash
# Prepares a debian:trixie container: Raspberry Pi apt repo + build dependencies.
set -euxo pipefail

curl -fsSL -o /tmp/raspberrypi.gpg.key https://archive.raspberrypi.com/debian/raspberrypi.gpg.key
file /tmp/raspberrypi.gpg.key
gpg --dearmor < /tmp/raspberrypi.gpg.key > /usr/share/keyrings/raspberrypi-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/raspberrypi-archive-keyring.gpg] http://archive.raspberrypi.com/debian/ trixie main" \
	> /etc/apt/sources.list.d/raspi.list
apt-get update

apt-get install -y --no-install-recommends \
	build-essential meson ninja-build pkg-config gettext xwayland \
	libwlroots-0.19-dev libwayland-dev wayland-protocols libxkbcommon-dev \
	libxcb1-dev libxcb-ewmh-dev libxcb-icccm4-dev libdrm-dev libxml2-dev \
	libglib2.0-dev libcairo2-dev libpango1.0-dev libinput-dev \
	libpixman-1-dev libpng-dev librsvg2-dev
apt-get install -y --no-install-recommends libsfdo-dev \
	|| echo "libsfdo-dev not available, meson wrap will be used"
