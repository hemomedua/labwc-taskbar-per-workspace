ws-switcher offline bundle / Автономный комплект
=================================================

Two workspaces with a per-workspace taskbar for Debian-based systems:
  * labwc 0.9.8 (Raspberry Pi OS trixie, arm64): patched labwc + configuration
  * xfwm4 (Xfce: Kali, Debian/Ubuntu Xfce, ...): configuration only, no patch needed
In both cases an xfce4-panel gets a workspace button (icon 1/2) and a window-menu button.

Две рабочие области с отдельной панелью задач для Debian-подобных систем:
  * labwc 0.9.8 (Raspberry Pi OS trixie, arm64): пропатченный labwc + настройка
  * xfwm4 (Xfce: Kali, Debian/Ubuntu Xfce и т.д.): только настройка, патч не нужен
В обоих случаях на панель xfce4 добавляются кнопка рабочего стола (значок 1/2) и кнопка меню окна.

USE / ИСПОЛЬЗОВАНИЕ
-------------------
  tar xzf ws-switcher-offline_*.tar.gz
  cd ws-switcher
  bash install.sh              # the mode (labwc / xfwm4) is detected automatically
  bash install.sh --offline    # never touch the network, use only files/ (labwc mode)
  bash install.sh --uninstall  # remove everything and restore the backups

Run it as a normal user from the graphical session's terminal (sudo is asked for apt only).
Запускать от обычного пользователя в терминале графической сессии (sudo нужен только для apt).
After the installation reboot (labwc mode) or log out and in (xfwm4 mode).

CONTENTS / СОСТАВ
-----------------
  install.sh                      installer (all other files are optional for it / остальное подхватывается само)
  files/labwc-taskbar-workspace_*_arm64.deb   patched labwc 0.9.8 for Debian trixie arm64 (diverts /usr/bin/labwc,
                                  original kept as /usr/bin/labwc.distrib; "apt remove labwc-taskbar-workspace" undoes it)
  files/deps/*.deb                wtype, xfce4-genmon-plugin, xdotool, libxdo3 (trixie arm64), used only when apt
                                  cannot install them (no network)
  source/                         full corresponding source: upstream labwc 0.9.8, our patches, build scripts
  SHA256SUMS                      checksums, verified by install.sh
  LICENSE-labwc-GPL-2.0.txt       GPL-2.0 (labwc and the patches are GPL-2.0-only)

REQUIREMENTS / ТРЕБОВАНИЯ
-------------------------
  labwc mode : arm64, Debian 13 (trixie) / Raspberry Pi OS trixie, labwc 0.9.8 with libwlroots-0.19 installed.
               The installer refuses to run with any other labwc version.
  xfwm4 mode : any Debian-based system with xfwm4 and xfce4-panel; xdotool and xfce4-genmon-plugin are
               installed from the distribution (or from files/deps on trixie arm64 when offline).
  Both       : python3 (labwc mode, for merging rc.xml/menu.xml) - preinstalled on Raspberry Pi OS.

REBUILD FROM SOURCE / СБОРКА ИЗ ИСХОДНИКОВ
------------------------------------------
Build dependencies (Debian trixie): build-essential meson ninja-build pkg-config gettext xwayland
libwlroots-0.19-dev (Raspberry Pi repository) libwayland-dev wayland-protocols libxkbcommon-dev libxcb1-dev
libxcb-ewmh-dev libxcb-icccm4-dev libdrm-dev libxml2-dev libglib2.0-dev libcairo2-dev libpango1.0-dev
libinput-dev libpixman-1-dev libpng-dev librsvg2-dev libsfdo-dev. See source/ci-setup.sh.

  cd source
  LABWC_SRC_TARBALL=$PWD/labwc-0.9.8-upstream-src.tar.gz OUT=$PWD/out bash build.sh
  # -> out/labwc-taskbar-workspace_*_arm64.deb ; put it into ../files/ and delete ../SHA256SUMS

WHAT THE PATCHES DO / ЧТО ДЕЛАЮТ ПАТЧИ
--------------------------------------
  0001  <desktops><taskbarCurrentWorkspaceOnly>yes</...>: panels see only the windows of the current workspace
  0002  <menu><showToggleState>yes</...>: check boxes in the window menu for always-on-top / omnipresent / shade

Home: https://github.com/hemomedua/labwc-taskbar-per-workspace (not needed for this bundle to work)
