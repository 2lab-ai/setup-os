#!/usr/bin/env bash
# ==============================================================================
# setup-os / install.sh — OS auto-detecting entrypoint
#
#   curl -fsSL https://raw.githubusercontent.com/2lab-ai/setup-os/main/install.sh | bash
#
# Detects the platform and hands off to the matching per-OS installer:
#   macOS            -> macos/install.sh
#   Linux (CachyOS)  -> z13-cachyos/install.sh
#
# Override detection by passing a target:
#   ... | bash -s -- macos
#   ... | bash -s -- z13-cachyos
#
# Shared logic lives in lib/common.sh. The per-OS installers can also be run
# directly (curl .../z13-cachyos/install.sh | bash) — this file is just the
# convenience "figure it out for me" front door.
# ==============================================================================
set -euo pipefail

RAW_BASE="${SETUP_OS_RAW:-https://raw.githubusercontent.com/2lab-ai/setup-os/main}"

_src="${BASH_SOURCE[0]:-}"
if [[ -n "$_src" && -f "$_src" ]]; then
    REPO_ROOT="$(cd "$(dirname "$_src")" && pwd)"
else
    REPO_ROOT=""
fi
export REPO_ROOT RAW_BASE

if [[ -n "$REPO_ROOT" && -f "$REPO_ROOT/lib/common.sh" ]]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib/common.sh"
else
    _tmp="$(mktemp)"
    curl -fsSL "$RAW_BASE/lib/common.sh" -o "$_tmp" || { echo "cannot fetch lib/common.sh" >&2; exit 1; }
    # shellcheck source=/dev/null
    source "$_tmp"
fi

# --- Resolve target -----------------------------------------------------------
target="${1:-}"

detect_target() {
    case "$(uname -s)" in
        Darwin) echo "macos"; return ;;
        Linux)  echo "z13-cachyos"; return ;;   # only supported Linux profile today
        *)      die "unsupported OS: $(uname -s)" ;;
    esac
}

if [[ -z "$target" ]]; then
    target="$(detect_target)"
    log "Detected target: ${C_BOLD}${target}${C_RESET}"
fi

case "$target" in
    macos|z13-cachyos) ;;
    *) die "unknown target '$target' (expected: macos | z13-cachyos)" ;;
esac

# --- Hand off -----------------------------------------------------------------
sub="$(grab "${target}/install.sh")"
log "Running ${target}/install.sh ..."
exec bash "$sub" "${@:2}"
