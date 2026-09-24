#!/usr/bin/env bash
#
# Put td-doctor, td-launch and td-patch-ids-peak on PATH and add a desktop
# entry, so TouchDesigner starts from the application menu with the
# compatibility environment already applied.
#
# Symlinks are used, so this repository has to stay where it is. Move it and
# re-run this script.

set -euo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
DESKTOP="$APP_DIR/touchdesigner.desktop"

# shellcheck source=lib/td-common.sh
source "$ROOT/lib/td-common.sh"

TOOLS=(td-setup td-doctor td-launch td-patch-ids-peak)

say() { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }

# Never clobber something the user wrote by hand; keep it as .bak. An existing
# .bak is left alone: it holds their original, whereas anything we would move
# on top of it is a file we generated on an earlier run.
back_up() {
	local target="$1" name
	name=$(basename "$target")
	[[ -e "$target" && ! -L "$target" ]] || return 0
	if [[ -e "$target.bak" ]]; then
		rm -f -- "$target"
		say "replaced $name (your original is still $name.bak)"
	else
		mv -- "$target" "$target.bak"
		say "kept your existing $name as $name.bak"
	fi
}

# Undo of back_up: if we shadowed something of the user's, give it back rather
# than leaving them with no launcher at all.
restore_backup() {
	local target="$1"
	if [[ -e "$target.bak" && ! -e "$target" ]]; then
		mv -- "$target.bak" "$target"
		say "restored your original $(basename "$target")"
	fi
}

uninstall() {
	local t
	for t in "${TOOLS[@]}" touchdesigner; do
		if [[ -L "$BIN_DIR/$t" ]]; then
			rm -- "$BIN_DIR/$t"
			say "removed $BIN_DIR/$t"
		fi
		restore_backup "$BIN_DIR/$t"
	done
	if [[ -f "$DESKTOP" ]]; then
		rm -- "$DESKTOP"
		say "removed $DESKTOP"
	fi
	restore_backup "$DESKTOP"
	[[ -f "$ICON_DIR/touchdesigner.png" ]] && rm -- "$ICON_DIR/touchdesigner.png"
	command -v update-desktop-database >/dev/null 2>&1 \
		&& update-desktop-database "$APP_DIR" 2>/dev/null || true
	say "uninstalled"
	exit 0
}

[[ "${1:-}" == "--uninstall" ]] && uninstall
[[ -n "${1:-}" ]] && { printf 'Usage: %s [--uninstall]\n' "$0" >&2; exit 2; }

mkdir -p "$BIN_DIR" "$APP_DIR"

# --------------------------------------------------------------- commands ----

for t in "${TOOLS[@]}"; do
	chmod +x "$ROOT/bin/$t"
	back_up "$BIN_DIR/$t"
	ln -sfn "$ROOT/bin/$t" "$BIN_DIR/$t"
done
say "linked ${TOOLS[*]} into $BIN_DIR"

# `touchdesigner` is the friendly name people actually type.
back_up "$BIN_DIR/touchdesigner"
ln -sfn "$ROOT/bin/td-launch" "$BIN_DIR/touchdesigner"
say "linked touchdesigner -> td-launch"

# ------------------------------------------------------------------- icon ----

icon_line=""
if command -v wrestool >/dev/null 2>&1 && command -v icotool >/dev/null 2>&1; then
	exe=""
	if data=$(td_bottles_data_dir); then
		for b in $(td_list_bottles "$data"); do
			if exe=$(td_find_exe "$data/bottles/$b"); then break; fi
		done
	fi
	if [[ -n "$exe" && -f "$exe" ]]; then
		tmp=$(mktemp -d)
		trap 'rm -rf "$tmp"' EXIT
		# Resource 101 is the application icon by Windows convention; the other
		# groups in TouchDesigner.exe are .toe/.tox document icons, which look
		# wrong in an application menu.
		wrestool -x -t 14 -n 101 -o "$tmp/app.ico" "$exe" >/dev/null 2>&1
		ico="$tmp/app.ico"
		[[ -s "$ico" ]] || ico=$(find "$tmp" -name '*.ico' -print -quit)
		if [[ -n "$ico" && -s "$ico" ]]; then
			mkdir -p "$ICON_DIR"
			# Largest frame in the .ico is the one worth keeping.
			if icotool -x -o "$tmp" "$ico" >/dev/null 2>&1; then
				png=$(find "$tmp" -name '*.png' -printf '%s %p\n' | sort -rn | head -1 | cut -d' ' -f2-) || png=""
				if [[ -n "$png" ]]; then
					cp -- "$png" "$ICON_DIR/touchdesigner.png"
					icon_line="Icon=touchdesigner"
					say "extracted icon from TouchDesigner.exe"
				fi
			fi
		fi
	fi
fi
[[ -n "$icon_line" ]] || icon_line="Icon=application-x-executable"

# ---------------------------------------------------------------- desktop ----

back_up "$DESKTOP"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=TouchDesigner
GenericName=Visual development platform
Comment=TouchDesigner via Wine, with the Linux compatibility fixes applied
Exec=$ROOT/bin/td-launch %f
Path=$ROOT
$icon_line
Terminal=false
StartupNotify=true
StartupWMClass=touchdesigner.exe
Categories=Graphics;AudioVideo;Development;
MimeType=application/x-touchdesigner;
Keywords=TouchDesigner;TD;toe;wine;
EOF
say "wrote $DESKTOP"

command -v update-desktop-database >/dev/null 2>&1 \
	&& update-desktop-database "$APP_DIR" 2>/dev/null || true

# ----------------------------------------------------------------- report ----

case ":$PATH:" in
	*":$BIN_DIR:"*) ;;
	*) printf '\n%swarning:%s %s is not on your PATH.\n' "$C_YELLOW" "$C_RESET" "$BIN_DIR"
	   printf '  Add this to your shell rc:  export PATH="%s:$PATH"\n' "$BIN_DIR" ;;
esac

cat <<EOF

Installed. Next:

  td-setup           install TouchDesigner from scratch (try --dry-run first)
  td-doctor          check this machine and print what still needs fixing
  touchdesigner      start TouchDesigner with the working environment
  td-doctor --log    explain the last run if it crashed

If TouchDesigner is already installed, skip td-setup: it will appear in your
application menu as soon as td-doctor finds it.
EOF
