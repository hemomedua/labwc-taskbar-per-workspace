#!/bin/bash
# labwc-taskbar-per-workspace: one-shot installer for Raspberry Pi OS (Debian trixie, arm64)
#
#   * installs the patched labwc 0.9.8 (.deb from the latest GitHub release of this repository)
#   * configures two workspaces (W-F11 / W-F12), per-workspace taskbar, window menu with
#     check marks, and - for xfce4-panel - a workspace button and a "send window" button
#
# Usage:  bash install.sh [--config-only] [--no-panel] [--keep-pager] [--uninstall]
#   --config-only   do not install packages, only (re)write the configuration
#   --no-panel      do not touch the xfce4-panel configuration
#   --keep-pager    keep the xfce4 "pager" plugin on the panel (removed by default)
#   --uninstall     remove everything this script installed and restore the backups
#
# Safe to run several times. Backups of the first state are kept as *.orig-ws.
set -euo pipefail

REPO="hemomedua/labwc-taskbar-per-workspace"
PKG="labwc-taskbar-workspace"
CONF="$HOME/.config/labwc"
PANEL_DIR="$HOME/.config/xfce4/panel"
BIN="$HOME/.local/bin"
ICONS="$HOME/.local/share/icons"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

CONFIG_ONLY=0; NO_PANEL=0; KEEP_PAGER=0; UNINSTALL=0
for arg in "$@"; do
	case "$arg" in
	--config-only) CONFIG_ONLY=1 ;;
	--no-panel) NO_PANEL=1 ;;
	--keep-pager) KEEP_PAGER=1 ;;
	--uninstall) UNINSTALL=1 ;;
	-h|--help) sed -n 2,16p "$0"; exit 0 ;;
	*) echo "unknown option: $arg" >&2; exit 2 ;;
	esac
done

log()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" != 0 ] || die "run as a normal user (sudo is used only for apt)"
mkdir -p "$CONF" "$BIN" "$ICONS"

# Keep a copy of the very first state of a file (not for files this script created itself).
backup_once() {
	[ -e "$1" ] && [ ! -e "$1.created-by-ws" ] && [ ! -e "$1.orig-ws" ] && cp -p "$1" "$1.orig-ws" || true
}

# ---------------------------------------------------------------- helpers
panel_ids() { xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids 2>/dev/null | grep -E '^[0-9]+$' || true; }

find_genmon_id() {
	local f
	for f in "$PANEL_DIR"/genmon-*.rc; do
		[ -e "$f" ] || continue
		if grep -q 'ws-genmon.sh' "$f"; then basename "$f" .rc | sed 's/^genmon-//'; return; fi
	done
}
find_launcher_id() {
	local d
	for d in "$PANEL_DIR"/launcher-*/; do
		[ -e "${d}ws-move-1.desktop" ] || continue
		basename "$d" | sed 's/^launcher-//'; return
	done
}

# ---------------------------------------------------------------- uninstall
if [ "$UNINSTALL" = 1 ]; then
	log "Uninstalling"
	if command -v xfconf-query >/dev/null; then
		g=$(find_genmon_id); l=$(find_launcher_id)
		ids=$(panel_ids)
		if [ -n "$ids" ]; then
			args=()
			for id in $ids; do
				[ "$id" = "$g" ] || [ "$id" = "$l" ] || args+=(-t int -s "$id")
			done
			xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids "${args[@]}"
		fi
		for id in $g $l; do xfconf-query -c xfce4-panel -p "/plugins/plugin-$id" -r -R 2>/dev/null || true; done
		[ -z "$g" ] || rm -f "$PANEL_DIR/genmon-$g.rc"
		[ -z "$l" ] || rm -rf "$PANEL_DIR/launcher-$l"
	fi
	for f in rc.xml menu.xml autostart themerc-override; do
		if [ -e "$CONF/$f.orig-ws" ]; then mv -f "$CONF/$f.orig-ws" "$CONF/$f"
		elif [ -e "$CONF/$f.created-by-ws" ]; then rm -f "$CONF/$f" "$CONF/$f.created-by-ws"; fi
	done
	rm -f "$BIN"/ws-set.sh "$BIN"/ws-click.sh "$BIN"/ws-genmon.sh "$BIN"/ws-move-click.sh \
		"$ICONS"/ws-1.svg "$ICONS"/ws-2.svg "$ICONS"/ws-move.svg "$XDG_RUNTIME_DIR/ws-current"
	sudo apt-mark unhold labwc || true
	sudo apt-get remove -y "$PKG" || true
	log "Done. Reboot (or log out and in) to go back to the stock labwc."
	exit 0
