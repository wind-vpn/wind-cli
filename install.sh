#!/bin/sh
# windvpn-cli installer (Linux only)
#
#   curl -fsSL https://raw.githubusercontent.com/wind-vpn/wind-cli/main/install.sh | sh
#
# Environment:
#   WINDVPN_CLI_VERSION    release tag to install, e.g. v1.0.0 (default: latest)
#   WINDVPN_CLI_DIRECTORY  install directory (default: first writable of
#                          ~/.local/bin, ~/bin, /usr/local/bin found in PATH,
#                          otherwise ~/.local/bin)
#   WINDVPN_CLI_SETCAP     set to 0 to skip granting CAP_NET_ADMIN (needed for TUN mode)

set -efu

repo="https://github.com/wind-vpn/wind-cli"
version="${WINDVPN_CLI_VERSION:-latest}"

step() {
	printf '• %s' "$1"
	if [ ! -t 1 ]; then printf '\n'; fi
}

pass() {
	if [ -t 1 ]; then printf '\r\033[K'; fi
	printf '✓ %s\n' "$1"
}

fail() {
	if [ -t 1 ]; then printf '\r\033[K'; fi
	printf '✗ %s\n' "$1" >&2
	exit 1
}

warn() {
	if [ -t 1 ]; then printf '\r\033[K'; fi
	printf '! %s\n' "$1" >&2
}

find_setcap() {
	if command -v setcap >/dev/null 2>&1; then
		command -v setcap
		return 0
	fi
	for candidate in /usr/sbin/setcap /sbin/setcap; do
		if [ -x "$candidate" ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	return 1
}

# TUN mode needs CAP_NET_ADMIN. Granting it here, with an interactive sudo prompt,
# avoids relying on a polkit agent at runtime. Never fatal: returns 1 on any problem.
grant_tun_capability() {
	case "${WINDVPN_CLI_SETCAP:-auto}" in
		0|no|false|off) return 2 ;;
	esac

	target="$dir/windvpn-clid"

	if ! setcap_bin=$(find_setcap); then
		warn "setcap not found (install libcap2-bin or libcap)"
		return 1
	fi

	if [ "$(id -u)" -eq 0 ]; then
		"$setcap_bin" cap_net_admin+ep "$target" || return 1
	elif command -v sudo >/dev/null 2>&1 && (: </dev/tty) 2>/dev/null; then
		printf '• Granting CAP_NET_ADMIN to windvpn-clid (required for TUN mode, sudo password may be requested)\n'
		sudo "$setcap_bin" cap_net_admin+ep "$target" || return 1
	else
		warn "no terminal or sudo available to grant permissions"
		return 1
	fi
}

[ "$(uname -s)" = Linux ] || fail "Unsupported OS: $(uname -s). windvpn-cli releases are Linux only"

case "$(uname -m)" in
	x86_64|amd64) arch=amd64 ;;
	arm64|aarch64) arch=arm64 ;;
	*) fail "Unsupported arch: $(uname -m)" ;;
esac
os=linux

for tool in curl tar awk mktemp; do
	command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

case "$version" in
	latest) base="$repo/releases/latest/download" ;;
	v*) base="$repo/releases/download/$version" ;;
	*) base="$repo/releases/download/v$version" ;;
esac

if [ -n "${WINDVPN_CLI_DIRECTORY:-}" ]; then
	dir="$WINDVPN_CLI_DIRECTORY"
else
	dir="$HOME/.local/bin"
	for candidate in "$HOME/.local/bin" "$HOME/bin" /usr/local/bin; do
		case ":$PATH:" in
			*":$candidate:"*)
				if [ "$candidate" != /usr/local/bin ]; then
					mkdir -p "$candidate" 2>/dev/null || continue
				fi
				[ -d "$candidate" ] && [ -w "$candidate" ] || continue
				dir="$candidate"
				break
				;;
		esac
	done
fi

mkdir -p "$dir" 2>/dev/null || fail "Cannot create directory $dir"
[ -w "$dir" ] || fail "Cannot write to $dir"
dir=$(cd "$dir" && pwd -P)

tmp=$(mktemp -d "$dir/.windvpn-cli.XXXXXXXX") || fail "Cannot create temporary directory in $dir"
restart=0

