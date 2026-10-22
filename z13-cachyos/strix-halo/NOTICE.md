# NOTICE — vendored third-party code

This directory (`z13-cachyos/strix-halo/`) is a **verbatim vendored copy** of a
third-party project, included in setup-os so that the exact code that has been
security-reviewed is the exact code that runs (no fetching a moving `main` at
install time).

| | |
|---|---|
| **Upstream project** | strix-halo-linux-setup |
| **Author** | th3cavalry (with Copilot) |
| **Source** | https://github.com/th3cavalry/strix-halo-linux-setup |
| **Vendored commit** | `4a058283ac035a34429eb1f30b1185de40270c65` |
| **Vendored on** | 2026-07-08 |
| **Upstream version** | 6.8.0 (see `VERSION`) |

## License status — please read

At the vendored commit the upstream repository **contains no LICENSE file**.
Absent an explicit license, the default legal position is "all rights reserved"
by the original author. This copy is retained here for reproducibility and
review of the exact bytes we execute; **all copyright remains with th3cavalry**.

setup-os itself is MIT (see the repo root `LICENSE`), but **that MIT license does
NOT extend to the files in this directory** — they are the upstream author's work.
If/when upstream adds a license we will conform this copy to it (or replace this
vendored tree with a git submodule pinned to the same commit).

## Local modifications

The tree is copied verbatim except that `.git/` and `.github/` were removed,
plus the local patch below. Do not hand-edit files here otherwise; to update,
re-vendor from a new upstream commit and re-run the security review
(`SECURITY-REVIEW.md`). **A re-vendor must re-apply (or confirm upstream has)
each local patch.**

| Date | Files | Change | Why |
|---|---|---|---|
| 2026-10-22 | `strix-halo-lib/gpu-manager.sh`, `docs/technical/kernel-support.md`, `docs/CHANGELOG.md`, `tests/gpu-manager-ppfeaturemask.sh` (new) | Stop writing `options amdgpu ppfeaturemask=0xffff7fff`; treat an existing active line (or a bootloader `amdgpu.ppfeaturemask=`) as outdated | The mask clears GFXOFF (`0x8000`), which keeps s2idle out of s0i3 on Strix Halo (GZ302EA: `total_hw_sleep=0`, battery drain while asleep) — see the `[Unreleased]` entry in `docs/CHANGELOG.md` |

## How it is invoked

`z13-cachyos/install.sh` runs `strix-halo-setup.sh -y --no-modules` via sudo:
hardware fixes (WiFi/GPU/Input/Audio/Display/Suspend) + z13ctl only. The
gaming / AI / hypervisor **modules are not executed**. See `SECURITY-REVIEW.md`
for what that means for the risk profile.
