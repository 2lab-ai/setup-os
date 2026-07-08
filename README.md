# setup-os

One-command, **idempotent** machine setup for 2lab-ai environments.
Pick a fresh machine, run one line, get all your tools + config. Re-run any
time — only what's missing gets installed.

## Quick start

Auto-detect the OS and do everything:

```sh
curl -fsSL https://raw.githubusercontent.com/2lab-ai/setup-os/main/install.sh | bash
```

Or target a specific profile directly:

```sh
# ASUS ROG Flow Z13 (GZ302) on CachyOS + KDE Plasma 6
curl -fsSL https://raw.githubusercontent.com/2lab-ai/setup-os/main/z13-cachyos/install.sh | bash

# macOS (placeholder for now)
curl -fsSL https://raw.githubusercontent.com/2lab-ai/setup-os/main/macos/install.sh | bash
```

`install.sh` detects the platform (`Darwin` → macOS, `Linux` → z13-cachyos) and
hands off to the matching installer. Override with `... | bash -s -- macos`.

## Layout

```
setup-os/
├── install.sh              # OS auto-detect → dispatch
├── software.yaml           # declarative app manifest (the single source of truth)
├── lib/
│   └── common.sh           # shared helpers: xbrew/brew bootstrap, YAML, idempotent config
├── z13-cachyos/
│   ├── install.sh          # full CachyOS setup (xbrew + apps + desktop + mac-style KDE)
│   └── setup-macstyle.sh   # KDE Plasma mac-style IME + global shortcuts (per-login apply)
└── macos/
    └── install.sh          # placeholder — Homebrew + xbrew + apps only, for now
```

## Adding software

Edit [`software.yaml`](software.yaml) and re-run the installer — only the new
tool installs.

```yaml
xbrew:            # installed via `xbrew install` (brew / pacman / AUR / recipe)
  - telegram
  - slack
  - claude-code
  - nomachine
  - codex
brew_taps:        # custom Homebrew taps
  - 2lab-ai/tap
brew:             # straight Homebrew — our own tools on 2lab-ai/tap
  - llmux
  - herdr-mx-preview
```

- **xbrew** ([2lab-ai/xbrew](https://github.com/2lab-ai/xbrew)) is the primary
  installer: `xbrew install <name>` picks the right backend per OS and records
  it so uninstall routes correctly. Missing recipe → native package manager / AUR fallback.
- **brew** section is for tools published on `2lab-ai/tap` (llmux, herdr-mx-preview).

## Idempotency

Every step is re-runnable and converges to the same state:

- app installs skip anything already present (xbrew state + `brew list`),
- shell PATH edits live in sentinel-fenced blocks (`# >>> setup-os:path >>>`) that
  are replaced in place, never duplicated,
- desktop packages use `pacman --needed`,
- `setup-macstyle.sh` overwrites its config/shortcut files to a known-good state
  and is run with `--no-install` (package installs are centralized in `install.sh`).

## z13-cachyos details

Steps: install xbrew → configure shell PATH (zsh/fish/bash) → install
`software.yaml` apps → install desktop deps (fcitx5 Hangul IME, Spectacle,
wl-clipboard, CJK fonts) → apply mac-style KDE setup (Shift+Space Han/Eng
toggle, mac-like global shortcuts, per-login re-apply hook).

After the first run, log out and back in once to fully activate the IME
environment variables and app-launch shortcuts.

---

MIT © 2026 2lab.ai
