#!/usr/bin/env bash
# ==============================================================================
# setup-os/lib/common.sh — shared helpers for every OS installer
#
# Sourced by z13-cachyos/install.sh, macos/install.sh, and the root install.sh.
# Works in two modes transparently:
#   - local clone   : sibling files are read straight from the repo
#   - curl | bash   : sibling files (software.yaml, sub-scripts) are fetched
#                     from GitHub raw on demand via grab()
#
# Everything here is idempotent: re-running only does the work still missing.
# ==============================================================================

# --- Config -------------------------------------------------------------------
RAW_BASE="${SETUP_OS_RAW:-https://raw.githubusercontent.com/2lab-ai/setup-os/main}"
XBREW_INSTALL_URL="https://raw.githubusercontent.com/2lab-ai/xbrew/HEAD/install.sh"

# REPO_ROOT is exported by the caller when running from a clone; empty in curl mode.
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

# --- Minimal YAML list reader (dependency-free) -------------------------------
# yaml_list <file> <top-level-key>  -> one item per line.
# Supports the flat schema used by software.yaml:
#   key:
#     - item        # inline comments and quotes are stripped
yaml_list() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 0
    awk -v want="$key" '
        /^[A-Za-z_][A-Za-z0-9_-]*:/ {
            cur=$0; sub(/:.*/,"",cur); insec=(cur==want); next
        }
        insec && /^[[:space:]]*-[[:space:]]/ {
            line=$0
            sub(/^[[:space:]]*-[[:space:]]*/,"",line)   # strip "- "
            sub(/[[:space:]]*#.*/,"",line)              # strip trailing comment
            gsub(/^[ \t"'\''"]+|[ \t"'\''"]+$/,"",line) # trim quotes/space
            if (line != "") print line
        }
    ' "$file"
}

# --- Idempotent file block insertion ------------------------------------------
# ensure_block <file> <marker> <content>
# Inserts/updates a fenced block delimited by:
#   # >>> setup-os:<marker> >>>  ...  # <<< setup-os:<marker> <<<
ensure_block() {
    local file="$1" marker="$2" content="$3"
    local begin="# >>> setup-os:${marker} >>>"
    local end="# <<< setup-os:${marker} <<<"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    local tmp; tmp="$(mktemp)"
    if grep -qF "$begin" "$file"; then
        # Replace the existing block in place.
        awk -v b="$begin" -v e="$end" -v c="$content" '
            $0==b { print; print c; skip=1; next }
            $0==e { skip=0; print; next }
            skip==1 { next }
            { print }
        ' "$file" > "$tmp"
        if ! grep -qF "$end" "$file"; then
            # Begin present but end missing (corrupted) — rebuild cleanly.
            { grep -vF "$begin" "$file"; printf '%s\n%s\n%s\n' "$begin" "$content" "$end"; } > "$tmp"
        fi
    else
        { cat "$file"; printf '\n%s\n%s\n%s\n' "$begin" "$content" "$end"; } > "$tmp"
    fi
    # Report whether anything actually changed: 0 = modified, 1 = already current.
    if cmp -s "$tmp" "$file"; then
        rm -f "$tmp"
        return 1
    fi
    cat "$tmp" > "$file"
    rm -f "$tmp"
    return 0
}

# --- xbrew --------------------------------------------------------------------
xbrew_bin() {
    if have xbrew; then command -v xbrew; return; fi
    [[ -x "$HOME/.xbrew/bin/xbrew" ]] && { printf '%s\n' "$HOME/.xbrew/bin/xbrew"; return; }
    return 1
}

ensure_xbrew() {
    if xbrew_bin >/dev/null; then
        local xb; xb="$(xbrew_bin)"
        log "xbrew present ($("$xb" --version 2>/dev/null)) — updating to latest..."
        "$xb" self-update || warning "xbrew self-update failed (keeping current version)"
        success "xbrew ready ($("$xb" --version 2>/dev/null))"
    else
        log "Installing xbrew..."
        curl -fsSL "$XBREW_INSTALL_URL" | bash || die "xbrew install failed"
        xbrew_bin >/dev/null || die "xbrew not found after install"
        success "xbrew installed ($("$(xbrew_bin)" --version 2>/dev/null))"
    fi
    # Make it usable in this process regardless of shell rc.
    export PATH="$(dirname "$(xbrew_bin)"):$PATH"
}

# --- Homebrew -----------------------------------------------------------------
brew_bin() {
    if have brew; then command -v brew; return; fi
    for p in /home/linuxbrew/.linuxbrew/bin/brew /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -x "$p" ]] && { printf '%s\n' "$p"; return; }
    done
    return 1
}

ensure_homebrew() {
    if brew_bin >/dev/null; then
        eval "$("$(brew_bin)" shellenv)"
        success "Homebrew present"
        return 0
    fi
    # Homebrew is installed *through xbrew* (recipe: brew) — xbrew is the only
    # thing we bootstrap via curl|bash; everything else routes through it.
    log "Installing Homebrew via xbrew..."
    ensure_xbrew
    "$(xbrew_bin)" install brew || { warning "xbrew install brew failed — tap-based tools may fail"; return 1; }
    brew_bin >/dev/null || { warning "brew not found after install"; return 1; }
    eval "$("$(brew_bin)" shellenv)"
    success "Homebrew installed (via xbrew)"
}

# --- Version helpers ----------------------------------------------------------
# Pull the first dotted version out of arbitrary `--version` output.
_extract_ver() { grep -oE '[0-9]+(\.[0-9]+){1,}' | head -1; }

