#!/bin/sh
# Builds serialtest.img (Pi 4) and serialtest_qemu_pi3.img (QEMU raspi3b check).
set -e
cd "$(dirname "$0")"
T=${TMPDIR:-/tmp}
for v in "serialtest 0xFE000000" "serialtest_qemu_pi3 0x3F000000"; do
  set -- $v
  clang --target=aarch64-none-elf -DPERI_BASE=$2 -c serialtest.S -o $T/$1.o
  ld.lld -Ttext=0x80000 -e _start -o $T/$1.elf $T/$1.o
  llvm-objcopy -O binary $T/$1.elf $1.img
done
ls -l *.img
