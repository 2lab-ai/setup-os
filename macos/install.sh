#!/usr/bin/env bash
# ==============================================================================
# setup-os / macos / install.sh  —  PLACEHOLDER
#
#   curl -fsSL https://raw.githubusercontent.com/2lab-ai/setup-os/main/macos/install.sh | bash
#
# Minimal for now: installs Homebrew + xbrew and the shared software.yaml apps.
# The full macOS layer (defaults, dock, shell, app config) will be filled in
# later. Already idempotent — safe to re-run as it grows.
# ==============================================================================
set -euo pipefail

RAW_BASE="${SETUP_OS_RAW:-https://raw.githubusercontent.com/2lab-ai/setup-os/main}"

_src="${BASH_SOURCE[0]:-}"
if [[ -n "$_src" && -f "$_src" ]]; then
    REPO_ROOT="$(cd "$(dirname "$_src")/.." && pwd)"
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

[[ "$(uname -s)" == "Darwin" ]] || die "macos installer is macOS-only (got $(uname -s))."
have curl || die "curl is required"

section "▐ setup-os — macOS (placeholder)"
info "user: $(whoami)   macOS: $(sw_vers -productVersion 2>/dev/null || echo '?')   arch: $(uname -m)"

# 1) Homebrew + xbrew
section "1) Homebrew + xbrew"
ensure_homebrew || warning "Homebrew unavailable"
ensure_xbrew

# 2) shell PATH (zsh — default macOS shell)
section "2) Shell PATH"
brew_prefix="$([[ "$(uname -m)" == "arm64" ]] && echo /opt/homebrew || echo /usr/local)"
posix_block="$(cat <<EOF
[ -d "\$HOME/.xbrew/bin" ] && export PATH="\$HOME/.xbrew/bin:\$PATH"
[ -d "\$HOME/.local/bin" ] && export PATH="\$HOME/.local/bin:\$PATH"
[ -x "${brew_prefix}/bin/brew" ] && eval "\$(${brew_prefix}/bin/brew shellenv)"
[ -d "\$HOME/.cargo/bin" ] && export PATH="\$HOME/.cargo/bin:\$PATH"
EOF
)"
ensure_block "$HOME/.zprofile" "path" "$posix_block"
success "updated .zprofile"

# 3) apps
section "3) Apps (software.yaml)"
SW_YAML="$(grab software.yaml)"
install_software "$SW_YAML" || warning "Some apps failed — see summary (safe to re-run)."

section "✅ Done — macOS (placeholder)"
info "TODO: system defaults, dock, app config — coming later."
