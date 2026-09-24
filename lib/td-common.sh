# shellcheck shell=bash
#
# Shared detection helpers for td-doctor and td-launch.
# Sourced, never executed directly.

TD_VERSION="0.1.0"

# ---------------------------------------------------------------- output ----

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
	C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
	C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'
else
	C_RESET=''; C_BOLD=''; C_DIM=''
	C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
fi

# Shorten $HOME to ~ for display. Paths stay copy-pasteable, because the shell
# expands ~ to the same thing, and output stops being dominated by one prefix.
td_tilde() {
	local text="$*"
	[[ -n "${HOME:-}" && ${#HOME} -gt 1 ]] && text="${text//$HOME/\~}"
	printf '%s' "$text"
}

die() { printf '%std-linux: error:%s %s\n' "$C_RED" "$C_RESET" "$(td_tilde "$*")" >&2; exit 1; }
warn_msg() { printf '%std-linux: warning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }

# ------------------------------------------------------------ bottles ----

# Print the Bottles data directory (Flatpak install first, then native).
td_bottles_data_dir() {
	local d
	for d in \
		"$HOME/.var/app/com.usebottles.bottles/data/bottles" \
		"$HOME/.local/share/bottles"
	do
		[[ -d "$d/bottles" ]] && { printf '%s\n' "$d"; return 0; }
	done
	return 1
}

# td_list_bottles <bottles-data-dir>
td_list_bottles() {
	local data="$1" b
	for b in "$data"/bottles/*/; do
		[[ -f "$b/bottle.yml" ]] && basename "$b"
	done
}

# td_bottle_get <bottle.yml> <TopLevelKey> — e.g. Runner, DXVK, VKD3D, Arch
# Reads only top-level scalars, which is all we need; avoids a YAML dependency.
td_bottle_get() {
	local file="$1" key="$2" val
	[[ -f "$file" ]] || return 1
	val=$(sed -n "s/^${key}:[[:space:]]*//p" "$file" | head -1)
	val="${val%\'}"; val="${val#\'}"
	val="${val%\"}"; val="${val#\"}"
	[[ -n "$val" ]] && printf '%s\n' "$val"
}

# --------------------------------------------------------- touchdesigner ----

# td_find_exe <wineprefix> — path of TouchDesigner.exe inside the prefix.
# Case-insensitive: the install directory is spelled differently by different
# installers, and Wine does not care while Linux does.
td_find_exe() {
	local prefix="$1" hit
	[[ -d "$prefix/drive_c" ]] || return 1
	hit=$(find "$prefix/drive_c" -maxdepth 5 -type f -iname 'TouchDesigner.exe' \
		-not -path '*/windows/*' -print 2>/dev/null | head -1)
	[[ -n "$hit" ]] && printf '%s\n' "$hit"
}

# td_exe_version <TouchDesigner.exe> — the build string, e.g. 2025.33070.
td_exe_version() {
	local exe="$1"
	[[ -f "$exe" ]] || return 1
	python3 - "$exe" <<'PY' 2>/dev/null
import re, sys
data = open(sys.argv[1], 'rb').read()
found = set(re.findall(r'20\d\d\.\d{3,6}', data.decode('utf-16-le', 'ignore')))
found |= {m.decode() for m in re.findall(rb'20\d\d\.\d{3,6}', data)}
if found:
    print(sorted(found)[-1])
PY
}

# ------------------------------------------------------------- runners ----

# A "sys-wine-*" runner means Bottles is using a Wine from the host (inside the
# Flatpak sandbox, for Flatpak installs) rather than one it downloaded.
td_runner_is_system() { [[ "$1" == sys-* ]]; }

# td_find_wine <runner-dir> — the wine binary inside a Bottles runner.
td_find_wine() {
	local runner="$1" cand
	for cand in "$runner/bin/wine64" "$runner/bin/wine"; do
		[[ -x "$cand" ]] && { printf '%s\n' "$cand"; return 0; }
	done
	cand=$(find "$runner" -maxdepth 3 -type f -name 'wine' -perm -u+x -print 2>/dev/null | head -1)
	[[ -n "$cand" ]] && printf '%s\n' "$cand"
}

# ---------------------------------------------------------------- system ----

td_gpu_name() {
	if command -v nvidia-smi >/dev/null 2>&1; then
		nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 && return 0
	fi
	if command -v lspci >/dev/null 2>&1; then
		lspci 2>/dev/null | sed -n 's/.*\(VGA compatible controller\|3D controller\): //p' | head -1
	fi
}

td_gpu_driver() {
	if command -v nvidia-smi >/dev/null 2>&1; then
		nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 && return 0
	fi
	[[ -r /sys/module/nvidia/version ]] && cat /sys/module/nvidia/version
}

td_is_nvidia() { [[ -n "$(td_gpu_driver)" ]] || [[ -e /dev/nvidiactl ]]; }

td_session_type() { printf '%s\n' "${XDG_SESSION_TYPE:-unknown}"; }
td_desktop()      { printf '%s\n' "${XDG_CURRENT_DESKTOP:-unknown}"; }

td_distro() {
	# shellcheck disable=SC1091
	[[ -r /etc/os-release ]] && ( . /etc/os-release; printf '%s\n' "${PRETTY_NAME:-$NAME}" )
}

td_state_dir() { printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/td-linux"; }
td_config_file() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/td-linux/config"; }

# The four IDS Peak libraries that need their PE entry point zeroed under Wine.
# ids_peak.dll itself is deliberately excluded: it loads fine, and patching it
# is not part of the known-good workaround.
TD_IDS_PEAK_DLLS=(
	ids_peak_afl.dll
	ids_peak_comfort_c.dll
	ids_peak_ifl.dll
	ids_peak_ipl.dll
)
