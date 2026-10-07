#!/bin/sh
# Builds serialtest.img (Pi 4) and serialtest_qemu_pi3.img (QEMU raspi3b) here,
# plus QEMU-only test variants in $TMPDIR: _trace (prints every pin-8 bit level),
# _trace_st (system timer forced), _stuck (fake stuck UART), _ramfail.
set -e
cd "$(dirname "$0")"
T=${TMPDIR:-/tmp}
build() {  # name peri_base extra-flags...
  n=$1; b=$2; shift 2
  clang --target=aarch64-none-elf -DPERI_BASE=$b "$@" -c serialtest.S -o $T/$n.o
  ld.lld -Ttext=0x80000 -e _start -o $T/$n.elf $T/$n.o
  llvm-objcopy -O binary $T/$n.elf $T/$n.img
}
build serialtest 0xFE000000
build serialtest_qemu_pi3 0x3F000000
build serialtest_qemu_trace 0x3F000000 -DTRACE
build serialtest_qemu_trace_st 0x3F000000 -DTRACE -DFORCE_ST
build serialtest_qemu_stuck 0x3F000000 -DTRACE -DSTUCK_TEST
build serialtest_qemu_ramfail 0x3F000000 -DTRACE -DRAMFAIL_TEST
cp $T/serialtest.img $T/serialtest_qemu_pi3.img .
ls -l serialtest.img serialtest_qemu_pi3.img
