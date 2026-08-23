#!/usr/bin/env bash
# Build a test rootfs that boots /bin/init = our integration test runner,
# then boot it under QEMU and grep the serial log for the pass/fail marker.
#
# Prereqs: a working kernel at zig-out/bin/kfs.bin, a base rootfs image at
# release/build/rootfs-full.img (produced by `make prepare-rootfs && ...`),
# and debugfs / qemu / grub-mkimage / mke2fs / sgdisk on PATH.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="${ROOT_DIR}/zig-out/bin/kfs.bin"
RUNNER_SRC="${ROOT_DIR}/tests/integration/runner.c"
RUNNER_BIN="${ROOT_DIR}/.zig-cache/init_test"
BASE_ROOTFS="${ROOT_DIR}/release/build/rootfs-min.img"
TEST_ROOTFS="${ROOT_DIR}/release/build/rootfs-test.img"
TEST_DISK="${ROOT_DIR}/.zig-cache/kfs-test-min.img"
SERIAL_LOG="${ROOT_DIR}/.zig-cache/kfs-integration.serial.log"
USER_LOG="${ROOT_DIR}/.zig-cache/kfs-integration.user.log"
TIMEOUT_SECS="${TIMEOUT_SECS:-90}"

DEBUGFS="${DEBUGFS:-debugfs}"
if ! command -v "${DEBUGFS}" >/dev/null 2>&1; then
    if [ -x /opt/homebrew/Cellar/e2fsprogs/*/sbin/debugfs ]; then
        DEBUGFS="$(ls /opt/homebrew/Cellar/e2fsprogs/*/sbin/debugfs | head -1)"
    else
        echo "debugfs not found; install e2fsprogs" >&2
        exit 2
    fi
fi

QEMU="${QEMU:-}"
if [ -z "${QEMU}" ]; then
    if command -v qemu-system-i386 >/dev/null 2>&1; then
        QEMU=qemu-system-i386
    else
        QEMU=qemu-system-x86_64
    fi
fi

# Force a non-test kernel build. `-Dtest=true` from `make test-kernel` leaves
# behind a kernel that runs the in-kernel suite at boot and never reaches
# userspace, so we'd never see /bin/init run.
echo ">> rebuilding non-test kernel"
( cd "${ROOT_DIR}" && zig build )

[ -f "${KERNEL}" ] || { echo "no kernel at ${KERNEL}" >&2; exit 2; }
[ -f "${BASE_ROOTFS}" ] || { echo "no base rootfs at ${BASE_ROOTFS}" >&2; exit 2; }

echo ">> cross-compiling integration runner"
zig cc -target x86-linux-musl -static -Os -o "${RUNNER_BIN}" "${RUNNER_SRC}"

echo ">> cloning rootfs and injecting /bin/init"
cp -c "${BASE_ROOTFS}" "${TEST_ROOTFS}" 2>/dev/null || cp "${BASE_ROOTFS}" "${TEST_ROOTFS}"
"${DEBUGFS}" -w -R "rm /bin/init" "${TEST_ROOTFS}" >/dev/null 2>&1 || true
"${DEBUGFS}" -w -f - "${TEST_ROOTFS}" >/dev/null 2>&1 <<EOF
write ${RUNNER_BIN} /bin/init
sif /bin/init mode 0100755
EOF

echo ">> building test boot disk"
DISK="${TEST_DISK}" \
    KERNEL="${KERNEL}" \
    ROOT_IMG="${TEST_ROOTFS}" \
    GRUB_CFG="${ROOT_DIR}/boot/grub/grub.cfg" \
    GRUB_THEME="${ROOT_DIR}/boot/grub/theme" \
    sh "${ROOT_DIR}/scripts/create_boot_disk.sh" "${TEST_DISK}" >/dev/null 2>&1

echo ">> booting under qemu (timeout=${TIMEOUT_SECS}s)"
rm -f "${SERIAL_LOG}" "${USER_LOG}"
set +e
( "${QEMU}" \
        -drive "file=${TEST_DISK},format=raw" \
        -m 1G \
        -display none \
        -serial "file:${SERIAL_LOG}" \
        -serial "file:${USER_LOG}" \
        -no-reboot \
        & echo $! >"${SERIAL_LOG}.pid" )

QPID="$(cat "${SERIAL_LOG}.pid")"
DEADLINE=$(( $(date +%s) + TIMEOUT_SECS ))
RESULT="timeout"
while [ "$(date +%s)" -lt "${DEADLINE}" ]; do
    for f in "${USER_LOG}" "${SERIAL_LOG}"; do
        [ -f "${f}" ] || continue
        if grep -q "\[ITEST\] === ALL PASS ===" "${f}" 2>/dev/null; then
            RESULT="pass"; break 2
        fi
        if grep -q "\[ITEST\] === FAIL ===" "${f}" 2>/dev/null; then
            RESULT="fail"; break 2
        fi
    done
    sleep 1
done
kill -9 "${QPID}" 2>/dev/null || true
wait "${QPID}" 2>/dev/null || true
rm -f "${SERIAL_LOG}.pid"
set -e

echo "---- kernel serial (COM1) ----"
tail -25 "${SERIAL_LOG}" 2>/dev/null || echo "(empty)"
echo "---- userspace serial (COM2) ----"
tail -40 "${USER_LOG}" 2>/dev/null || echo "(empty)"
echo "---- end -----------"

case "${RESULT}" in
    pass)    echo "RESULT: ALL PASS"; exit 0 ;;
    fail)    echo "RESULT: FAILURES";  exit 1 ;;
    timeout) echo "RESULT: TIMEOUT (no marker after ${TIMEOUT_SECS}s)"; exit 2 ;;
esac
