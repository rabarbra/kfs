#!/usr/bin/env bash
# Boot the in-kernel test variant under QEMU, capture serial output, return
# 0 if the runner reported "ALL PASS", 1 otherwise.
#
# Expects the kernel built with -Dtest=true at zig-out/bin/kfs.bin.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="${ROOT_DIR}/zig-out/bin/kfs.bin"
GRUB_CFG="${ROOT_DIR}/tests/kernel/grub.cfg"
STAGE="${ROOT_DIR}/.zig-cache/test-iso"
ISO="${ROOT_DIR}/.zig-cache/kfs-test.iso"
LOG="${ROOT_DIR}/.zig-cache/kfs-test.serial.log"

if [ ! -f "${KERNEL}" ]; then
    echo "no kernel at ${KERNEL} — run 'zig build -Dtest=true' first" >&2
    exit 2
fi

GRUB_MKRESCUE="${GRUB_MKRESCUE:-}"
if [ -z "${GRUB_MKRESCUE}" ]; then
    if command -v grub-mkrescue >/dev/null 2>&1; then
        GRUB_MKRESCUE=grub-mkrescue
    elif command -v i686-elf-grub-mkrescue >/dev/null 2>&1; then
        GRUB_MKRESCUE=i686-elf-grub-mkrescue
    else
        echo "no grub-mkrescue / i686-elf-grub-mkrescue on PATH" >&2
        exit 2
    fi
fi

QEMU="${QEMU:-}"
if [ -z "${QEMU}" ]; then
    if command -v qemu-system-i386 >/dev/null 2>&1; then
        QEMU=qemu-system-i386
    elif command -v qemu-system-x86_64 >/dev/null 2>&1; then
        QEMU=qemu-system-x86_64
    else
        echo "no qemu-system-i386 / qemu-system-x86_64 on PATH" >&2
        exit 2
    fi
fi

rm -rf "${STAGE}"
mkdir -p "${STAGE}/boot/grub"
cp "${KERNEL}" "${STAGE}/kfs.bin"
cp "${GRUB_CFG}" "${STAGE}/boot/grub/grub.cfg"

"${GRUB_MKRESCUE}" -o "${ISO}" "${STAGE}" 2>/dev/null

# isa-debug-exit translates `outl 0xf4, V` into qemu exit code (V<<1)|1.
# 0x10 (PASS) → 33, 0x11 (FAIL) → 35.
set +e
"${QEMU}" \
    -cdrom "${ISO}" \
    -m 1G \
    -display none \
    -serial "file:${LOG}" \
    -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >/dev/null 2>&1
QEMU_RC=$?
set -e

echo "---- serial log ----"
cat "${LOG}" || true
echo "---- end log -------"
echo "qemu exit code: ${QEMU_RC}"

case "${QEMU_RC}" in
    33) echo "RESULT: ALL PASS"; exit 0 ;;
    35) echo "RESULT: FAILURES"; exit 1 ;;
    *)  echo "RESULT: unexpected qemu exit (${QEMU_RC})"; exit 2 ;;
esac
