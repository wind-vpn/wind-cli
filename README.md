<h1 align="center">windvpn-cli</h1>

<p align="center">
  <a href="https://github.com/wind-vpn/wind-cli/releases"><img alt="Version" src="https://img.shields.io/github/v/release/wind-vpn/wind-cli?style=for-the-badge&labelColor=1e1e2e&color=cba6f7"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-linux-cba6f7?style=for-the-badge&logo=linux&logoColor=white&labelColor=1e1e2e">
</p>

<p align="center">
  A modern VPN client that lives in your terminal
</p>

### Features

- **Modern protocols:** VMess, VLESS, Trojan, WireGuard, Shadowsocks, Hysteria 1/2, TUIC, AnyTLS, SOCKS5 and others
- **Flexible:** import subscriptions from raw links or Clash/Mihomo YAML, sing-box or Xray JSON, with automatic refresh and a wide range of settings
- **Headless:** the daemon and the embedded sing-box core run independently from the TUI, keeping connections alive after you detach
- **Lightweight:** ~50 MB RAM
- **Linux native:** static binaries for x86_64 and aarch64, no runtime dependencies

### Requirements

- Linux, x86_64 or aarch64
- `curl`, `tar` and `sha256sum` (or `shasum`) for the install script
- TUN mode: `pkexec` or `sudo` plus `setcap` (package `libcap2-bin` on Debian/Ubuntu, `libcap` on Arch and Fedora). The first time you enable TUN, the client asks for your password once to grant `CAP_NET_ADMIN` to its own binary
- Optional: systemd, for starting the daemon automatically at login

### Installation

```bash
curl -fsSL https://raw.githubusercontent.com/wind-vpn/wind-cli/main/install.sh | sh
```

The script detects your architecture, downloads the latest release, verifies its SHA-256 checksum and installs `windvpn-cli`, `windvpn-clid` and the `windvpn` alias into `~/.local/bin` (or the first writable directory from your `PATH`). If the daemon was running, it is restarted after the update.

Options are passed as environment variables:

```bash
# Install a specific version
curl -fsSL https://raw.githubusercontent.com/wind-vpn/wind-cli/main/install.sh | WINDVPN_CLI_VERSION=v1.0.0 sh

# Install into a custom directory
curl -fsSL https://raw.githubusercontent.com/wind-vpn/wind-cli/main/install.sh | WINDVPN_CLI_DIRECTORY=/usr/local/bin sh
```

Manual installation:

1. Download `windvpn-cli_<version>_linux_<amd64|arm64>.tar.gz` and `checksums.txt` from the [Releases](https://github.com/wind-vpn/wind-cli/releases) page
2. Verify the archive: `sha256sum -c checksums.txt --ignore-missing`
3. Extract it and put `windvpn-cli` and `windvpn-clid` into one directory that is in your `PATH`
4. Optionally create the short alias: `ln -s windvpn-cli windvpn`

### Uninstall

```bash
windvpn-cli stop
rm -f ~/.local/bin/windvpn-cli ~/.local/bin/windvpn-clid ~/.local/bin/windvpn
```

If you enabled autostart, disable it first with `systemctl --user disable --now windvpn-clid.service`. Settings, subscriptions and logs are kept in your user config directory (`~/.config/windvpn-cli` by default); delete it to remove them.

### Usage

The install script also provides `windvpn` as a short alias for `windvpn-cli`; the examples below use it.

- `windvpn`: open the TUI

#### Connection

- `windvpn up <node> [--tun | --proxy]`: start the daemon and connect
- `windvpn down`: disconnect
- `windvpn stop`: stop the daemon
- `windvpn probe [sub | id | name]`: probe node latencies
- `windvpn status [--json]`: show connection status
- `windvpn logs [daemon | engine] [-f]`: view logs

#### Subscriptions & Nodes

`windvpn subscription` or `windvpn sub`

- `add`: add a subscription or a raw protocol link
- `remove`: remove a subscription by ID or name
- `refresh`: refresh subscriptions
- `list [--json]`: list subscriptions and nodes

#### Additional

- `-h`, `--help`: show help
- `-v`, `--version`: show the current version

### Keybinds

| **Key**      | **Action**                | **Key**       | **Action**                  |
| ------------ | ------------------------- | ------------- | --------------------------- |
| `↑/↓`, `k/j` | Navigate                  | `Shift+↑/↓`   | Reorder subscriptions       |
| `←/→`, `h/l` | Fold / expand             | `Enter`       | Toggle / connect            |
| `t` / `T`    | Ping selected / all       | `r` / `R`     | Refresh selected / all      |
| `m`          | Switch mode (PROXY / TUN) | `/`           | Filter nodes                |
| `a`          | Add subscription / node   | `d`           | Delete subscription         |
| `o`          | Open settings             | `Esc`         | Save settings / cancel edit |
| `Tab`        | Switch settings tabs      | `q`, `Ctrl+C` | Exit TUI                    |

### Privacy

windvpn-cli has no telemetry and no analytics, and it does not check for updates on its own. Your subscription links and settings stay on your machine, in a file readable only by your user.

When the client downloads a subscription, it sends the following headers to the subscription server you configured, which many providers use to enforce device limits:

- `User-Agent` with the client name and version
- `X-Device-OS`, `X-Ver-OS` and `X-Device-Model`: OS name, OS version and device model
- `X-Hwid`: a hashed device identifier, different for every subscription host. The raw machine ID is never sent

Other network requests go only to the nodes of your subscriptions and the DNS servers you configured. By default, latency probing requests `http://www.gstatic.com/generate_204` through the selected node; the URL can be changed in the settings.

### Support

Found a bug? Open an [issue](https://github.com/wind-vpn/wind-cli/issues) and include the output of `windvpn --version` and `windvpn logs`. Remove subscription links and server addresses from the logs before posting them.

<!-- TODO: add a License section once the licensing question for the published binaries is settled -->
