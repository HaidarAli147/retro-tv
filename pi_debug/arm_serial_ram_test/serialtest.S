// Bare-metal Raspberry Pi 4 test: serial output on GPIO14 + RAM test.
// Prints to the PL011 UART (pin 8, 9600 8N1 by default; build with -DBAUD=115200 for 115200), tests RAM 0x00200000-0x20000000
// (the first 512 MB, which Linux still failed in with total_mem=512), then
// blinks the ACT LED: 3 flashes + pause = RAM OK, 10 fast flashes + pause = RAM FAIL.
// Build: see build.sh (PERI_BASE 0xFE000000 = Pi 4, 0x3F000000 = Pi 3 for QEMU).

#ifndef PERI_BASE
#define PERI_BASE 0xFE000000
#endif
#ifndef BAUD
#define BAUD 9600
#endif
// PL011 divisor from the 48 MHz UART clock: 48e6 / (16 * BAUD) = IBRD + FBRD/64
#define DIV64 ((48000000 * 4 + BAUD / 2) / BAUD)
#define GPIO      (PERI_BASE + 0x200000)
#define UART0     (PERI_BASE + 0x201000)
#define RAM_START 0x00200000
#define RAM_END   0x20000000

        .macro PUTC reg                 // write one char, waits while TX FIFO full
putc_wait\@:
        ldr     w9, [x21, #0x18]
        tbnz    w9, #5, putc_wait\@
        str     \reg, [x21]
        .endm

        .section .text
        .globl _start
_start:
        mrs     x0, mpidr_el1
        and     x0, x0, #3
        cbnz    x0, hang

        ldr     x20, =GPIO
        ldr     x21, =UART0
        mov     w22, #(1 << 10)         // GPIO42 bit in SET1/CLR1
        mrs     x23, cntfrq_el0
        cbnz    x23, 1f
        ldr     x23, =54000000
1:
        // ACT LED (GPIO42) output, on during the test
        ldr     w2, [x20, #0x10]
        bic     w2, w2, #(7 << 6)
        orr     w2, w2, #(1 << 6)
        str     w2, [x20, #0x10]
        str     w22, [x20, #0x20]

        // GPIO14/15 -> ALT0 (PL011 TXD0/RXD0)
        ldr     w2, [x20, #0x04]
        bic     w2, w2, #(0x3f << 12)
        ldr     w3, =(0x24 << 12)
        orr     w2, w2, w3
        str     w2, [x20, #0x04]

        // PL011 at BAUD (9600 by default, readable by an Uno's SoftwareSerial)
        str     wzr, [x21, #0x30]       // CR off
        mov     w2, #0x7ff
        str     w2, [x21, #0x44]        // clear interrupts
        ldr     w2, =(DIV64 >> 6)
        str     w2, [x21, #0x24]        // IBRD
        ldr     w2, =(DIV64 & 63)
        str     w2, [x21, #0x28]        // FBRD
        mov     w2, #0x70
        str     w2, [x21, #0x2c]        // 8N1, FIFO on
        mov     w2, #0x301
        str     w2, [x21, #0x30]        // UART, TX, RX enable

        adr     x0, s_hello
        bl      puts

        // RAM test: pass 1 writes each address into itself, pass 2 its inverse
        mov     x24, #0                 // 0 = OK, 1 = FAIL
        mov     x25, #0                 // pass: 0 or 1
pass:   adr     x0, s_pass
        bl      puts
        ldr     x10, =RAM_START
        ldr     x11, =RAM_END
        mov     x12, x10
wr:     mov     x13, x12
        cbz     x25, 2f
        mvn     x13, x12
2:      str     x13, [x12], #8
        cmp     x12, x11
        b.lo    wr
        mov     x12, x10
rd:     ldr     x14, [x12]
        mov     x13, x12
        cbz     x25, 3f
        mvn     x13, x12
3:      cmp     x14, x13
        b.ne    bad
        add     x12, x12, #8
        tst     x12, #0x3ffffff         // a dot every 64 MB
        b.ne    4f
        mov     w0, #'.'
        PUTC    w0
4:      cmp     x12, x11
        b.lo    rd
        adr     x0, s_ok
        bl      puts
        b       next
bad:    mov     x24, #1
        adr     x0, s_bad
        bl      puts
        mov     x0, x12
        bl      puthex
        adr     x0, s_read
        bl      puts
        mov     x0, x14
        bl      puthex
        adr     x0, s_want
        bl      puts
        mov     x0, x13
        bl      puthex
        adr     x0, s_crlf
        bl      puts
next:   add     x25, x25, #1
        cmp     x25, #2
        b.lo    pass

        adr     x0, s_resok
        cbz     x24, 5f
        adr     x0, s_resbad
5:      bl      puts

        // forever: LED pattern + "alive" line
        mov     x26, #3
        cbz     x24, loop
        mov     x26, #10
loop:   mov     x6, x26
flash:  str     w22, [x20, #0x20]
        lsr     x0, x23, #4
        bl      delay
        str     w22, [x20, #0x2c]
        lsr     x0, x23, #3
        bl      delay
        subs    x6, x6, #1
        b.ne    flash
        adr     x0, s_alive
        bl      puts
        mov     x0, x23
        bl      delay
        b       loop

// x0 = NUL-terminated string
puts:   ldrb    w1, [x0], #1
        cbz     w1, 1f
        PUTC    w1
        b       puts
1:      ret

// x0 = value, printed as 0x + 16 hex digits
puthex: mov     x2, x0
        mov     w1, #'0'
        PUTC    w1
        mov     w1, #'x'
        PUTC    w1
        mov     x3, #60
1:      lsr     x1, x2, x3
        and     x1, x1, #0xf
        cmp     x1, #10
        b.lo    2f
        add     x1, x1, #('a' - '0' - 10)
2:      add     x1, x1, #'0'
        PUTC    w1
        subs    x3, x3, #4
        b.ge    1b
        ret

// x0 = timer ticks to wait
delay:  mrs     x8, cntpct_el0
        add     x9, x8, x0
1:      mrs     x8, cntpct_el0
        cmp     x8, x9
        b.lo    1b
        ret

hang:   wfe
        b       hang

s_hello: .asciz "\r\n\r\n=== RETRO-TV ARM TEST ===\r\nCPU core 0 running, serial OK\r\nRAM test 0x00200000-0x20000000 (first 512 MB)\r\n"
s_pass:  .asciz "pass "
s_ok:    .asciz " OK\r\n"
s_bad:   .asciz " FAIL at "
s_read:  .asciz " read "
s_want:  .asciz " expected "
s_crlf:  .asciz "\r\n"
s_resok: .asciz "RESULT: RAM OK\r\n"
s_resbad: .asciz "RESULT: RAM FAIL\r\n"
s_alive: .asciz "alive\r\n"
        .balign 8
