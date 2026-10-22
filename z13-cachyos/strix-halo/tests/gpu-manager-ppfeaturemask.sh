#!/usr/bin/env bash
set -euo pipefail

# Regression checks for the amdgpu ppfeaturemask policy in gpu-manager.sh:
# the setup must not write ppfeaturemask=0xffff7fff (it clears GFXOFF, which
# keeps s2idle out of s0i3), must treat an old amdgpu.conf that carries it as
# not configured so a re-run rewrites it, and must flag a leftover
# amdgpu.ppfeaturemask= on the kernel cmdline.
#
# Runs without root. The library is copied into a temp dir with every
# /etc, /boot and /efi path rewritten to temp files, and
# gpu_regenerate_initramfs is stubbed, so nothing on the host is modified.
#
# Usage: tests/gpu-manager-ppfeaturemask.sh [path/to/gpu-manager.sh]
#        (or GPU_MANAGER_LIB=path/to/gpu-manager.sh)

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_SRC="${1:-${GPU_MANAGER_LIB:-${SCRIPT_DIR}/../strix-halo-lib/gpu-manager.sh}}"

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gpu-manager-ppfeaturemask.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

LIB_COPY="${WORK_DIR}/gpu-manager.sh"
MODPROBE_CONF="${WORK_DIR}/amdgpu.conf"
GRUB_CONF="${WORK_DIR}/grub"
LIMINE_CONF="${WORK_DIR}/limine-etc.conf"
INITRAMFS_CALLS="${WORK_DIR}/initramfs.calls"

ASSERTIONS_PASSED=0
ASSERTIONS_FAILED=0

record_pass() {
    printf 'PASS: %s\n' "$1"
    ASSERTIONS_PASSED=$((ASSERTIONS_PASSED + 1))
}

record_fail() {
    printf 'FAIL: %s\n' "$1"
    ASSERTIONS_FAILED=$((ASSERTIONS_FAILED + 1))
}

expect_eq() {
    local label="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$actual" == "$expected" ]]; then
        record_pass "$label"
    else
        record_fail "$label (expected: $expected, actual: $actual)"
    fi
}

print_case() {
    printf '\nCASE: %s\n' "$1"
}

# amdgpu.conf exactly as the 6.8.0 writer produced it (active GFXOFF-clearing mask)
write_old_modprobe_conf() {
    cat > "$1" <<'EOF'
# AMD GPU configuration for Radeon 8060S (RDNA 3.5, integrated)
# Strix Halo specific: Phoenix/Navi33 equivalent
# Enable all power features for better performance and efficiency
# ROCm-compatible for AI/ML workloads
# 0xffff7fff: all bits enabled except bit 15 (GFXOFF) — de-risks RDNA 3.5
# GFXOFF causes hangs under rapid power-state transitions on Strix Halo iGPU.
options amdgpu ppfeaturemask=0xffff7fff
# abmlevel=0: disable Adaptive Backlight Management — not applicable/safe on OLED
# (OLED panels report oled=1 in DPCD ext_caps; ABM is skipped by driver anyway)
options amdgpu abmlevel=0
# sg_display=0: disable scatter-gather display on this APU.
# Kernel doc: "Set to 0 to disable if you experience flickering or other
# issues under memory pressure" — directly applies to GZ302 OLED flicker.
options amdgpu sg_display=0
# cwsr_enable=0: disable Compute Wavefront Save-Restore.
# Prevents GPU hangs and graphical artifacts on Strix Halo (RDNA 3.5)
# caused by register file synchronization issues in early 2026 kernels.
options amdgpu cwsr_enable=0
EOF
}