fi

# ---------------------------------------------------------------- preflight
log "Checking the system"
[ "$(uname -m)" = aarch64 ] || die "this package is built for arm64 (aarch64) only"
# shellcheck disable=SC1091
. /etc/os-release
[ "${VERSION_CODENAME:-}" = trixie ] || die "Debian/Raspberry Pi OS 13 (trixie) is required, found: ${PRETTY_NAME:-unknown}"
labwc_ver=$(dpkg-query -W -f='${Version}' labwc 2>/dev/null || true)
[ -n "$labwc_ver" ] || die "the labwc package is not installed"
case "$labwc_ver" in
0.9.8*) ;;
*) die "labwc $labwc_ver is installed, but the patch is built for 0.9.8 (with libwlroots-0.19). Aborting to avoid breaking the session." ;;
esac
dpkg -s libwlroots-0.19 >/dev/null 2>&1 || die "libwlroots-0.19 is not installed"
echo "OK: $PRETTY_NAME, labwc $labwc_ver"

# ---------------------------------------------------------------- packages
if [ "$CONFIG_ONLY" = 0 ]; then
	log "Installing packages (wtype, xfce4-genmon-plugin, python3, curl)"
	sudo apt-get install -y --no-install-recommends wtype xfce4-genmon-plugin python3 curl ca-certificates

	log "Downloading the patched labwc"
	tmp=$(mktemp -d); chmod 755 "$tmp"
	url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | python3 -c '
import json, sys
for a in json.load(sys.stdin).get("assets", []):
    if a["name"].endswith("_arm64.deb"):
        print(a["browser_download_url"]); break')
	[ -n "$url" ] || die "no .deb found in the latest release of $REPO"
	echo "$url"
	curl -fsSL -o "$tmp/$PKG.deb" "$url"
	chmod 644 "$tmp/$PKG.deb"
	sudo apt-get install -y "$tmp/$PKG.deb"
	sudo apt-mark hold labwc
	rm -rf "$tmp"
else
	command -v python3 >/dev/null || die "python3 is required"
fi

# ---------------------------------------------------------------- scripts and icons
log "Writing scripts and icons"
cat > "$ICONS/ws-1.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="32" height="32">
<rect x="1" y="1" width="22" height="22" rx="5" fill="#3b82f6"/>
<path d="M10 8.5 L13 6 L13 18" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
EOF
cat > "$ICONS/ws-2.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="32" height="32">
<rect x="1" y="1" width="22" height="22" rx="5" fill="#10b981"/>
<path d="M8.5 9 C8.5 4.5 15.5 4.5 15.5 9 C15.5 12.5 8.5 14.5 8.5 18 L15.5 18" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
EOF
cat > "$ICONS/ws-move.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="32" height="32">
<rect x="1" y="1" width="22" height="22" rx="5" fill="#f59e0b"/>
<path d="M6 9 H18 M15 6 L18 9 L15 12 M18 15 H6 M9 12 L6 15 L9 18" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
EOF
cat > "$BIN/ws-set.sh" <<'EOF'
#!/bin/bash
echo "$1" > "${XDG_RUNTIME_DIR:-/tmp}/ws-current"
EOF
cat > "$BIN/ws-click.sh" <<'EOF'
#!/bin/bash
f=${XDG_RUNTIME_DIR:-/tmp}/ws-current
n=1
[ -r "$f" ] && read -r n < "$f"
if [ "$n" = 1 ]; then k=F12; else k=F11; fi
exec wtype -M logo -k "$k" -m logo
EOF
cat > "$BIN/ws-genmon.sh" <<'EOF'
#!/bin/bash
f=${XDG_RUNTIME_DIR:-/tmp}/ws-current
n=1
[ -r "$f" ] && read -r n < "$f"
[ "$n" = 2 ] || n=1
echo "<img>$HOME/.local/share/icons/ws-$n.svg</img>"
echo "<click>$HOME/.local/bin/ws-click.sh</click>"
EOF
cat > "$BIN/ws-move-click.sh" <<'EOF'
#!/bin/bash
exec wtype -M alt -k space -m alt
EOF
chmod +x "$BIN"/ws-set.sh "$BIN"/ws-click.sh "$BIN"/ws-genmon.sh "$BIN"/ws-move-click.sh

# ---------------------------------------------------------------- labwc configuration
log "Configuring labwc"
cat > /tmp/ws-merge.$$.py <<'PYEOF'
#!/usr/bin/env python3
"""Merge the labwc-taskbar-per-workspace settings into existing labwc XML files.

  merge.py rc   FILE HOME     two workspaces, W-F11/W-F12, taskbarCurrentWorkspaceOnly, ...
  merge.py menu FILE          replace (or add) <menu id="client-menu">
"""
import sys
import xml.etree.ElementTree as ET

