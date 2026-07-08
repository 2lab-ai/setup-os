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
├── software.yaml           # COMMON manifest — my cross-platform tools (all OSes)
├── software.arch.yaml      # Arch/CachyOS-specific apps (+ pinned versions)
├── software.macos.yaml     # macOS-specific apps
├── lib/
│   └── common.sh           # shared helpers: xbrew/brew bootstrap, YAML, versions, idempotent config
├── z13-cachyos/
│   ├── install.sh          # full CachyOS setup (xbrew + apps + desktop + mac-style KDE + hardware)
│   ├── setup-macstyle.sh   # KDE Plasma mac-style IME + global shortcuts (per-login apply)
│   └── strix-halo/         # vendored GZ302 hardware setup (see NOTICE.md + SECURITY-REVIEW.md)
└── macos/
    └── install.sh          # placeholder — xbrew + apps only, for now
```

Each OS installer applies the **common** `software.yaml` first, then its
**per-OS** manifest on top (`z13-cachyos` → `software.arch.yaml`, `macos` →
`software.macos.yaml`). Shared cross-platform tools live in the common file;
only genuinely OS-specific apps (and their per-OS version pins) are split out.

## Adding software

Put shared tools in [`software.yaml`](software.yaml); put OS-only tools in
[`software.arch.yaml`](software.arch.yaml) / [`software.macos.yaml`](software.macos.yaml).
Re-run the installer — only the new/unsatisfied tool is touched.
**Everything installs through xbrew.**

```yaml
trust:                       # custom Homebrew taps registered FIRST
  - 2lab-ai/tap
xbrew:                       # installed via `xbrew install`
  - brew                     # no constraint = latest
  - claude-code >= 2.1.204   # minimum-version baseline, verified after install
  - llmux >= 0.2.15
```

- **xbrew** ([2lab-ai/xbrew](https://github.com/2lab-ai/xbrew)) is the one
  installer: `xbrew install <name>` picks the right backend per OS (brew /
  pacman / AUR / curated recipe) and records it so uninstall routes correctly.
- The **only** thing bootstrapped via `curl … | bash` is xbrew itself.
  Homebrew, when needed, is installed by xbrew (`xbrew install brew`).
- **trust** taps are registered before installing so xbrew's brew backend can
  resolve formulae from our own `2lab-ai/tap` (llmux, herdr-mx-preview).
- **Version tags** (`>=`, `==`, `>`, `<=`, `<`) are optional per line. xbrew
  installs the latest; the tag is a baseline that is checked after install and
  reported if unmet. Common-tool versions are shared across OSes (one build);
  OS-specific pins live in the per-OS manifests.

## Idempotency

Every step is re-runnable and converges to the same state:

- app installs skip anything already present (xbrew records install state),
- shell PATH edits live in sentinel-fenced blocks (`# >>> setup-os:path >>>`) that
  are replaced in place, never duplicated,
- desktop packages use `pacman --needed`,
- `setup-macstyle.sh` overwrites its config/shortcut files to a known-good state
  and is run with `--no-install` (package installs are centralized in `install.sh`).

## z13-cachyos details

Steps: install xbrew → configure shell PATH (zsh/fish/bash) → install
`software.yaml` + `software.arch.yaml` apps → install desktop deps (fcitx5
Hangul IME, Spectacle, wl-clipboard, CJK fonts) → apply mac-style KDE setup
(Shift+Space Han/Eng toggle, mac-like global shortcuts, per-login re-apply hook)
→ **Strix Halo hardware enablement**.

The last step runs a **vendored, security-reviewed copy** of
[th3cavalry/strix-halo-linux-setup](https://github.com/th3cavalry/strix-halo-linux-setup)
(commit `4a058283`), living in [`z13-cachyos/strix-halo/`](z13-cachyos/strix-halo/).
It is vendored (not fetched from a moving branch) so the reviewed bytes are the
executed bytes — see that directory's
[`NOTICE.md`](z13-cachyos/strix-halo/NOTICE.md) (attribution; upstream has no
license — copyright remains th3cavalry's) and
[`SECURITY-REVIEW.md`](z13-cachyos/strix-halo/SECURITY-REVIEW.md) (verdict: no
malware; residual trust is the z13ctl binary; snapshot first).

It applies GZ302 hardware fixes — WiFi, GPU, Input, Audio, Display, Suspend — and
installs **z13ctl** (RGB, power profiles, TDP, fan curves). Gaming/AI/hypervisor
modules are skipped (`--no-modules`); apps are xbrew's job. It auto-detects the
device and no-ops the fixes on non-Strix-Halo hardware. **Note:** this step
includes a system update and edits bootloader kernel params — the installer's
**step 0 offers a snapper snapshot** (y/n, default yes) before anything changes,
so a bad run is one rollback away.

After the first run, log out and back in once to fully activate the IME
environment variables and app-launch shortcuts, and reboot to apply the
hardware/kernel changes.

---

MIT © 2026 2lab.ai