# Copy the library with system paths redirected into WORK_DIR. Longer paths
# come first: /efi/EFI/refind/refind.conf is a suffix of the /boot/efi one.
prepare_library() {
    if [[ ! -f "$LIB_SRC" ]]; then
        printf 'ERROR: library not found: %s\n' "$LIB_SRC"
        exit 2
    fi

    sed -e "s|/etc/modprobe.d/amdgpu.conf|${MODPROBE_CONF}|g" \
        -e "s|/etc/default/grub|${GRUB_CONF}|g" \
        -e "s|/etc/kernel/cmdline|${WORK_DIR}/kernel-cmdline|g" \
        -e "s|/etc/limine/limine.conf|${LIMINE_CONF}|g" \
        -e "s|/boot/limine/limine.conf|${WORK_DIR}/limine-boot.conf|g" \
        -e "s|/boot/limine.cfg|${WORK_DIR}/limine-boot.cfg|g" \
        -e "s|/boot/refind_linux.conf|${WORK_DIR}/refind_linux.conf|g" \
        -e "s|/boot/EFI/refind/refind.conf|${WORK_DIR}/refind-boot-EFI.conf|g" \
        -e "s|/boot/efi/EFI/refind/refind.conf|${WORK_DIR}/refind-boot-efi.conf|g" \
        -e "s|/efi/EFI/refind/refind.conf|${WORK_DIR}/refind-efi.conf|g" \
        -e "s|/etc/mkinitcpio.conf|${WORK_DIR}/mkinitcpio.conf|g" \
        "$LIB_SRC" > "$LIB_COPY"

    # Fail closed if the library gained a host path this test does not redirect.
    if grep -nE '(^|[^[:alnum:]_.-])/(etc|boot|efi)/' "$LIB_COPY"; then
        printf 'ERROR: unredirected /etc, /boot or /efi path in library copy (see above)\n'
        exit 2
    fi

    # Never run mkinitcpio/dracut/update-initramfs; count calls instead.
    cat >> "$LIB_COPY" <<EOF

gpu_regenerate_initramfs() {
    echo called >> "${INITRAMFS_CALLS}"
    return 0
}
EOF
}

reset_files() {
    rm -f "$MODPROBE_CONF" "$GRUB_CONF" "$LIMINE_CONF" "$INITRAMFS_CALLS"
}

checker_state() {
    if gpu_ppfeaturemask_configured; then
        echo configured
    else
        echo not-configured
    fi
}

override_state() {
    if ! declare -f gpu_kernel_ppfeaturemask_override_set >/dev/null 2>&1; then
        echo missing-function
    elif gpu_kernel_ppfeaturemask_override_set; then
        echo present
    else
        echo absent
    fi
}

active_ppfeaturemask_state() {
    if grep -Eq '^[[:space:]]*options[[:space:]]+amdgpu[[:space:]][^#]*ppfeaturemask=' "$MODPROBE_CONF"; then
        echo present
    else
        echo absent
    fi
}

initramfs_call_count() {
    if [[ -f "$INITRAMFS_CALLS" ]]; then
        wc -l < "$INITRAMFS_CALLS" | tr -d ' '
    else
        echo 0
    fi
}

apply_exit_code() {
    if gpu_apply_modprobe_config >/dev/null 2>&1; then
        echo 0
    else
        echo "$?"
    fi
}

# Hardware probes for gpu_print_status
lspci() { echo '00:00.0 VGA compatible controller [0300]: AMD Strix Halo [1002:1586]'; }
lsmod() { echo 'amdgpu 1 0'; }
dmesg() { :; }

print_status_output() {
    gpu_print_status 2>/dev/null || true
}

test_old_file_reads_not_configured() {
    print_case "(a) old amdgpu.conf with active ppfeaturemask line"
    reset_files
    write_old_modprobe_conf "$MODPROBE_CONF"
    expect_eq "old file is not configured" "not-configured" "$(checker_state)"
}

test_commented_ppfeaturemask_is_ignored() {
    print_case "(c) only a commented ppfeaturemask line plus the 3 options"
    reset_files
    write_old_modprobe_conf "$MODPROBE_CONF.old"
    sed 's|^options amdgpu ppfeaturemask=|# options amdgpu ppfeaturemask=|' \
        "$MODPROBE_CONF.old" > "$MODPROBE_CONF"
    rm -f "$MODPROBE_CONF.old"
    expect_eq "commented ppfeaturemask is configured" "configured" "$(checker_state)"
}

test_single_line_options_with_ppfeaturemask() {
    print_case "(c2) one options line carrying ppfeaturemask among other params"
    reset_files
    printf 'options amdgpu abmlevel=0 sg_display=0 cwsr_enable=0 ppfeaturemask=0xffff7fff\n' > "$MODPROBE_CONF"
    expect_eq "single-line ppfeaturemask is not configured" "not-configured" "$(checker_state)"
}

