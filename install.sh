#!/bin/bash
# labwc-taskbar-per-workspace: installer for Debian-based systems (Raspberry Pi OS, Kali, Debian, ...)
#
# It detects the desktop and picks a mode:
#   labwc  (Wayland, Raspberry Pi OS trixie, arm64, labwc 0.9.8)
#          installs the patched labwc, two workspaces (W-F11 / W-F12), a taskbar that shows only the
#          windows of the current workspace, a window menu with check marks
#   xfwm4  (X11, Xfce: Kali, Debian/Ubuntu Xfce, ...)
#          no patch needed: sets two workspaces and makes the tasklist per-workspace
# In both modes an xfce4-panel gets a workspace button (SVG icon 1/2, click = switch) and a
# "window menu" button.
#
# Usage:  bash install.sh [--mode labwc|xfwm4] [--offline] [--config-only] [--no-panel] [--keep-pager] [--uninstall] [--status]
#   --offline       never use the network: install only from the files/ folder next to this script
#   --config-only   do not install packages, only (re)write the configuration
#   --no-panel      do not touch the xfce4-panel configuration
#   --keep-pager    keep the xfce4 "pager" plugin on the panel (removed by default)
#   --uninstall     remove everything this script installed and restore the backups
#   --status        print what is installed / configured (read-only, good for bug reports)
#
# If a files/ folder (the offline bundle) is next to this script, it is used instead of the network.
# Safe to run several times. Backups of the first state are kept as *.orig-ws.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
REPO="hemomedua/labwc-taskbar-per-workspace"
PKG="labwc-taskbar-workspace"
CONF="$HOME/.config/labwc"
STATE="$HOME/.config/ws-switcher"
PANEL_DIR="$HOME/.config/xfce4/panel"
BIN="$HOME/.local/bin"
ICONS="$HOME/.local/share/icons"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
	export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi
if [ -z "${DISPLAY:-}" ] && [ -S /tmp/.X11-unix/X0 ]; then export DISPLAY=:0; fi

STATUS=0; OFFLINE=0; MODE=auto; CONFIG_ONLY=0; NO_PANEL=0; KEEP_PAGER=0; UNINSTALL=0
while [ $# -gt 0 ]; do
	case "$1" in
	--mode) shift; MODE="${1:-}"; case "$MODE" in labwc|xfwm4) ;; *) echo "--mode needs labwc or xfwm4" >&2; exit 2 ;; esac ;;
	--offline) OFFLINE=1 ;;
	--config-only) CONFIG_ONLY=1 ;;
	--no-panel) NO_PANEL=1 ;;
	--keep-pager) KEEP_PAGER=1 ;;
	--uninstall) UNINSTALL=1 ;;
	--status) STATUS=1 ;;
	-h|--help) sed -n 2,27p "$0"; exit 0 ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

log()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" != 0 ] || die "run as a normal user (sudo is used only for apt)"
command -v apt-get >/dev/null || die "apt-get not found: this installer is for Debian-based systems"
mkdir -p "$BIN" "$ICONS" "$STATE"

# Keep a copy of the very first state of a file (not for files this script created itself).
backup_once() {
	[ -e "$1" ] && [ ! -e "$1.created-by-ws" ] && [ ! -e "$1.orig-ws" ] && cp -p "$1" "$1.orig-ws" || true
}

# ---------------------------------------------------------------- panel helpers
XQ() { timeout 15 xfconf-query -c xfce4-panel "$@"; }

panel_numbers() { XQ -p /panels 2>/dev/null | grep -E '^[0-9]+$' || true; }
panel_ids()     { XQ -p "/panels/panel-$1/plugin-ids" 2>/dev/null | grep -E '^[0-9]+$' || true; }
plugin_type()   { XQ -p "/plugins/plugin-$1" 2>/dev/null || true; }

# the panel that holds the tasklist (the "taskbar"); otherwise the first panel
pick_panel() {
	local p id first=""
	for p in $(panel_numbers); do
		[ -n "$first" ] || first=$p
		for id in $(panel_ids "$p"); do
			if [ "$(plugin_type "$id")" = tasklist ]; then echo "$p"; return; fi
		done
	done
	echo "$first"
}