RC_NS = "http://openbox.org/3.4/rc"


def load(path, root_tag, ns_default):
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
    try:
        tree = ET.parse(path, parser)
    except (FileNotFoundError, ET.ParseError) as e:
        if isinstance(e, ET.ParseError):
            sys.exit("cannot parse %s: %s" % (path, e))
        root = ET.Element("{%s}%s" % (ns_default, root_tag) if ns_default else root_tag)
        tree = ET.ElementTree(root)
    root = tree.getroot()
    ns = root.tag[1:root.tag.index("}")] if root.tag.startswith("{") else ""
    return tree, root, ns


def save(tree, path, ns):
    if ns:
        ET.register_namespace("", ns)
    ET.indent(tree, space="  ")
    tree.write(path, encoding="utf-8", xml_declaration=True)


def finder(ns):
    def q(tag):
        return "{%s}%s" % (ns, tag) if ns else tag

    def get(parent, tag):
        for c in parent:
            if c.tag == q(tag):
                return c
        return None

    def ensure(parent, tag):
        e = get(parent, tag)
        if e is None:
            e = ET.SubElement(parent, q(tag))
        return e

    return q, get, ensure


def merge_rc(path, home):
    tree, root, ns = load(path, "openbox_config", RC_NS)
    q, get, ensure = finder(ns)

    desktops = ensure(root, "desktops")
    desktops.set("number", "2")
    ensure(desktops, "popupTime").text = "0"
    ensure(desktops, "taskbarCurrentWorkspaceOnly").text = "yes"

    kb = get(root, "keyboard")
    if kb is None:
        kb = ET.SubElement(root, q("keyboard"))
        ET.SubElement(kb, q("default"))
    for bind in list(kb):
        if bind.tag == q("keybind") and bind.get("key") in ("W-F11", "W-F12"):
            kb.remove(bind)
    for n in ("1", "2"):
        bind = ET.SubElement(kb, q("keybind"), key="W-F1%s" % n)
        ET.SubElement(bind, q("action"), name="GoToDesktop", to=n)
        ET.SubElement(bind, q("action"), name="Execute",
                      command="%s/.local/bin/ws-set.sh %s" % (home, n))

    if get(root, "mouse") is None:
        mouse = ET.SubElement(root, q("mouse"))
        ET.SubElement(mouse, q("default"))

    ensure(ensure(root, "menu"), "showToggleState").text = "yes"
    save(tree, path, ns)


CLIENT_MENU = [
    ("Послать в другой стол", [("SendToDesktop", {"to": "right", "wrap": "yes", "follow": "no"})]),
    ("Свернуть в заголовок", [("ToggleShade", {})]),
    ("Поверх всех", [("ToggleAlwaysOnTop", {})]),
    ("Показать везде", [("ToggleOmnipresent", {})]),
    None,
    ("Свернуть", [("Iconify", {})]),
    ("Развернуть / вернуть", [("ToggleMaximize", {})]),
    ("Закрыть", [("Close", {})]),
]