test_rerun_rewrites_old_file() {
    print_case "(d) re-run on an old file rewrites it; second run is a no-op"
    reset_files
    write_old_modprobe_conf "$MODPROBE_CONF"

    expect_eq "first apply exit code" "0" "$(apply_exit_code)"
    expect_eq "rewritten file has no active ppfeaturemask" "absent" "$(active_ppfeaturemask_state)"

    local opt
    for opt in abmlevel=0 sg_display=0 cwsr_enable=0; do
        if grep -q "^options amdgpu ${opt}\$" "$MODPROBE_CONF"; then
            record_pass "rewritten file keeps options amdgpu ${opt}"
        else
            record_fail "rewritten file keeps options amdgpu ${opt}"
        fi
    done
    expect_eq "initramfs regenerated once on rewrite" "1" "$(initramfs_call_count)"

    print_case "(b) file written by the current writer"
    expect_eq "new writer output is configured" "configured" "$(checker_state)"

    local calls_before
    calls_before=$(initramfs_call_count)
    echo "# idempotency-marker" >> "$MODPROBE_CONF"
    expect_eq "second apply exit code" "0" "$(apply_exit_code)"
    if grep -q "idempotency-marker" "$MODPROBE_CONF"; then
        record_pass "second apply leaves the file untouched"
    else
        record_fail "second apply leaves the file untouched (file was rewritten)"
    fi
    expect_eq "initramfs not regenerated on second apply" "$calls_before" "$(initramfs_call_count)"
}

test_bootloader_override_detection() {
    print_case "(e) amdgpu.ppfeaturemask on the kernel cmdline"
    reset_files
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet amdgpu.ppfeaturemask=0xffff7fff"\n' > "$GRUB_CONF"
    expect_eq "active GRUB override is present" "present" "$(override_state)"

    printf '#GRUB_CMDLINE_LINUX_DEFAULT="quiet amdgpu.ppfeaturemask=0xffff7fff"\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' > "$GRUB_CONF"
    expect_eq "commented GRUB override is absent" "absent" "$(override_state)"

    rm -f "$GRUB_CONF"
    printf 'quiet amdgpu.ppfeaturemask=0xfff7bfff rw\n' > "$LIMINE_CONF"
    expect_eq "Limine override with any value is present" "present" "$(override_state)"

    rm -f "$LIMINE_CONF"
    expect_eq "no bootloader configs is absent" "absent" "$(override_state)"
}

test_status_warnings() {
    print_case "(f) gpu_print_status warnings"
    local status

    reset_files
    write_old_modprobe_conf "$MODPROBE_CONF"
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet amdgpu.ppfeaturemask=0xffff7fff"\n' > "$GRUB_CONF"
    status=$(print_status_output)
    if [[ "$status" == *"modprobe config missing or outdated"* ]]; then
        record_pass "status flags the old modprobe file"
    else
        record_fail "status flags the old modprobe file"
    fi
    if [[ "$status" == *"set on the kernel cmdline"* ]]; then
        record_pass "status warns about the cmdline override"
    else
        record_fail "status warns about the cmdline override"
    fi

    reset_files
    write_old_modprobe_conf "$MODPROBE_CONF"
    gpu_apply_modprobe_config >/dev/null 2>&1 || true
    status=$(print_status_output)
    if [[ "$status" != *"modprobe config missing or outdated"* && \
          "$status" != *"set on the kernel cmdline"* && \
          "$status" == *"GPU Status"* ]]; then
        record_pass "status is quiet after rewrite with no cmdline override"
    else
        record_fail "status is quiet after rewrite with no cmdline override"
    fi
}

main() {
    printf 'Library under test: %s\n' "$LIB_SRC"
    prepare_library

    # shellcheck source=/dev/null
    source "$LIB_COPY"

    test_old_file_reads_not_configured
    test_commented_ppfeaturemask_is_ignored
    test_single_line_options_with_ppfeaturemask
    test_rerun_rewrites_old_file
    test_bootloader_override_detection
    test_status_warnings

    printf '\nAssertions passed: %s\n' "$ASSERTIONS_PASSED"

    if [[ "$ASSERTIONS_FAILED" -gt 0 ]]; then
        printf 'Assertions failed: %s\n' "$ASSERTIONS_FAILED"
        return 1
    fi

    printf 'All gpu-manager ppfeaturemask regression checks passed.\n'
}

main "$@"
