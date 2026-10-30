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
* `install.sh` – one-shot installer (see below)
* `scripts/build.sh` – builds labwc 0.9.8 + patch for Debian trixie arm64 and makes a `.deb`
* `.github/workflows/build.yml` – runs the build on GitHub Actions (arm64), publishes the `.deb` as a release

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/hemomedua/labwc-taskbar-per-workspace/main/install.sh -o install.sh
less install.sh      # read it first
bash install.sh      # options: --mode labwc|xfwm4  --config-only  --no-panel  --keep-pager  --uninstall
```

The installer detects the desktop and picks a mode:

| Mode | Where | What it does |
|---|---|---|
| `labwc` | Raspberry Pi OS trixie, arm64, labwc 0.9.8 (Wayland) | installs the patched labwc from the latest release, two workspaces (`W-F11`/`W-F12`), per-workspace taskbar, window menu with check marks |
| `xfwm4` | X11 with Xfce (Kali, Debian/Ubuntu Xfce, ...) | no patch needed: sets two workspaces in xfwm4 and makes every xfce4-panel tasklist show only the current workspace; xfwm4 has its own window menu |

In both modes an xfce4-panel gets a workspace button (SVG icon 1/2, click = switch) and a "window menu"
button next to the application menu (genmon settings are written either to the old `genmon-N.rc` files or to
xfconf, depending on the plugin version). Existing `rc.xml`/`menu.xml` are merged, not overwritten;
first-run backups are kept as `*.orig-ws`. `labwc` mode refuses to run with another labwc version.
Other Wayland compositors and other labwc versions are not supported (the patch is version specific).

## Remove / recover

`bash install.sh --uninstall` removes everything and restores the backed-up files (`*.orig-ws`); every step is
independent, so a failing step does not stop the others. `bash install.sh --status` prints a read-only report.
Recovery if the desktop does not start, manual removal without the script, and what to do after system
updates: [docs/UNINSTALL.md](docs/UNINSTALL.md) (also shipped in the offline bundle as `UNINSTALL.txt`).

The `.deb` diverts `/usr/bin/labwc` (original kept as `/usr/bin/labwc.distrib`);
`sudo apt remove labwc-taskbar-workspace` restores it.

Status: experimental, tested on Raspberry Pi OS (trixie), Raspberry Pi 4B.

---

# По-русски

Патч для labwc 0.9.8: панели задач показывают только окна текущего рабочего стола.
Включается опцией `<desktops><taskbarCurrentWorkspaceOnly>yes</taskbarCurrentWorkspaceOnly></desktops>`
в `~/.config/labwc/rc.xml`. Установка и настройка одной командой: раздел Install выше (`install.sh`, режимы `labwc` и `xfwm4` определяются сами; на Kali/Xfce патч не нужен). Готовый `.deb` — в разделе Releases.