def merge_menu(path):
    tree, root, ns = load(path, "openbox_menu", "")
    q, get, ensure = finder(ns)
    for m in list(root):
        if m.tag == q("menu") and m.get("id") == "client-menu":
            root.remove(m)
    menu = ET.SubElement(root, q("menu"), id="client-menu")
    for entry in CLIENT_MENU:
        if entry is None:
            ET.SubElement(menu, q("separator"))
            continue
        label, actions = entry
        item = ET.SubElement(menu, q("item"), label=label)
        for name, args in actions:
            action = ET.SubElement(item, q("action"), name=name)
            for k, v in args.items():
                ET.SubElement(action, q(k)).text = v
    save(tree, path, ns)


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "rc":
        merge_rc(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 3 and sys.argv[1] == "menu":
        merge_menu(sys.argv[2])
    else:
        sys.exit(__doc__)
PYEOF

# A user file replaces the system one completely, so start from the system file if the user has none.
# Files created here get a ".created-by-ws" marker, so --uninstall can remove them again.
seed() { # seed FILE SYSTEM_FILE
	if [ ! -e "$1" ]; then
		[ ! -e "$2" ] || cp "$2" "$1"
		: > "$1.created-by-ws"
	fi
}
seed "$CONF/rc.xml" /etc/xdg/labwc/rc.xml
seed "$CONF/menu.xml" /etc/xdg/labwc/menu.xml
seed "$CONF/autostart" /etc/xdg/labwc/autostart
seed "$CONF/themerc-override" /nonexistent

for f in rc.xml menu.xml autostart themerc-override; do backup_once "$CONF/$f"; done

python3 /tmp/ws-merge.$$.py rc "$CONF/rc.xml" "$HOME"
python3 /tmp/ws-merge.$$.py menu "$CONF/menu.xml"
rm -f /tmp/ws-merge.$$.py

touch "$CONF/autostart"
grep -qF 'ws-current' "$CONF/autostart" || echo 'echo 1 > "$XDG_RUNTIME_DIR/ws-current"' >> "$CONF/autostart"

touch "$CONF/themerc-override"
sed -i '/^menu\.width\.\(min\|max\):/d' "$CONF/themerc-override"
printf '\nmenu.width.min: 260\nmenu.width.max: 420\n' >> "$CONF/themerc-override"

echo 1 > "$XDG_RUNTIME_DIR/ws-current"

# ---------------------------------------------------------------- xfce4-panel
if [ "$NO_PANEL" = 1 ]; then
	log "Skipping the panel (--no-panel)"
elif ! command -v xfconf-query >/dev/null || [ -z "$(panel_ids)" ]; then
	warn "xfce4-panel is not configured on this system (no panel-1 found); the panel buttons were skipped."
	warn "Start xfce4-panel once, then run:  bash install.sh --config-only"
else
	log "Configuring xfce4-panel"
	ids=$(panel_ids)
	gid=$(find_genmon_id || true); lid=$(find_launcher_id || true)
	max=0
	for n in $ids $(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -oE '^/plugins/plugin-[0-9]+' | sed 's/.*-//'); do
		[ "$n" -gt "$max" ] && max=$n
	done
	[ -n "$gid" ] || { max=$((max+1)); gid=$max; }
	[ -n "$lid" ] || { max=$((max+1)); lid=$max; }

	cat > "$PANEL_DIR/genmon-$gid.rc" <<EOF
Command=$BIN/ws-genmon.sh
UseLabel=0
Text=(ws)
UpdatePeriod=1000
Font=Sans 10
EOF
	mkdir -p "$PANEL_DIR/launcher-$lid"
	cat > "$PANEL_DIR/launcher-$lid/ws-move-1.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Move window
Comment=Window menu: send to another workspace
Icon=$ICONS/ws-move.svg
Exec=$BIN/ws-move-click.sh
Terminal=false
StartupNotify=false
EOF
	xfconf-query -c xfce4-panel -p "/plugins/plugin-$gid" -n -t string -s genmon
	xfconf-query -c xfce4-panel -p "/plugins/plugin-$lid" -n -t string -s launcher
	xfconf-query -c xfce4-panel -p "/plugins/plugin-$lid/items" -n -a -t string -s ws-move-1.desktop

	# anchor: the application menu (whiskermenu / applicationsmenu), otherwise the first plugin
	anchor=""
	for kind in whiskermenu applicationsmenu; do
		for id in $ids; do
			t=$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$id" 2>/dev/null || true)
			if [ "$t" = "$kind" ] && [ -z "$anchor" ]; then anchor=$id; fi
		done
	done
	[ -n "$anchor" ] || anchor=$(echo "$ids" | head -1)

	args=()
	for id in $ids; do
		[ "$id" = "$gid" ] || [ "$id" = "$lid" ] && continue
		if [ "$KEEP_PAGER" = 0 ]; then
			t=$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$id" 2>/dev/null || true)
			[ "$t" = pager ] && continue
		fi
		args+=(-t int -s "$id")
		[ "$id" = "$anchor" ] && args+=(-t int -s "$gid" -t int -s "$lid")
	done
	xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids "${args[@]}"
fi

# ---------------------------------------------------------------- apply
log "Applying"
pkill -HUP -x labwc 2>/dev/null || true
sleep 1
if [ "$NO_PANEL" = 0 ] && pgrep -x xfce4-panel >/dev/null; then xfce4-panel -r || true; fi

dpkg -s "$PKG" >/dev/null 2>&1 || warn "the $PKG package is not installed: stock labwc ignores the per-workspace taskbar option."
running=$(readlink "/proc/$(pgrep -x labwc | head -1)/exe" 2>/dev/null || true)
echo
echo "Done."
case "$running" in
*labwc.distrib*) echo "The running session still uses the stock labwc: save your work and reboot (or log out and in) to activate the patched one." ;;
"") echo "labwc is not running in this session; the patched labwc will be used at the next login." ;;
*) echo "The patched labwc is already running." ;;
esac