cleanup() {
	rm -rf "$tmp"

	# If we stopped a running daemon and bailed out before the restart step,
	# bring it back so a failed update does not leave the user disconnected.
	if [ "$restart" -eq 1 ] && [ -x "$dir/windvpn-clid" ]; then
		printf '• Restarting daemon...\n'
		nohup "$dir/windvpn-clid" >/dev/null 2>&1 </dev/null &
	fi
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

step "Fetching release..."

checksums="$tmp/checksums.txt"
curl -fsSL --retry 3 "$base/checksums.txt" -o "$checksums" 2>/dev/null || fail "Failed to fetch release metadata"

line=$(
	awk -v platform="${os}_${arch}" '
		length($1) == 64 && $1 ~ /^[[:xdigit:]]+$/ {
			sub(/^\*/, "", $2)
			if ($2 ~ ("^windvpn-cli_[^/[:space:]]+_" platform "\\.tar\\.gz$")) print tolower($1), $2
		}
	' "$checksums"
)

# shellcheck disable=SC2086
set -- $line
[ "$#" -eq 2 ] || fail "Expected exactly one release for ${os}_${arch}"

expected="$1"
archive="$2"

version=${archive#windvpn-cli_}
version=${version%_"${os}_${arch}.tar.gz"}
pass "Found v$version for ${os}/${arch}"

step "Downloading $archive..."

set -- -fsSL
if [ -t 1 ] && [ -t 2 ]; then
	printf '\n'
	set -- -fSL --progress-bar
fi
curl "$@" --retry 3 "$base/$archive" -o "$tmp/$archive" || fail "Failed to download $archive"
pass "Downloaded archive"

step "Verifying checksum..."

if command -v sha256sum >/dev/null 2>&1; then
	actual=$(sha256sum < "$tmp/$archive" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
	actual=$(shasum -a 256 < "$tmp/$archive" | awk '{print $1}')
else
	fail "sha256sum or shasum is required"
fi

[ "$actual" = "$expected" ] || fail "Checksum mismatch"

pass "Verified checksum"

step "Extracting archive..."
mkdir -p "$tmp/out"
tar -xzf "$tmp/$archive" -C "$tmp/out" 2>/dev/null || fail "Failed to extract archive"

for binary in windvpn-cli windvpn-clid; do
	[ -f "$tmp/out/$binary" ] || fail "Archive is missing $binary"
done
chmod 755 "$tmp/out/windvpn-cli" "$tmp/out/windvpn-clid"
ln -sf windvpn-cli "$tmp/out/windvpn"

for binary in windvpn-cli windvpn-clid windvpn; do
	[ ! -d "$dir/$binary" ] || fail "$dir/$binary is a directory"
done
pass "Extracted archive"

# Exit code 2 means "daemon not running"; anything else non-zero is a real failure.
if "$tmp/out/windvpn-cli" stop >/dev/null; then
	restart=1
	pass "Stopped daemon"
else
	[ "$?" -eq 2 ] || fail "Failed to stop daemon"
fi

step "Installing..."

for binary in windvpn-clid windvpn-cli; do
	mv -f "$tmp/out/$binary" "$dir/$binary" || fail "Failed to install $binary"
done

# Short alias. Never overwrite a different program that happens to be called "windvpn".
alias_ok=1
if [ -e "$dir/windvpn" ] || [ -L "$dir/windvpn" ]; then
	[ "$(readlink "$dir/windvpn" 2>/dev/null)" = windvpn-cli ] || alias_ok=0
fi
if [ "$alias_ok" -eq 1 ]; then
	mv -f "$tmp/out/windvpn" "$dir/windvpn" || fail "Failed to install windvpn"
fi

# The capability is stored on the file, so it must be (re)applied after every update
# and before the daemon is started again.
tun_ready=0
if grant_tun_capability; then
	tun_ready=1
	pass "Granted TUN permissions"
else
	[ "$?" -eq 2 ] || warn "Could not grant TUN permissions"
fi

if [ "$restart" -eq 1 ]; then
	restart=0
	step "Restarting daemon..."
	nohup "$dir/windvpn-clid" </dev/null >/dev/null 2>&1 &
	deadline=$(($(date +%s) + 30))
	while [ -z "$("$dir/windvpn-cli" status --json 2>/dev/null)" ]; do
		[ "$(date +%s)" -lt "$deadline" ] || fail "Failed to restore daemon"
		sleep 1
	done
	"$dir/windvpn-cli" status >/dev/null || fail "Failed to restore daemon"
	pass "Restarted daemon"
fi

pass "Installed to $dir"

if [ "$alias_ok" -eq 1 ]; then
	cmd=windvpn
else
	cmd=windvpn-cli
	printf '! %s/windvpn already exists and was left untouched\n' "$dir"
fi

if [ "$tun_ready" -eq 0 ]; then
	printf '\nTo use TUN mode, run once (and again after each update):\n  sudo setcap cap_net_admin+ep "%s/windvpn-clid"\n' "$dir"
fi

case ":$PATH:" in
	*":$dir:"*)
		printf '\nRun %s in a new terminal window.\n' "$cmd"
		;;
	*)
		printf '\nAdd %s to your PATH, then run %s.\n' "$dir" "$cmd"
		;;
esac
