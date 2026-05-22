#!/usr/bin/env bash
# -----------------------------------------------------------------------
# bios-info — install script
#
# Installs bios-info.sh and bios-info-wrapper.sh to ~/.local/bin/
# Override the install location:
#   INSTALL_DIR=~/bin bash install.sh
# -----------------------------------------------------------------------

set -u

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colours ─────────────────────────────────────────────────────────
if [[ -t 1 && "${TERM:-}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    GREEN='' YELLOW='' RED='' BOLD='' RESET=''
fi

ok()   { echo -e "${GREEN}✓ ${*}${RESET}"; }
warn() { echo -e "${YELLOW}⚠ ${*}${RESET}"; }
fail() { echo -e "${RED}✗ ${*}${RESET}"; exit 1; }
info() { echo    "  ${*}"; }

# ── Header ──────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}bios-info — installer${RESET}"
echo -e "Install location: ${BOLD}${INSTALL_DIR}${RESET}"
echo ""

# ── Create install dir if needed ────────────────────────────────────
if [[ ! -d "$INSTALL_DIR" ]]; then
    if mkdir -p "$INSTALL_DIR" 2>/dev/null; then
        ok "Created $INSTALL_DIR"
    else
        fail "Could not create $INSTALL_DIR"
    fi
fi

# ── Check $PATH ─────────────────────────────────────────────────────
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    warn "$INSTALL_DIR is not in your PATH"
    info "Add this to your ~/.bashrc or ~/.profile:"
    info "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi

# ── Install files ───────────────────────────────────────────────────
install_file() {
    local src="$1"
    local dst="$2"
    if [[ ! -f "$src" ]]; then
        fail "Source not found: $src"
    fi
    cp "$src" "$dst" && chmod +x "$dst" || fail "Failed to install $dst"
    ok "Installed $dst"
}

install_file "$SCRIPT_DIR/bin/bios-info.sh"         "$INSTALL_DIR/bios-info"
install_file "$SCRIPT_DIR/bin/bios-info-wrapper.sh"  "$INSTALL_DIR/bios-info-wrapper"

# ── Done ────────────────────────────────────────────────────────────
echo ""
ok "Installation complete"
echo ""
info "Run:          bios-info"
info "Full check:   bios-info --full"
info "Setup check:  bios-info --check"
info "Autostart:    add bios-info-wrapper to your session autostart"
echo ""
info "First time? Run 'bios-info --check' to verify dependencies"
info "and sudoers setup."
echo ""