find_genmon_id() {
	local f p v
	for f in "$PANEL_DIR"/genmon-*.rc; do
		[ -e "$f" ] || continue
		if grep -q 'ws-genmon.sh' "$f"; then basename "$f" .rc | sed 's/^genmon-//'; return; fi
	done
	for p in $(XQ -l 2>/dev/null | grep -E '^/plugins/plugin-[0-9]+/command$' || true); do
		v=$(XQ -p "$p" 2>/dev/null || true)
		case "$v" in *ws-genmon.sh*) echo "$p" | sed -E 's#^/plugins/plugin-([0-9]+)/.*#\1#'; return ;; esac
	done
}
find_launcher_id() {
	local d
	for d in "$PANEL_DIR"/launcher-*/; do
		[ -e "${d}ws-move-1.desktop" ] || continue
		basename "$d" | sed 's/^launcher-//'; return
	done
}

# genmon < 4.2.0 keeps its settings in ~/.config/xfce4/panel/genmon-N.rc, newer versions in xfconf
write_genmon_config() { # ID COMMAND
	local id=$1 cmd=$2 ver
	ver=$(dpkg-query -W -f='${Version}' xfce4-genmon-plugin 2>/dev/null || echo 0)
	if dpkg --compare-versions "$ver" ge 4.2.0; then
		local P="/plugins/plugin-$id"
		XQ -p "$P/command" -n -t string -s "$cmd"
		XQ -p "$P/use-label" -n -t bool -s false
		XQ -p "$P/text" -n -t string -s "(ws)"
		XQ -p "$P/update-period" -n -t int -s 1000
		XQ -p "$P/font" -n -t string -s "Sans 10"
	else
		cat > "$PANEL_DIR/genmon-$id.rc" <<EOF
Command=$cmd
UseLabel=0
Text=(ws)
UpdatePeriod=1000
Font=Sans 10
EOF
	fi
}

# ---------------------------------------------------------------- mode detection
detect_mode() {
	[ "$MODE" = auto ] || return 0
	if pgrep -x labwc >/dev/null 2>&1; then MODE=labwc
	elif pgrep -x xfwm4 >/dev/null 2>&1; then MODE=xfwm4
	elif dpkg -s labwc >/dev/null 2>&1 && ! dpkg -s xfwm4 >/dev/null 2>&1; then MODE=labwc
	elif dpkg -s xfwm4 >/dev/null 2>&1; then MODE=xfwm4
	else die "could not detect labwc or xfwm4; use --mode labwc or --mode xfwm4"; fi
}

