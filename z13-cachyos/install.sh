#!/usr/bin/env bash
# ==============================================================================
# setup-os / z13-cachyos / install.sh
#
# One-shot, idempotent machine setup for the ASUS ROG Flow Z13 (GZ302) on
# CachyOS + KDE Plasma 6 (Wayland).
#
#   curl -fsSL https://raw.githubusercontent.com/2lab-ai/setup-os/main/z13-cachyos/install.sh | bash
#
# What it does (each step is safe to repeat):
#   1. Install xbrew (if missing)
#   2. Configure shell PATH (zsh / fish / bash) — xbrew, linuxbrew, ~/.local/bin, cargo
#   3. Install apps from ../software.yaml (xbrew + Homebrew 2lab-ai/tap)
#   4. Install CachyOS desktop deps (fcitx5 Hangul IME, Spectacle, wl-clipboard, CJK fonts)
#   5. Apply mac-style KDE setup (IME + global shortcuts + per-login re-apply)
#
# Re-run any time: adding a tool to software.yaml and re-running installs only
# the new tool; config steps converge to the same state.
# ==============================================================================
set -euo pipefail

RAW_BASE="${SETUP_OS_RAW:-https://raw.githubusercontent.com/2lab-ai/setup-os/main}"

# Locate repo root when run from a clone; otherwise stay in curl|bash mode.
_src="${BASH_SOURCE[0]:-}"
if [[ -n "$_src" && -f "$_src" ]]; then
    REPO_ROOT="$(cd "$(dirname "$_src")/.." && pwd)"
else
    REPO_ROOT=""
fi
export REPO_ROOT RAW_BASE

# Fetch + source the shared library.
if [[ -n "$REPO_ROOT" && -f "$REPO_ROOT/lib/common.sh" ]]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib/common.sh"
else
    _tmp="$(mktemp)"
    curl -fsSL "$RAW_BASE/lib/common.sh" -o "$_tmp" || { echo "cannot fetch lib/common.sh" >&2; exit 1; }
    # shellcheck source=/dev/null
    source "$_tmp"
fi

# ------------------------------------------------------------------------------
[[ "$(uname -s)" == "Linux" ]] || die "z13-cachyos installer is Linux-only (got $(uname -s)). For macOS use macos/install.sh."
[[ "${EUID:-$(id -u)}" -ne 0 ]] || die "Run as your normal user, NOT root. sudo is invoked only where needed."
have curl || die "curl is required"

section "▐ setup-os — z13-cachyos"
if [[ -r /etc/os-release ]]; then
    _id="$(grep -oP '(?<=^ID=)[^"\n]+' /etc/os-release 2>/dev/null | tr -d '"' || true)"
    info "distro: ${_id:-unknown}   kernel: $(uname -r)   user: $(whoami)"
    [[ "$_id" == "cachyos" ]] || warning "This is tuned for CachyOS (detected: ${_id:-unknown}). Continuing anyway."
fi

# ------------------------------------------------------------------------------
# Step 0 — Snapshot (before anything changes)
#   Later steps edit bootloader kernel params, install packages, etc. Offer a
#   snapper snapshot up front so a bad run is one rollback away. Skipped if a
#   setup-os snapshot already exists (no piling up on re-runs).
# ------------------------------------------------------------------------------
section "0) Pre-setup snapshot"
maybe_snapshot() {
    have snapper || { info "snapper not installed — skipping snapshot"; return 0; }
    if ! ask_yn "Take a snapper snapshot before making changes? (recommended)" Y; then
        info "skipping snapshot (your call)"
        return 0
    fi
    if sudo snapper list 2>/dev/null | grep -q "setup-os pre-install"; then
        info "a 'setup-os pre-install' snapshot already exists — not creating another."
        return 0
    fi
    if sudo snapper create --type single --description "setup-os pre-install $(date +%F_%H%M)"; then
        success "snapshot created — roll back later with: sudo snapper undochange <n>..0 (or snapper rollback)"
    else
        warning "snapshot failed (is the snapper 'root' config set up? 'sudo snapper -c root create') — continuing"
    fi
}
maybe_snapshot

# ------------------------------------------------------------------------------
# Step 1 — xbrew
# ------------------------------------------------------------------------------
section "1) xbrew"
ensure_xbrew

# ------------------------------------------------------------------------------
# Step 2 — shell PATH (idempotent, sentinel-fenced)
# ------------------------------------------------------------------------------
section "2) Shell PATH"
configure_shell_path() {
    local brew_prefix="/home/linuxbrew/.linuxbrew"
    info "Managed PATH entries (prepended, login shells):"
    info "  • \$HOME/.xbrew/bin      (xbrew)"
    info "  • \$HOME/.local/bin       (user bins, e.g. claude)"
    info "  • ${brew_prefix}/bin  (brew shellenv)"
    info "  • \$HOME/.cargo/bin       (rust)"

    # POSIX shells: zsh + bash
    local posix_block
    posix_block="$(cat <<EOF
[ -d "\$HOME/.xbrew/bin" ] && export PATH="\$HOME/.xbrew/bin:\$PATH"
[ -d "\$HOME/.local/bin" ] && export PATH="\$HOME/.local/bin:\$PATH"
[ -x "${brew_prefix}/bin/brew" ] && eval "\$(${brew_prefix}/bin/brew shellenv)"
[ -d "\$HOME/.cargo/bin" ] && export PATH="\$HOME/.cargo/bin:\$PATH"
EOF
)"
    local f label
    for f in "$HOME/.zshrc" "$HOME/.bashrc"; do
        label="$(basename "$f")"
        if ensure_block "$f" "path" "$posix_block"; then
            success "$label: wrote/updated the setup-os:path block (4 entries above)"
        else
            info "$label: already current — no change"
        fi
    done

    # fish
    local fish_cfg="$HOME/.config/fish/config.fish"
    local fish_block
    fish_block="$(cat <<'EOF'
