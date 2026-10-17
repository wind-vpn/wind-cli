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

# Remove the alias installed by older versions of this script.
if [ -L "$dir/jray" ] && [ "$(readlink "$dir/jray")" = windvpn-cli ]; then
	rm -f "$dir/jray"
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

case ":$PATH:" in
	*":$dir:"*)
		printf '\nRun %s in a new terminal window.\n' "$cmd"
		;;
	*)
		printf '\nAdd %s to your PATH, then run %s.\n' "$dir" "$cmd"
		;;
esac
