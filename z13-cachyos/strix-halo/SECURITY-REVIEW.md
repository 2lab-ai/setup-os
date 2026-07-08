# Security Review — vendored strix-halo-linux-setup

- **Target:** the vendored tree in this directory (upstream
  `th3cavalry/strix-halo-linux-setup`, commit `4a058283`, v6.8.0).
- **Reviewed:** 2026-07-08, by Claude (Opus 4.8) — a 4-way parallel read of every
  shell library, executed script, and Python module, plus the entry script.
- **How it runs here:** `z13-cachyos/install.sh` invokes
  `sudo strix-halo-setup.sh -y --no-modules` — **hardware fixes + z13ctl only**;
  the gaming / AI / hypervisor modules are **not executed**.

## Verdict

> **No malware, backdoor, data exfiltration, telemetry, or hidden network
> callback was found in any file.** It is a legitimate hardware-enablement
> installer. The residual risk is a matter of *supply-chain trust and blast
> radius*, not malicious code — and vendoring + `--no-modules` removes most of it.

**Safe to run on the target device (ASUS ROG Flow Z13 / GZ302) given the
mitigations below.** The single most important precaution is unchanged from the
original review: **take a filesystem snapshot first** (the script edits
bootloader kernel parameters, and a few of those edits are not individually
backed up).

## What vendoring changed (why this copy is safer than `curl | bash`)

The upstream design's biggest weakness is that it **downloads code and runs it
as root with no checksum/signature/pinning** — missing libraries are fetched and
`source`d, modules are fetched and `bash`ed, etc. By vendoring the **entire**
tree and pinning to a reviewed commit, those fetch-and-execute paths **no longer
fire**, because the files are already present locally:

| Upstream remote-exec path | Status here |
|---|---|
| Fetch missing `strix-halo-lib/*.sh` and `source` as root | **Eliminated** — all 12 libs vendored |
| Fetch + `bash` `scripts/fix-suspend.sh` | **Eliminated** — vendored |
| Fetch + `bash` `modules/{gaming,llm,hypervisor}.sh` | **Eliminated** — vendored *and* `--no-modules` |
| Fetch + `bash` `command-center/*` | **Eliminated** — vendored |
| `curl https://ollama.com/install.sh | sh` (llm module) | **Not executed** (`--no-modules`) |
| `curl .../distrobox/install | sh` (toolboxes) | **Not executed** (opt-in, module) |
| Repo-name mismatch (`GITHUB_RAW_URL` → `GZ302-Linux-Setup`) | **Moot** — nothing is fetched |

## Residual risks (present even with vendoring)

These are the things vendoring does **not** remove — review these before running:

1. **z13ctl binary is downloaded, unverified, and granted passwordless root.**
   `strix-halo-setup.sh` installs `z13ctl` from `dahui/z13ctl` GitHub releases
   (`.tar.gz`/`.deb`/`.rpm`) with **no checksum/GPG check**, to `/usr/local/bin`,
   runs it as a root-adjacent daemon, and writes `/etc/sudoers.d/strix-halo`
   granting the user **NOPASSWD** to run `z13ctl` (+ `pwrcfg`/`gz302-rgb`/`rrcfg`)
   as root. The sudoers file is `visudo -c`-validated and scoped to those
   binaries — good — but this means: (a) you trust the `dahui/z13ctl` release
   assets and that GitHub account; (b) if `z13ctl` is ever writable by your user,
   or exposes any file-write/arbitrary-exec subcommand, that becomes a root
   primitive. This is the **main trust you are accepting**. It is inherent to
   using z13ctl at all (the same model as asusctl/g-helper). To avoid it, run
   with `--no-z13ctl` (loses RGB/power/TDP/fan control).

