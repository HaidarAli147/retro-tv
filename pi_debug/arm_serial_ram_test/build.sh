#!/bin/sh
# Builds serialtest.img (Pi 4), serialtest_qemu_pi3.img (QEMU raspi3b check) and
# serialtest_qemu_trace.img (QEMU, prints every pin-8 bit level on the UART).
set -e
cd "$(dirname "$0")"
T=${TMPDIR:-/tmp}
for v in "serialtest 0xFE000000" "serialtest_qemu_pi3 0x3F000000" "serialtest_qemu_trace 0x3F000000 -DTRACE"; do
  set -- $v
  clang --target=aarch64-none-elf -DPERI_BASE=$2 $3 -c serialtest.S -o $T/$1.o
  ld.lld -Ttext=0x80000 -e _start -o $T/$1.elf $T/$1.o
  llvm-objcopy -O binary $T/$1.elf $T/$1.img
done
cp $T/serialtest.img $T/serialtest_qemu_pi3.img .
ls -l serialtest.img serialtest_qemu_pi3.img