# ---------------------------------------------------------------- status (read-only)
if [ "$STATUS" = 1 ]; then
	set +e +u
	echo "== system"
	( . /etc/os-release; echo "${PRETTY_NAME:-unknown} / $(uname -m)" )
	echo "detected mode: $( (detect_mode; echo "$MODE") 2>/dev/null || echo unknown )"
	echo "== labwc package"
	dpkg-query -W -f='labwc ${Version}\n' labwc 2>/dev/null || echo "labwc: not installed"
	dpkg-query -W -f="$PKG "'${Version}\n' "$PKG" 2>/dev/null || echo "$PKG: not installed"
	echo "held packages: $(apt-mark showhold 2>/dev/null | tr '\n' ' ')"
	echo "diversions: $(dpkg-divert --list /usr/bin/labwc 2>/dev/null || true)"
	echo "running labwc: $(readlink "/proc/$(pgrep -x labwc | head -1)/exe" 2>/dev/null || echo "not running")"
	ls -la /usr/bin/labwc /usr/bin/labwc.distrib 2>&1 | sed 's/^/  /'
	echo "== files"
	for f in "$CONF"/rc.xml "$CONF"/menu.xml "$CONF"/autostart "$CONF"/themerc-override \
		"$CONF"/*.orig-ws "$CONF"/*.created-by-ws "$BIN"/ws-*.sh "$ICONS"/ws-*.svg "$STATE"/*; do
		[ -e "$f" ] && echo "  $f"
	done
	echo "== xfce4-panel"
	if command -v xfconf-query >/dev/null && [ -n "$(pick_panel)" ]; then
		echo "genmon id: $(find_genmon_id || true)   launcher id: $(find_launcher_id || true)"
		for p in $(panel_numbers); do echo "panel-$p: $(panel_ids "$p" | tr '\n' ' ')"; done
	else
		echo "(no xfce4-panel configuration reachable from this shell)"
	fi
	echo "== xfwm4 workspaces: $(xfconf-query -c xfwm4 -p /general/workspace_count 2>/dev/null || echo n/a)"
	exit 0
fi

# ---------------------------------------------------------------- uninstall
# Best effort: every step is independent, a failing step never stops the following ones.
if [ "$UNINSTALL" = 1 ]; then
	log "Uninstalling"
	set +e +u

	echo "-- 1/5 patched labwc package (restores the stock /usr/bin/labwc)"
	sudo apt-mark unhold labwc
	if dpkg -s "$PKG" >/dev/null 2>&1; then
		sudo apt-get remove -y "$PKG" || sudo dpkg -r "$PKG"
	fi
	if dpkg-divert --list /usr/bin/labwc 2>/dev/null | grep -q "$PKG"; then
		sudo dpkg-divert --package "$PKG" --remove --rename /usr/bin/labwc
	fi
	if [ ! -x /usr/bin/labwc ] && [ -x /usr/bin/labwc.distrib ]; then sudo mv /usr/bin/labwc.distrib /usr/bin/labwc; fi
	[ -x /usr/bin/labwc ] || warn "/usr/bin/labwc is missing: run  sudo apt-get install --reinstall labwc"

	echo "-- 2/5 configuration files"
	for f in rc.xml menu.xml autostart themerc-override; do
		if [ -e "$CONF/$f.orig-ws" ]; then mv -f "$CONF/$f.orig-ws" "$CONF/$f"; echo "restored $f"
		elif [ -e "$CONF/$f.created-by-ws" ]; then rm -f "$CONF/$f" "$CONF/$f.created-by-ws"; echo "removed $f (it was created by the installer)"; fi
	done

	echo "-- 3/5 scripts and icons"
	g=$(find_genmon_id); l=$(find_launcher_id)
	rm -f "$BIN"/ws-set.sh "$BIN"/ws-click.sh "$BIN"/ws-genmon.sh "$BIN"/ws-move-click.sh \
		"$ICONS"/ws-1.svg "$ICONS"/ws-2.svg "$ICONS"/ws-move.svg "$XDG_RUNTIME_DIR/ws-current"

	echo "-- 4/5 xfwm4 workspace count"
	if [ -e "$STATE/xfwm4-workspace-count.orig" ] && command -v xfconf-query >/dev/null; then
		orig=$(cat "$STATE/xfwm4-workspace-count.orig")
		if [ "$orig" = unset ]; then timeout 15 xfconf-query -c xfwm4 -p /general/workspace_count -r
		else timeout 15 xfconf-query -c xfwm4 -p /general/workspace_count -n -t int -s "$orig"; fi
	fi

	echo "-- 5/5 panel buttons"
	if command -v xfconf-query >/dev/null; then
		for p in $(panel_numbers); do
			ids=$(panel_ids "$p")
			echo "$ids" | grep -qxE "${g:-x}|${l:-x}" || continue
			args=()
			for id in $ids; do
				[ "$id" = "$g" ] || [ "$id" = "$l" ] || args+=(-t int -s "$id")
			done
			XQ -p "/panels/panel-$p/plugin-ids" "${args[@]}"
		done
		for id in $g $l; do XQ -p "/plugins/plugin-$id" -r -R; done
	fi
	[ -z "$g" ] || rm -f "$PANEL_DIR/genmon-$g.rc"
	[ -z "$l" ] || rm -rf "$PANEL_DIR/launcher-$l"
	pgrep -x xfce4-panel >/dev/null && xfce4-panel -r
	rm -rf "$STATE"

	log "Done. Log out and in (or reboot) to go back to the stock setup."
	echo "The xfce4 pager plugin, if it was removed from the panel, is not restored automatically."
	echo "Check the result with:  bash install.sh --status"
	exit 0
fi

# ---------------------------------------------------------------- preflight
log "Checking the system"
detect_mode
. /etc/os-release
echo "System: ${PRETTY_NAME:-unknown}, mode: $MODE"
if [ "$MODE" = labwc ]; then
	[ "$(uname -m)" = aarch64 ] || die "the patched labwc package is built for arm64 (aarch64) only"
	[ "${VERSION_CODENAME:-}" = trixie ] || die "labwc mode needs Debian/Raspberry Pi OS 13 (trixie), found: ${PRETTY_NAME:-unknown}"
	labwc_ver=$(dpkg-query -W -f='${Version}' labwc 2>/dev/null || true)
	[ -n "$labwc_ver" ] || die "the labwc package is not installed"
	case "$labwc_ver" in
	0.9.8*) ;;
	*) die "labwc $labwc_ver is installed, but the patch is built for 0.9.8 (with libwlroots-0.19). Aborting to avoid breaking the session." ;;
	esac
	dpkg -s libwlroots-0.19 >/dev/null 2>&1 || die "libwlroots-0.19 is not installed"
	echo "OK: labwc $labwc_ver"
else
	dpkg -s xfwm4 >/dev/null 2>&1 || die "xfwm4 is not installed"
	echo "OK: xfwm4 $(dpkg-query -W -f='${Version}' xfwm4)"
fi

# ---------------------------------------------------------------- packages
# apt_install PKG...: install from the distribution (apt); if that is impossible (no network,
# --offline) fall back to the matching .deb files of the offline bundle (files/deps/).
apt_install() {
	if [ "$OFFLINE" = 0 ] && sudo apt-get install -y --no-install-recommends "$@"; then return 0; fi
	local pkg f list=()
	for pkg in "$@"; do
		for f in "$SCRIPT_DIR/files/deps/${pkg}_"*.deb; do [ -e "$f" ] && list+=("$f"); done
		if [ "$pkg" = xdotool ]; then
			for f in "$SCRIPT_DIR/files/deps/libxdo3_"*.deb; do [ -e "$f" ] && list+=("$f"); done
		fi
	done
	[ "${#list[@]}" -gt 0 ] || die "cannot install: $* (no network and no bundled .deb files for them)"
	echo "Installing from the bundled files: ${list[*]##*/}"
	sudo apt-get install -y --no-install-recommends "${list[@]}" \
		|| die "installing the bundled packages failed (they are built for Debian trixie arm64 and need their dependencies installed)"
}