# installed_version <manifest-name> -> prints the upstream dotted version, or "".
# Resolves per the backend xbrew recorded (pacman/aur -> pacman -Q, brew ->
# brew list, script/unknown -> ask the tool itself).
installed_version() {
    local name="$1" backend="" ref=""
    if [[ -f "$HOME/.xbrew/state.json" ]]; then
        read -r backend ref < <(awk -v k="\"$name\":" '
            index($0, k)        { f=1 }
            f && /"backend"/    { gsub(/[",]/,""); b=$2 }
            f && /"reference"/  { gsub(/[",]/,""); print b, $2; exit }
        ' "$HOME/.xbrew/state.json")
    fi
    case "$backend" in
        pacman|aur)
            have pacman && pacman -Q "$ref" 2>/dev/null \
                | awk '{print $2}' | sed -E 's/^[0-9]+://; s/-[0-9.]+$//'
            ;;
        brew)
            brew_bin >/dev/null 2>&1 && "$(brew_bin)" list --versions "$ref" 2>/dev/null | awk '{print $NF}'
            ;;
        *)  # script backend or not-yet-recorded -> ask the tool directly
            case "$name" in
                brew)        brew_bin >/dev/null 2>&1 && "$(brew_bin)" --version 2>/dev/null | _extract_ver ;;
                claude-code) have claude && claude --version 2>/dev/null | _extract_ver ;;
                *)           have "$name" && "$name" --version 2>/dev/null | _extract_ver ;;
            esac
            ;;
    esac
}

# version_satisfies <current> <op> <required>
#   returns 0 = ok, 1 = constraint violated, 2 = current version unknown
version_satisfies() {
    local a="$1" op="$2" b="$3"
    [[ -z "$op" || -z "$b" ]] && return 0     # no constraint
    [[ -z "$a" ]] && return 2                  # can't tell
    local lo; lo="$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)"
    case "$op" in
        "=="|"=") [[ "$a" == "$b" ]] ;;
        ">=")     [[ "$a" == "$b" || "$lo" == "$b" ]] ;;
        ">")      [[ "$a" != "$b" && "$lo" == "$b" ]] ;;
        "<=")     [[ "$a" == "$b" || "$lo" == "$a" ]] ;;
        "<")      [[ "$a" != "$b" && "$lo" == "$a" ]] ;;
        *) return 0 ;;
    esac
}

# --- Software manifest installer ----------------------------------------------
# install_software <manifest.yaml> [manifest2.yaml ...]
# Processes manifests in order (e.g. common software.yaml + per-OS software.arch.yaml).
# `trust:` -> `brew tap` (Homebrew itself comes via `xbrew install brew`); then
# every `xbrew:` entry installs through `xbrew install` (brew / pacman / AUR / recipe),
# and any `name OP version` constraint is verified against the resolved version.
#
# NOTE: manifest parsing + version resolution/enforcement is the "heavy" part that
# is planned to move into an `xbrew bundle` subcommand (Rust); this shell path is
# the interim that works with released xbrew today.
install_software() {
    local -a manifests=("$@")
    ((${#manifests[@]})) || die "install_software: no manifest given"
    local m
    for m in "${manifests[@]}"; do [[ -f "$m" ]] || die "manifest not found: $m"; done

    local -a ok=() fail=()
    ensure_xbrew
    local xb; xb="$(xbrew_bin)"

    # ---- Trust custom Homebrew taps FIRST (from all manifests), so xbrew's brew
    #      backend can resolve formulae published there (our 2lab-ai/tap). ----
    local taps; taps="$(for m in "${manifests[@]}"; do yaml_list "$m" trust; done | awk 'NF && !seen[$0]++')"
    if [[ -n "$taps" ]]; then
        if ensure_homebrew; then
            local bb; bb="$(brew_bin)" t
            while IFS= read -r t; do
                [[ -z "$t" ]] && continue
                log "trust tap: $t"
                "$bb" tap "$t" >/dev/null 2>&1 && success "tapped $t" || warning "brew tap $t failed"
            done <<< "$taps"
        else
            warning "Homebrew unavailable — tap-based tools may fail to resolve"
        fi
    fi

    # ---- Install every xbrew: entry (order preserved, duplicates collapsed) ----
    local entries; entries="$(for m in "${manifests[@]}"; do yaml_list "$m" xbrew; done | awk 'NF && !seen[$0]++')"
    local line name op ver cur rc
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        read -r name op ver _ <<< "$line"
        log "xbrew install ${name}${op:+ (need $op $ver)}"
        if ! "$xb" install "$name"; then
            fail+=("$name — install failed"); continue
        fi
        cur="$(installed_version "$name" 2>/dev/null || true)"
        if [[ -z "$op" ]]; then
            ok+=("$name${cur:+ $cur}")
        elif version_satisfies "$cur" "$op" "$ver"; then
            ok+=("$name ${cur:-?} (need $op $ver ✓)")
        else
            rc=$?
            if [[ "$rc" == "2" || -z "$cur" ]]; then
                warning "$name installed but version unreadable — cannot verify need $op $ver"
                ok+=("$name (installed; version unverified, wanted $op $ver)")
            else
                warning "$name $cur does NOT satisfy need $op $ver"
                fail+=("$name $cur — need $op $ver")
            fi
        fi
    done <<< "$entries"

    # ---- Report ----
    section "Software summary"
    local i
    ((${#ok[@]})) && { success "ok (${#ok[@]}):"; for i in "${ok[@]}"; do info "$i"; done; }
    if ((${#fail[@]})); then
        warning "failed (${#fail[@]}) — re-run after fixing, or add/adjust an xbrew recipe:"
        for i in "${fail[@]}"; do warning "  $i"; done
        return 1
    fi
    return 0
}
