// Bare-metal ARM test for Raspberry Pi 4: blinks the green ACT LED (GPIO42)
// 3 quick flashes, 1 s pause, forever. If this runs, the ARM cores can
// execute code loaded from the SD card; Linux is not involved.
// Build: clang --target=aarch64-none-elf -c blink.S && ld.lld -Ttext=0x80000 -o blink.elf blink.o
//        llvm-objcopy -O binary blink.elf blink.img

        .section .text
        .globl _start
_start:
        mrs     x0, mpidr_el1
        and     x0, x0, #3
        cbnz    x0, hang                // only core 0 runs the test

        ldr     x1, =0xFE200000         // GPIO base (low-peripheral mode)
        ldr     w2, [x1, #0x10]         // GPFSEL4
        bic     w2, w2, #(7 << 6)
        orr     w2, w2, #(1 << 6)       // GPIO42 = output
        str     w2, [x1, #0x10]
        mov     w3, #(1 << 10)          // GPIO42 bit in SET1/CLR1

        mrs     x4, cntfrq_el0          // timer ticks per second
        cbnz    x4, 1f
        ldr     x4, =54000000           // Pi 4 default if firmware left it 0
1:      lsr     x5, x4, #3              // 1/8 s

loop:   mov     x6, #3
flash:  str     w3, [x1, #0x20]         // GPSET1: LED on
        mov     x0, x5
        bl      delay
        str     w3, [x1, #0x2C]         // GPCLR1: LED off
        mov     x0, x5
        bl      delay
        subs    x6, x6, #1
        b.ne    flash
        mov     x0, x4                  // 1 s pause
        bl      delay
        b       loop

delay:  mrs     x8, cntpct_el0
        add     x9, x8, x0
2:      mrs     x8, cntpct_el0
        cmp     x8, x9
        b.lo    2b
        ret

hang:   wfe
        b       hang
