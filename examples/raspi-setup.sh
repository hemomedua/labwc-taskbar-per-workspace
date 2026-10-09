#!/bin/bash
# Example setup for xfce4-panel + labwc (Raspberry Pi OS trixie), written for one specific machine:
#  - two workspaces, W-F11 / W-F12 switch to workspace 1 / 2
#  - panel button (genmon plugin 30) showing the current workspace as an SVG icon, click = switch
#  - panel button (launcher plugin 32) that opens the labwc window menu (Alt+Space)
#  - taskbarCurrentWorkspaceOnly enabled (needs the patched labwc from this repo)
# Safe to run several times. Keeps a backup of rc.xml as rc.xml.bak-final.
set -eu
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/icons" "$HOME/.config/labwc"

# icons
cat > "$HOME/.local/share/icons/ws-1.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="32" height="32">
<rect x="1" y="1" width="22" height="22" rx="5" fill="#3b82f6"/>
<path d="M10 8.5 L13 6 L13 18" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
EOF
cat > "$HOME/.local/share/icons/ws-2.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="32" height="32">
<rect x="1" y="1" width="22" height="22" rx="5" fill="#10b981"/>
<path d="M8.5 9 C8.5 4.5 15.5 4.5 15.5 9 C15.5 12.5 8.5 14.5 8.5 18 L15.5 18" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
EOF
cat > "$HOME/.local/share/icons/ws-move.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="32" height="32">
<rect x="1" y="1" width="22" height="22" rx="5" fill="#f59e0b"/>
<path d="M6 9 H18 M15 6 L18 9 L15 12 M18 15 H6 M9 12 L6 15 L9 18" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
EOF

# scripts
cat > "$HOME/.local/bin/ws-set.sh" <<'EOF'
#!/bin/bash
echo "$1" > "${XDG_RUNTIME_DIR:-/tmp}/ws-current"
EOF
cat > "$HOME/.local/bin/ws-click.sh" <<'EOF'
#!/bin/bash
f=${XDG_RUNTIME_DIR:-/tmp}/ws-current
n=1
[ -r "$f" ] && read -r n < "$f"
if [ "$n" = 1 ]; then k=F12; else k=F11; fi
exec wtype -M logo -k "$k" -m logo
EOF
cat > "$HOME/.local/bin/ws-genmon.sh" <<'EOF'
#!/bin/bash
f=${XDG_RUNTIME_DIR:-/tmp}/ws-current
n=1
[ -r "$f" ] && read -r n < "$f"
[ "$n" = 2 ] || n=1
echo "<img>$HOME/.local/share/icons/ws-$n.svg</img>"
echo "<click>$HOME/.local/bin/ws-click.sh</click>"
EOF
cat > "$HOME/.local/bin/ws-move-click.sh" <<'EOF'
#!/bin/bash
exec wtype -M alt -k space -m alt
EOF
chmod +x "$HOME"/.local/bin/ws-set.sh "$HOME"/.local/bin/ws-click.sh \
	"$HOME"/.local/bin/ws-genmon.sh "$HOME"/.local/bin/ws-move-click.sh

# labwc autostart: reset the workspace number at login
touch "$HOME/.config/labwc/autostart"
grep -qF 'ws-current' "$HOME/.config/labwc/autostart" \
	|| echo 'echo 1 > "$XDG_RUNTIME_DIR/ws-current"' >> "$HOME/.config/labwc/autostart"

# labwc rc.xml
[ -f "$HOME/.config/labwc/rc.xml" ] && cp "$HOME/.config/labwc/rc.xml" "$HOME/.config/labwc/rc.xml.bak-final"
cat > "$HOME/.config/labwc/rc.xml" <<EOF
<?xml version="1.0"?>
<openbox_config xmlns="http://openbox.org/3.4/rc"><theme><font place="ActiveWindow"><name>Nunito Sans</name><size>14</size><weight>Light</weight><slant>Normal</slant></font><font place="InactiveWindow"><name>Nunito Sans</name><size>14</size><weight>Light</weight><slant>Normal</slant></font><name>PiXtrix</name></theme>
<desktops number="2">
  <popupTime>0</popupTime>
  <taskbarCurrentWorkspaceOnly>yes</taskbarCurrentWorkspaceOnly>
</desktops>
<keyboard>
  <default />
  <keybind key="W-F11">
    <action name="GoToDesktop" to="1" />
    <action name="Execute" command="$HOME/.local/bin/ws-set.sh 1" />
  </keybind>
  <keybind key="W-F12">
    <action name="GoToDesktop" to="2" />
    <action name="Execute" command="$HOME/.local/bin/ws-set.sh 2" />
  </keybind>
</keyboard>
<mouse>
  <default />
</mouse>
<menu>
  <showToggleState>yes</showToggleState>
</menu>
</openbox_config>
EOF

# window menu (client-menu): Alt+Space or right click on the title bar
cat > "$HOME/.config/labwc/menu.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu>
<menu id="client-menu">
  <item label="Послать в другой стол">
    <action name="SendToDesktop">
      <to>right</to>
      <wrap>yes</wrap>
      <follow>no</follow>
    </action>
  </item>
  <item label="Свернуть в заголовок">
    <action name="ToggleShade" />
  </item>
  <item label="Поверх всех">
    <action name="ToggleAlwaysOnTop" />
  </item>
  <item label="Показать везде">
    <action name="ToggleOmnipresent" />
  </item>
  <separator />
  <item label="Свернуть">
    <action name="Iconify" />
  </item>
  <item label="Развернуть / вернуть">
    <action name="ToggleMaximize" />
  </item>
  <item label="Закрыть">
    <action name="Close" />
  </item>
</menu>
</openbox_menu>
EOF
touch "$HOME/.config/labwc/themerc-override"
sed -i '/^menu\.width\.\(min\|max\):/d' "$HOME/.config/labwc/themerc-override"
printf '\nmenu.width.min: 260\nmenu.width.max: 420\n' >> "$HOME/.config/labwc/themerc-override"

# xfce4-panel: genmon 30 (workspace button) and launcher 32 (window menu button)
cat > "$HOME/.config/xfce4/panel/genmon-30.rc" <<EOF
Command=$HOME/.local/bin/ws-genmon.sh
UseLabel=0
Text=(ws)
UpdatePeriod=1000
Font=Sans 10
EOF
mkdir -p "$HOME/.config/xfce4/panel/launcher-32"
cat > "$HOME/.config/xfce4/panel/launcher-32/ws-move-1.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Move window
Comment=Window menu: send to another workspace
Icon=$HOME/.local/share/icons/ws-move.svg
Exec=$HOME/.local/bin/ws-move-click.sh
Terminal=false
StartupNotify=false
EOF
xfconf-query -c xfce4-panel -p /plugins/plugin-30 -n -t string -s genmon
xfconf-query -c xfce4-panel -p /plugins/plugin-32 -n -t string -s launcher
xfconf-query -c xfce4-panel -p /plugins/plugin-32/items -n -a -t string -s ws-move-1.desktop

# insert 30 and 32 right after the menu (plugin 16), drop the pager (4), keep everything else
args=()
for id in $(xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids | grep -E '^[0-9]+$'); do
	case "$id" in 4|30|32) continue ;; esac
	args+=(-t int -s "$id")
	[ "$id" = 16 ] && args+=(-t int -s 30 -t int -s 32)
done
xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids "${args[@]}"

echo 1 > "$XDG_RUNTIME_DIR/ws-current"
pkill -HUP labwc || true
sleep 1
xfce4-panel -r || true
echo "DONE"
