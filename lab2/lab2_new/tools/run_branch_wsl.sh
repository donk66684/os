#!/usr/bin/env bash
set -u

ROOT=/mnt/d/Study/OS/Lab/Lab2
QEMU=/home/kali123/qemu-6.2.0/build-riscv-debug/riscv64-softmmu/qemu-system-riscv64
GDB=$ROOT/.gdb-wsl/extracted/usr/bin/gdb-multiarch
LDROOT=$ROOT/.gdb-wsl/extracted
BIOS=/mnt/d/Study/OS/.tools/qemu/riscv-qemu-5.1.0-2020.08.1-x86_64-w64-mingw32/bin/opensbi-riscv64-virt-fw_jump.bin
LOG=$ROOT/report/logs
export LD_LIBRARY_PATH=$LDROOT/usr/lib/x86_64-linux-gnu:$LDROOT/lib/x86_64-linux-gnu

rm -f "$LOG/qemu_source_gdb_host_new.txt" "$LOG/qemu_source_gdb_host_new.stderr.txt" \
      "$LOG/qemu_source_gdb_guest_new.txt" "$LOG/qemu_source_gdb_serial_new.txt"

trap 'if [ -n "${HOSTPID:-}" ]; then kill "$HOSTPID" 2>/dev/null || true; fi' EXIT
sleep 1

timeout 30s "$GDB" -q -batch \
    -ex "file $QEMU" \
    -x "$LOG/qemu_source_gdb_host_launch.gdb" \
    >"$LOG/qemu_source_gdb_host_new.txt" 2>"$LOG/qemu_source_gdb_host_new.stderr.txt" &
HOSTPID=$!
sleep 2

timeout 15s "$GDB" -q -batch \
    -ex "file $ROOT/lab2_new/bin/kernel" \
    -ex 'target remote :1234' \
    -ex 'break check_alloc_page' -ex continue \
    -ex 'info registers satp' -ex 'x/6i $pc' \
    -ex continue \
    >"$LOG/qemu_source_gdb_guest_new.txt" 2>&1 || true

wait "$HOSTPID" 2>/dev/null || true