2. **Bootloader / kernel-cmdline edits without a per-function backup.**
   `display-fix.sh` (PSR-SU `amdgpu.dcdebugmask=0x600`) and the
   `ensure_*_kernel_param` helpers in `utils.sh` do in-place `sed`/append on
   `/etc/default/grub`, `/etc/kernel/cmdline`, systemd-boot/limine/refind entries
   and then regenerate initramfs/grub — **without** the timestamped `.bak` that
   `distro-manager.sh` makes. Brick risk is *mitigated* (edits are idempotent,
   guarded by `grep` checks, and the injected token is a fixed literal), but a
   snapshot is the real safety net. **→ `sudo snapper create` before running.**

3. **Third-party / AUR trust for optional bits.** `yay` (if no AUR helper),
   `openai-codex-bin`-style AUR builds, etc. use the normal AUR trust model
   (makepkg building unsigned PKGBUILDs). Standard for Arch; noted for awareness.

## Findings (consolidated, most severe first)

Severity reflects the risk **in our vendored `--no-modules` invocation**.

| Sev | File:line | Finding | Notes / mitigation |
|---|---|---|---|
| HIGH | strix-halo-setup.sh:490–514, install-policy.sh:17 | z13ctl downloaded unverified + NOPASSWD sudo grant | See residual risk #1. `visudo -c`-validated, scoped. Accept or `--no-z13ctl`. |
| MEDIUM | display-fix.sh:270–446; utils.sh:376–439,764–847 | Bootloader/cmdline `sed` edits with no per-function backup | Idempotent + static literal params; **snapshot first**. |
| MEDIUM | strix-halo-setup.sh:564 | `eval echo "~${real_user}"` — `eval` on a `SUDO_USER`-derived value | Practically low (invoker is already privileged); `getent passwd` would be safer. |
| MEDIUM | install-tray.sh:111–149 | Login autostart `Exec=python3 $APP_PY` points at the install dir | If the dashboard installs, the tray runs from the setup-os checkout each login; keep that path non-world-writable. Same-user trust, not priv-esc. |
| LOW | input-manager.sh:462 | `$product_id` interpolated into a hwdb file | Sanitized to 4 hex digits (`grep -oP '0b05:[\da-f]{4}'`); no injection. |
| LOW | device-manager.sh / setup.sh:838 | DMI strings written into `/etc/strix-halo/tray.conf` unsanitized | Requires firmware/root control to abuse; consumed as a UI label only. |
| INFO | gpu/wifi/input/audio/display managers | Many `/etc/modprobe.d`, `/etc/udev`, config writes | Content is **static** quoted heredocs; writes are guarded/idempotent; correct perms. |
| INFO | distro-manager.sh:245 | Reads `/etc/os-release` `ID` via `grep` not `source` | Deliberately injection-safe (author's own comment). |
| INFO (not executed) | modules/llm.sh:157, 45; gaming.sh, hypervisor.sh | `curl | sh` (Ollama), remote `source` fallback, OLLAMA_HOST=0.0.0.0, docker-group add | **Skipped under `--no-modules`.** Vendored copies reviewed; if you ever drop `--no-modules`, re-read these. |

**Full network inventory:** every URL any file would contact is a genuine
upstream (`raw.githubusercontent.com/th3cavalry/...`, `dahui/z13ctl` releases,
`ollama.com`, `lmstudio.ai`, `pytorch.org`, `ghcr.io`, `aur.archlinux.org`,
`github.com`/`1.1.1.1` for a connectivity check). No unexpected domains, no
`nc`/reverse shells, no encoded payloads, no telemetry beacons. In our
invocation, the only network endpoint actually contacted is the **z13ctl release
download** (+ a connectivity check and any distro package installs).

## Recommendation

Run it — on the GZ302, with these guardrails:

1. `sudo snapper create --type single --description "before strix-halo"` first.
2. Accept the z13ctl trust (or pass `--no-z13ctl` to skip it).
3. Reboot afterward to apply kernel/bootloader changes; verify with `z13ctl status`.
4. Re-vendoring to a newer upstream commit **requires re-running this review**.