verify_bundle() {
	if [ -f "$SCRIPT_DIR/SHA256SUMS" ]; then
		log "Verifying the bundled files"
		(cd "$SCRIPT_DIR" && sha256sum -c --quiet SHA256SUMS) || die "checksum mismatch: the bundle is damaged or was modified"
		echo "OK"
	fi
}

if [ "$CONFIG_ONLY" = 0 ]; then
	verify_bundle
	if [ "$MODE" = labwc ]; then
		log "Installing packages (wtype, xfce4-genmon-plugin)"
		apt_install wtype xfce4-genmon-plugin
		command -v python3 >/dev/null || apt_install python3

		LOCAL_DEB=$(ls "$SCRIPT_DIR"/files/*_arm64.deb 2>/dev/null | head -1 || true)
		tmp=$(mktemp -d); chmod 755 "$tmp"
		if [ -n "$LOCAL_DEB" ]; then
			log "Using the bundled patched labwc: ${LOCAL_DEB##*/}"
			cp "$LOCAL_DEB" "$tmp/$PKG.deb"
		else
			[ "$OFFLINE" = 0 ] || die "--offline needs the files/ folder of the offline bundle next to install.sh"
			log "Downloading the patched labwc"
			command -v curl >/dev/null || apt_install curl ca-certificates
			url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | python3 -c '
import json, sys
for a in json.load(sys.stdin).get("assets", []):
    if a["name"].endswith("_arm64.deb"):
        print(a["browser_download_url"]); break')
			[ -n "$url" ] || die "no .deb found in the latest release of $REPO"
			echo "$url"
			curl -fsSL -o "$tmp/$PKG.deb" "$url"
		fi
		chmod 644 "$tmp/$PKG.deb"
		sudo apt-get install -y "$tmp/$PKG.deb"
		sudo apt-mark hold labwc
		rm -rf "$tmp"
	else
		log "Installing packages (xdotool, xfce4-genmon-plugin)"
		apt_install xdotool xfce4-genmon-plugin
	fi
elif [ "$MODE" = labwc ]; then
	command -v python3 >/dev/null || die "python3 is required"
fi

# ---------------------------------------------------------------- icons
log "Writing icons and scripts"
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

if [ "$MODE" = labwc ]; then
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
else
	cat > "$BIN/ws-click.sh" <<'EOF'
#!/bin/bash
cur=$(xdotool get_desktop)
if [ "$cur" = 0 ]; then xdotool set_desktop 1; else xdotool set_desktop 0; fi
id=$(cat "$HOME/.config/ws-switcher/genmon-id" 2>/dev/null || true)
[ -z "$id" ] || xfce4-panel --plugin-event="genmon-$id:refresh:bool:true" || true
EOF
	cat > "$BIN/ws-genmon.sh" <<'EOF'
#!/bin/bash
n=$(xdotool get_desktop 2>/dev/null || echo 0)
[ "$n" = 1 ] && i=2 || i=1
echo "<img>$HOME/.local/share/icons/ws-$i.svg</img>"
echo "<click>$HOME/.local/bin/ws-click.sh</click>"
EOF
	cat > "$BIN/ws-move-click.sh" <<'EOF'
#!/bin/bash
exec xdotool key alt+space
EOF
fi
chmod +x "$BIN"/ws-*.sh

# ---------------------------------------------------------------- labwc configuration
if [ "$MODE" = labwc ]; then
	log "Configuring labwc"
	mkdir -p "$CONF"
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
fi

