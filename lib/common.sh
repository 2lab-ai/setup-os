#!/usr/bin/env bash
# ==============================================================================
# setup-os/lib/common.sh — shared helpers for every OS installer
#
# Sourced by z13-cachyos/install.sh, macos/install.sh, and the root install.sh.
# Works in two modes transparently:
#   - local clone : sibling files are read straight from the repo
#   - curl | bash : sibling files (manifests) are fetched from GitHub raw on demand
#
# Kept deliberately thin: the heavy lifting — manifest parsing, version
# resolution/constraints, trust taps, backend selection — lives in xbrew
# (`xbrew bundle` / `xbrew version`, Rust). This file is just glue.
# ==============================================================================

# --- Config -------------------------------------------------------------------
RAW_BASE="${SETUP_OS_RAW:-https://raw.githubusercontent.com/2lab-ai/setup-os/main}"
XBREW_INSTALL_URL="https://raw.githubusercontent.com/2lab-ai/xbrew/HEAD/install.sh"
# `xbrew bundle` requires xbrew >= this. ensure_xbrew self-updates to satisfy it.
XBREW_MIN_VERSION="0.4.0"
REPO_ROOT="${REPO_ROOT:-}"

# --- Colors / logging ---------------------------------------------------------
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_BLUE=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
    C_RESET=; C_BOLD=; C_DIM=; C_BLUE=; C_GREEN=; C_YELLOW=; C_RED=
fi
log()     { printf '%s==>%s %s\n'  "$C_BLUE$C_BOLD" "$C_RESET" "$*"; }
info()    { printf '%s  - %s%s\n'  "$C_DIM" "$*" "$C_RESET"; }
success() { printf '%s  ✓ %s%s\n'  "$C_GREEN" "$*" "$C_RESET"; }
warning() { printf '%s  ! %s%s\n'  "$C_YELLOW" "$*" "$C_RESET" >&2; }
die()     { printf '%serror:%s %s\n' "$C_RED$C_BOLD" "$C_RESET" "$*" >&2; exit 1; }
section() { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }

have() { command -v "$1" >/dev/null 2>&1; }

# ask_yn <prompt> [default Y|N] -> 0=yes, 1=no.
# Reads from /dev/tty so it still prompts under `curl … | bash` (where stdin is
# the script itself). Falls back to the default when there is no terminal.
ask_yn() {
    local prompt="$1" default="${2:-Y}" ans hint
    case "$default" in [Yy]*) hint="[Y/n]";; *) hint="[y/N]";; esac
    if [[ -r /dev/tty ]]; then
        printf '%s%s%s %s ' "$C_BOLD" "$prompt" "$C_RESET" "$hint" > /dev/tty
        read -r ans < /dev/tty || ans=""
    else
        ans=""
        info "no terminal — assuming '$default' for: $prompt"
    fi
    [[ -z "$ans" ]] && ans="$default"
    case "$ans" in [Yy]*) return 0;; *) return 1;; esac
}

# --- File fetch (local-or-download) -------------------------------------------
# grab <repo-relative-path> -> prints a usable local path to that file.
_SETUP_OS_CACHE=""
grab() {
    local rel="$1"
    if [[ -n "$REPO_ROOT" && -f "$REPO_ROOT/$rel" ]]; then
        printf '%s\n' "$REPO_ROOT/$rel"; return 0
    fi
    [[ -n "$_SETUP_OS_CACHE" ]] || _SETUP_OS_CACHE="$(mktemp -d "${TMPDIR:-/tmp}/setup-os.XXXXXX")"
    local dst="$_SETUP_OS_CACHE/$rel"
    mkdir -p "$(dirname "$dst")"
    if [[ ! -f "$dst" ]]; then
        curl -fsSL "$RAW_BASE/$rel" -o "$dst" || die "download failed: $rel ($RAW_BASE/$rel)"
    fi
    printf '%s\n' "$dst"
}

# --- Idempotent file block insertion ------------------------------------------
# ensure_block <file> <marker> <content>
# Inserts/updates a fenced block delimited by:
#   # >>> setup-os:<marker> >>>  ...  # <<< setup-os:<marker> <<<
# Returns 0 if the file changed, 1 if it was already current.
ensure_block() {
    local file="$1" marker="$2" content="$3"
    local begin="# >>> setup-os:${marker} >>>"
    local end="# <<< setup-os:${marker} <<<"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    local tmp; tmp="$(mktemp)"
    if grep -qF "$begin" "$file" && grep -qF "$end" "$file"; then
        awk -v b="$begin" -v e="$end" -v c="$content" '
            $0==b { print; print c; skip=1; next }
            $0==e { skip=0; print; next }
            skip==1 { next }
            { print }
        ' "$file" > "$tmp"
    else
        { grep -vF "$begin" "$file" | grep -vF "$end"
          printf '\n%s\n%s\n%s\n' "$begin" "$content" "$end"; } > "$tmp"
    fi
    if cmp -s "$tmp" "$file"; then
        rm -f "$tmp"; return 1
    fi
    cat "$tmp" > "$file"; rm -f "$tmp"; return 0
}

# --- xbrew --------------------------------------------------------------------
xbrew_bin() {
    if have xbrew; then command -v xbrew; return; fi
    [[ -x "$HOME/.xbrew/bin/xbrew" ]] && { printf '%s\n' "$HOME/.xbrew/bin/xbrew"; return; }
    return 1
}

# Print xbrew's dotted version (e.g. 0.4.0), or "" if unknown.
xbrew_version() {
    local xb; xb="$(xbrew_bin)" || return 1
    "$xb" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1
}

# True if $1 (dotted) >= $2 (dotted).
_ver_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]; }

ensure_xbrew() {
    if xbrew_bin >/dev/null; then
        local v; v="$(xbrew_version)"
        if [[ -n "$v" ]] && _ver_ge "$v" "$XBREW_MIN_VERSION"; then
            log "xbrew present ($v) — updating to latest..."
        else
            log "xbrew $v is older than $XBREW_MIN_VERSION (need bundle support) — updating..."
        fi
        "$(xbrew_bin)" self-update || warning "xbrew self-update failed (keeping current version)"
    else
        log "Installing xbrew..."
        curl -fsSL "$XBREW_INSTALL_URL" | bash || die "xbrew install failed"
        xbrew_bin >/dev/null || die "xbrew not found after install"
    fi
    export PATH="$(dirname "$(xbrew_bin)"):$PATH"
    local v; v="$(xbrew_version)"
    _ver_ge "${v:-0}" "$XBREW_MIN_VERSION" \
        || die "need xbrew >= $XBREW_MIN_VERSION for 'xbrew bundle' but have ${v:-unknown}. Try: XBREW_CHANNEL=preview bash <(curl -fsSL $XBREW_INSTALL_URL)"
    success "xbrew ready ($v)"
}

# --- Software (delegates entirely to `xbrew bundle`) --------------------------
# install_software <manifest.yaml> [manifest2.yaml ...]
# xbrew handles trust taps, install, version constraints, and reporting.
install_software() {
    (($#)) || die "install_software: no manifest given"
    ensure_xbrew
    "$(xbrew_bin)" bundle "$@"
}