if test -d "$HOME/.xbrew/bin"; fish_add_path -g "$HOME/.xbrew/bin"; end
if test -d "$HOME/.local/bin"; fish_add_path -g "$HOME/.local/bin"; end
if test -x /home/linuxbrew/.linuxbrew/bin/brew; eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv); end
if test -d "$HOME/.cargo/bin"; fish_add_path -g "$HOME/.cargo/bin"; end
EOF
)"
    if ensure_block "$fish_cfg" "path" "$fish_block"; then
        success "config.fish: wrote/updated the setup-os:path block (4 entries above)"
    else
        info "config.fish: already current — no change"
    fi
}
configure_shell_path

# ------------------------------------------------------------------------------
# Step 3 — apps: common software.yaml + Arch-specific software.arch.yaml
# ------------------------------------------------------------------------------
section "3) Apps (software.yaml + software.arch.yaml)"
install_software "$(grab software.yaml)" "$(grab software.arch.yaml)" \
    || warning "Some apps failed — see summary above (safe to re-run)."

# ------------------------------------------------------------------------------
# Step 4 — CachyOS desktop dependencies for the mac-style layer
# ------------------------------------------------------------------------------
section "4) Desktop deps (fcitx5 Hangul, Spectacle, wl-clipboard, fonts)"
DESKTOP_PKGS=(
    fcitx5 fcitx5-hangul fcitx5-configtool fcitx5-qt fcitx5-gtk
    spectacle wl-clipboard noto-fonts-cjk noto-fonts-emoji
)
if have pacman; then
    missing=()
    for p in "${DESKTOP_PKGS[@]}"; do pacman -Qq "$p" &>/dev/null || missing+=("$p"); done
    if ((${#missing[@]})); then
        log "pacman -S --needed ${missing[*]}"
        sudo pacman -S --needed --noconfirm "${missing[@]}" || warning "pacman install had issues (continuing)"
    else
        success "all desktop packages already installed"
    fi
else
    warning "pacman not found — skipping desktop deps"
fi

# ------------------------------------------------------------------------------
# Step 5 — mac-style KDE setup (config + shortcuts only; packages handled above)
# ------------------------------------------------------------------------------
section "5) mac-style KDE setup"
MACSTYLE="$(grab z13-cachyos/setup-macstyle.sh)"
# --no-install: skip the script's own pacman/brew installs (already done in steps 3-4);
# apply IME config, fcitx5 hotkeys, KDE global shortcuts, autostart + per-login hook.
bash "$MACSTYLE" --no-install || warning "mac-style setup reported issues (see above)"

# ------------------------------------------------------------------------------
# Step 6 — Strix Halo hardware enablement (ASUS ROG Flow Z13 GZ302)
#   WiFi / GPU / Input / Audio / Display / Suspend fixes + z13ctl
#   (RGB, power profiles, TDP, fan curves).
#
#   Runs the VENDORED, security-reviewed copy under z13-cachyos/strix-halo/
#   (upstream th3cavalry/strix-halo-linux-setup @ 4a058283) — see that dir's
#   NOTICE.md (attribution/license) and SECURITY-REVIEW.md (verdict: no malware;
#   run with a snapshot first). "Reviewed == run": nothing is fetched from a
#   moving branch. Gaming/AI/hypervisor modules are skipped (--no-modules) — apps
#   are xbrew's job. The script auto-detects the device and no-ops the hardware
#   fixes on anything that isn't confirmed Strix Halo.
# ------------------------------------------------------------------------------
section "6) Strix Halo hardware setup (z13ctl, WiFi/GPU/Audio/Suspend fixes)"
install_strix_halo() {
    # Resolve the vendored tree: straight from the clone, or clone setup-os in
    # curl|bash mode so the reviewed files are present locally.
    local base
    if [[ -n "$REPO_ROOT" && -d "$REPO_ROOT/z13-cachyos/strix-halo" ]]; then
        base="$REPO_ROOT"
    else
        have git || { warning "git not found — skipping Strix Halo setup"; return 1; }
        local cache="${XDG_CACHE_HOME:-$HOME/.cache}/setup-os/repo"
        if [[ -d "$cache/.git" ]]; then
            git -C "$cache" pull -q --ff-only || warning "setup-os pull failed (using existing checkout)"
        else
            mkdir -p "$(dirname "$cache")"
            git clone -q https://github.com/2lab-ai/setup-os.git "$cache" \
                || { warning "setup-os clone failed — skipping Strix Halo setup"; return 1; }
        fi
        base="$cache"
    fi

    local script="$base/z13-cachyos/strix-halo/strix-halo-setup.sh"
    [[ -f "$script" ]] || { warning "vendored strix-halo not found at $script — skipping"; return 1; }

    info "Running vendored (reviewed) Strix Halo setup: hardware fixes + z13ctl, --no-modules."
    info "See z13-cachyos/strix-halo/SECURITY-REVIEW.md. Includes a system update and"
    info "bootloader kernel-param edits — a 'sudo snapper create' snapshot first is wise."
    sudo bash "$script" -y --no-modules \
        || warning "strix-halo setup reported issues (see output above)"
}
install_strix_halo

# ------------------------------------------------------------------------------
section "✅ Done — z13-cachyos"
info "Open a new shell (or: exec \$SHELL) to pick up PATH changes."
info "First run: log out / back in once for IME env vars + app-launch shortcuts."
info "Reboot to apply Strix Halo hardware/kernel changes; then: z13ctl status"
info "Re-run this any time; add tools to software.yaml to install more."