# ---------------------------------------------------------------- xfwm4 configuration
if [ "$MODE" = xfwm4 ]; then
	log "Configuring xfwm4 (two workspaces)"
	command -v xfconf-query >/dev/null || die "xfconf-query not found"
	backup_once "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
	if [ ! -e "$STATE/xfwm4-workspace-count.orig" ]; then
		xfconf-query -c xfwm4 -p /general/workspace_count > "$STATE/xfwm4-workspace-count.orig" 2>/dev/null \
			|| echo unset > "$STATE/xfwm4-workspace-count.orig"
	fi
	xfconf-query -c xfwm4 -p /general/workspace_count -n -t int -s 2
fi

# ---------------------------------------------------------------- xfce4-panel
if [ "$NO_PANEL" = 1 ]; then
	log "Skipping the panel (--no-panel)"
elif ! command -v xfconf-query >/dev/null || [ -z "$(pick_panel)" ]; then
	warn "xfce4-panel is not configured on this system (no panel found); the panel buttons were skipped."
	warn "Start xfce4-panel once, then run:  bash install.sh --config-only"
else
	log "Configuring xfce4-panel"
	backup_once "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
	P=$(pick_panel)
	ids=$(panel_ids "$P")
	echo "Using panel-$P"

	if [ "$MODE" = xfwm4 ]; then
		# show only the windows of the current workspace in every tasklist
		for p in $(panel_numbers); do
			for id in $(panel_ids "$p"); do
				[ "$(plugin_type "$id")" = tasklist ] || continue
				XQ -p "/plugins/plugin-$id/include-all-workspaces" -n -t bool -s false
			done
		done
	fi

	gid=$(find_genmon_id || true); lid=$(find_launcher_id || true)
	max=0
	for n in $(for p in $(panel_numbers); do panel_ids "$p"; done) \
		$(XQ -l 2>/dev/null | grep -oE '^/plugins/plugin-[0-9]+' | sed 's/.*-//'); do
		[ "$n" -gt "$max" ] && max=$n
	done
	[ -n "$gid" ] || { max=$((max+1)); gid=$max; }
	[ -n "$lid" ] || { max=$((max+1)); lid=$max; }
	echo "$gid" > "$STATE/genmon-id"

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
	XQ -p "/plugins/plugin-$gid" -n -t string -s genmon
	write_genmon_config "$gid" "$BIN/ws-genmon.sh"
	XQ -p "/plugins/plugin-$lid" -n -t string -s launcher
	XQ -p "/plugins/plugin-$lid/items" -n -a -t string -s ws-move-1.desktop

	# anchor: the application menu (whiskermenu / applicationsmenu), otherwise the first plugin
	anchor=""
	for kind in whiskermenu applicationsmenu; do
		for id in $ids; do
			if [ "$(plugin_type "$id")" = "$kind" ] && [ -z "$anchor" ]; then anchor=$id; fi
		done
	done
	[ -n "$anchor" ] || anchor=$(echo "$ids" | head -1)

	args=()
	for id in $ids; do
		if [ "$id" = "$gid" ] || [ "$id" = "$lid" ]; then continue; fi
		if [ "$KEEP_PAGER" = 0 ] && [ "$(plugin_type "$id")" = pager ]; then continue; fi
		args+=(-t int -s "$id")
		if [ "$id" = "$anchor" ]; then args+=(-t int -s "$gid" -t int -s "$lid"); fi
	done
	XQ -p "/panels/panel-$P/plugin-ids" "${args[@]}"
fi

# ---------------------------------------------------------------- apply
log "Applying"
if [ "$MODE" = labwc ]; then
	pkill -HUP -x labwc 2>/dev/null || true
	sleep 1
fi
if [ "$NO_PANEL" = 0 ] && pgrep -x xfce4-panel >/dev/null; then xfce4-panel -r || true; fi

echo
echo "Done."
if [ "$MODE" = labwc ]; then
	dpkg -s "$PKG" >/dev/null 2>&1 || warn "the $PKG package is not installed: stock labwc ignores the per-workspace taskbar option."
	running=$(readlink "/proc/$(pgrep -x labwc | head -1)/exe" 2>/dev/null || true)
	case "$running" in
	*labwc.distrib*) echo "The running session still uses the stock labwc: save your work and reboot (or log out and in) to activate the patched one." ;;
	"") echo "labwc is not running in this session; the patched labwc will be used at the next login." ;;
	*) echo "The patched labwc is already running." ;;
	esac
else
	echo "xfwm4 now has 2 workspaces. The window menu (right click on the title bar or Alt+Space) is xfwm4's own."
fi
