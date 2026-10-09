# labwc-taskbar-per-workspace

Patch for [labwc](https://github.com/labwc/labwc) 0.9.8 that makes panels/taskbars
(xfce4-panel, waybar, sfwbar, ...) show only the windows of the **current workspace**.

Wayland has no standard way to tell a panel which workspace a window is on, so the
compositor does it itself: with the new option

```xml
<desktops number="2">
  <taskbarCurrentWorkspaceOnly>yes</taskbarCurrentWorkspaceOnly>
</desktops>
```

labwc keeps the foreign-toplevel handle of a window only while the window is on the
active workspace (or is visible on all workspaces). On workspace switch / window move
the handles are destroyed and re-created. The option is off by default.

* `patches/0001-taskbar-current-workspace-only.patch` – per-workspace taskbar (GPL-2.0-only, like labwc)
* `patches/0002-menu-show-toggle-state.patch` – optional `<menu><showToggleState>yes</showToggleState></menu>`:
  menu items for ToggleAlwaysOnTop / ToggleAlwaysOnBottom / ToggleOmnipresent / ToggleShade show a
  checked/unchecked box for the window the menu was opened for
* `examples/raspi-setup.sh` – example setup (two workspaces, panel buttons, window menu) for xfce4-panel on Raspberry Pi OS
* `scripts/build.sh` – builds labwc 0.9.8 + patch for Debian trixie arm64 and makes a `.deb`
* `.github/workflows/build.yml` – runs the build on GitHub Actions (arm64), publishes the `.deb` as a release

The `.deb` diverts `/usr/bin/labwc` (original kept as `/usr/bin/labwc.distrib`);
`sudo apt remove labwc-taskbar-workspace` restores it.

Status: experimental, tested on Raspberry Pi OS (trixie), Raspberry Pi 4B.

---

# По-русски

Патч для labwc 0.9.8: панели задач показывают только окна текущего рабочего стола.
Включается опцией `<desktops><taskbarCurrentWorkspaceOnly>yes</taskbarCurrentWorkspaceOnly></desktops>`
в `~/.config/labwc/rc.xml`. Готовый `.deb` для Raspberry Pi OS (trixie, arm64) — в разделе Releases.
