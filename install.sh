#!/usr/bin/env bash
# server-pulse installer.
#
#   curl -fsSL https://raw.githubusercontent.com/volkv/server-pulse/main/install.sh | sudo bash
#   # or, from a clone:
#   sudo ./install.sh

set -euo pipefail

REPO_URL="https://github.com/volkv/server-pulse"
INSTALL_DIR="/opt/server-pulse"
CONFIG_DIR="/etc/server-pulse"
STATE_DIR="/var/lib/server-pulse"
BIN_LINK="/usr/local/bin/server-pulse"
SYSTEMD_DIR="/etc/systemd/system"
REF="${INSTALL_REF:-main}"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        red "Installer must run as root. Try: sudo $0"
        exit 1
    fi
}

require_prereqs() {
    local missing=()
    local cmd
    for cmd in bash curl awk grep sed tar systemctl; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        red "Missing prerequisites: ${missing[*]}"
        red "Install them via your package manager and re-run."
        exit 1
    fi

    if (( BASH_VERSINFO[0] < 4 )); then
        red "bash >= 4 is required (you have ${BASH_VERSION})"
        exit 1
    fi

    if [[ ! -d /run/systemd/system ]]; then
        red "systemd is required (couldn't find /run/systemd/system)."
        exit 1
    fi
}

install_files() {
    bold "==> Installing server-pulse to ${INSTALL_DIR}"
    local src
    src="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

    if [[ -f "$src/bin/server-pulse" ]]; then
        # Running from a clone.
        mkdir -p "$INSTALL_DIR"
        cp -r "$src/bin" "$src/lib" "$src/systemd" "$src/config" "$INSTALL_DIR/"
        [[ -f "$src/LICENSE"   ]] && cp "$src/LICENSE"   "$INSTALL_DIR/"
        [[ -f "$src/README.md" ]] && cp "$src/README.md" "$INSTALL_DIR/"
    else
        # Curl install: fetch a tarball from GitHub.
        local tarball="/tmp/server-pulse-${REF}.tar.gz"
        local tmpdir="/tmp/server-pulse-${REF}.d"
        rm -rf "$tmpdir" "$tarball"
        bold "==> Downloading ${REPO_URL}/archive/${REF}.tar.gz"
        curl -fsSL -o "$tarball" "${REPO_URL}/archive/${REF}.tar.gz"
        mkdir -p "$tmpdir"
        tar -xzf "$tarball" -C "$tmpdir" --strip-components=1
        mkdir -p "$INSTALL_DIR"
        cp -r "$tmpdir/bin" "$tmpdir/lib" "$tmpdir/systemd" "$tmpdir/config" "$INSTALL_DIR/"
        [[ -f "$tmpdir/LICENSE"   ]] && cp "$tmpdir/LICENSE"   "$INSTALL_DIR/"
        [[ -f "$tmpdir/README.md" ]] && cp "$tmpdir/README.md" "$INSTALL_DIR/"
        rm -rf "$tmpdir" "$tarball"
    fi

    chmod +x "$INSTALL_DIR/bin/server-pulse"
    find "$INSTALL_DIR/lib" -name '*.sh' -exec chmod 0644 {} \;
    ln -sf "$INSTALL_DIR/bin/server-pulse" "$BIN_LINK"
}

install_config() {
    bold "==> Setting up config at ${CONFIG_DIR}"
    mkdir -p "$CONFIG_DIR"
    if [[ ! -f "$CONFIG_DIR/config.env" ]]; then
        cp "$INSTALL_DIR/config/config.example.env" "$CONFIG_DIR/config.env"
        yellow "    Created ${CONFIG_DIR}/config.env from the template."
        yellow "    Edit it and set TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID before enabling the timer."
    else
        yellow "    ${CONFIG_DIR}/config.env already exists — left untouched."
    fi
    chown root:root "$CONFIG_DIR/config.env"
    chmod 600       "$CONFIG_DIR/config.env"
}

install_state() {
    bold "==> Preparing state dir at ${STATE_DIR}"
    mkdir -p "$STATE_DIR/state"
    chown -R root:root "$STATE_DIR"
    chmod 700 "$STATE_DIR"
}

install_systemd() {
    bold "==> Installing systemd units"
    cp "$INSTALL_DIR/systemd/server-pulse.service" "$SYSTEMD_DIR/"
    cp "$INSTALL_DIR/systemd/server-pulse.timer"   "$SYSTEMD_DIR/"
    systemctl daemon-reload
}

print_next_steps() {
    echo ""
    green "✅ server-pulse installed."
    echo ""
    bold  "Next steps:"
    echo  "  1. Edit config:"
    echo  "       sudo \$EDITOR ${CONFIG_DIR}/config.env"
    echo  "     (at minimum: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID)"
    echo  ""
    echo  "  2. Send a test alert:"
    echo  "       sudo server-pulse test"
    echo  ""
    echo  "  3. Enable the periodic timer:"
    echo  "       sudo systemctl enable --now server-pulse.timer"
    echo  ""
    echo  "  4. Inspect state any time:"
    echo  "       sudo server-pulse status"
    echo  "       systemctl list-timers server-pulse.timer"
    echo  "       journalctl -u server-pulse.service -e"
    echo  ""
    bold  "Docs: ${REPO_URL}"
    echo  ""
}

main() {
    require_root
    require_prereqs
    install_files
    install_config
    install_state
    install_systemd
    print_next_steps
}

main "$@"
