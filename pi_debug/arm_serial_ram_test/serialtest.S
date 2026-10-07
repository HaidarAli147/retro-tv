// Bare-metal Raspberry Pi 4 test v3: is our code running, which header pin
// carries text, does the PL011 UART work, and is the first 512 MB of RAM OK.
//
// 1. ACT LED blinks once a second from the moment the code starts.
// 2. Every second it sends "[BB pin N] PI ALIVE k" bit-banged (GPIO driven
//    directly, timed by the ARM generic timer, no UART involved) on pins
//    7, 8, 10, 11 and 12, one pin at a time, so the text says which pin the
//    wire is on. Then "[UART pin 8] PI ALIVE k" from the PL011 on pin 8.
//    UART waits time out, so a dead UART clock can't hang the test.
// 3. After 5 of those, RAM test 0x00400000-0x20000000 (LED solid on),
//    reported bit-banged on all five pins, then the beacons repeat forever
//    with the result. LED: 1 blink/s = RAM OK, 1 + 4 quick blinks/s = FAIL.
// Position independent: runs wherever the firmware loads it (0x80000 or
// 0x200000) and prints the load address. 9600 8N1 by default (-DBAUD=...).
// Build: build.sh (PERI_BASE 0xFE000000 = Pi 4, 0x3F000000 = Pi 3 for QEMU;
// -DTRACE prints every pin-8 bit level on the UART for the QEMU check).

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
#define GPFSEL0   0x00
#define GPFSEL1   0x04
#define GPFSEL4   0x10
#define GPSET0    0x1c
#define GPSET1    0x20
#define GPCLR0    0x28
#define GPCLR1    0x2c
#define GPLEV0    0x34
#define UART_DR   0x00
#define UART_FR   0x18
#define M7   (1 << 4)               // header pin 7  = GPIO4
#define M8   (1 << 14)              // header pin 8  = GPIO14 (TXD)
#define M10  (1 << 15)              // header pin 10 = GPIO15 (RXD)
#define M11  (1 << 17)              // header pin 11 = GPIO17
#define M12  (1 << 18)              // header pin 12 = GPIO18
#define MALL (M7 | M8 | M10 | M11 | M12)
#define FSEL1_MASK ((7 << 12) | (7 << 15) | (7 << 21) | (7 << 24))
#define FSEL1_OUT  ((1 << 12) | (1 << 15) | (1 << 21) | (1 << 24))
#define RAM_START 0x00400000
#define RAM_END   0x20000000
#define BEACONS   5

// Global registers:
//   x20 GPIO base, x21 UART base, w22 ACT LED bit (GPIO42 in bank 1),
//   x23 timer ticks per second, x27 ticks per serial bit,
//   x28 output target for putc (0 = PL011, else GPIO mask to bit-bang),
//   x24 RAM state (0 untested, 1 OK, 2 FAIL), x25 beacon counter,
//   x18 UART state (0 ok, 1 stuck). Helpers use x0-x17 as scratch.

        .section .text
        .globl _start
_start:
        mrs     x0, mpidr_el1
        and     x0, x0, #3
        cbnz    x0, hang                // only core 0 runs the test

        adr     x0, _start
        mov     sp, x0                  // stack grows down below the image

        ldr     x20, =GPIO
        ldr     x21, =UART0
        mov     w22, #(1 << 10)
        mrs     x23, cntfrq_el0
        cbnz    x23, 1f
        ldr     x23, =54000000          // Pi 4 timer rate if firmware left it 0
1:      ldr     x0, =BAUD
        udiv    x27, x23, x0
        mov     x24, #0
        mov     x25, #0
        mov     x18, #0

        // ACT LED (GPIO42) output, off
        str     w22, [x20, #GPCLR1]
        ldr     w2, [x20, #GPFSEL4]
        bic     w2, w2, #(7 << 6)
        orr     w2, w2, #(1 << 6)
        str     w2, [x20, #GPFSEL4]

        // serial pins: latch high (idle) first, then make them outputs
        ldr     w2, =MALL
        str     w2, [x20, #GPSET0]
        ldr     w2, [x20, #GPFSEL0]
        bic     w2, w2, #(7 << 12)
        orr     w2, w2, #(1 << 12)      // GPIO4 output
        str     w2, [x20, #GPFSEL0]
        ldr     w2, [x20, #GPFSEL1]
        ldr     w3, =FSEL1_MASK
        bic     w2, w2, w3
        ldr     w3, =FSEL1_OUT
        orr     w2, w2, w3              // GPIO14/15/17/18 outputs
        str     w2, [x20, #GPFSEL1]

        // PL011: BAUD 8N1, FIFO on (pin 8 stays a plain output until used)
        str     wzr, [x21, #0x30]       // CR off
        mov     w2, #0x7ff
        str     w2, [x21, #0x44]        // clear interrupts
        ldr     w2, =(DIV64 >> 6)
        str     w2, [x21, #0x24]        // IBRD
        ldr     w2, =(DIV64 & 63)
        str     w2, [x21, #0x28]        // FBRD
        mov     w2, #0x70
        str     w2, [x21, #0x2c]        // LCRH: 8N1, FIFO (latches IBRD/FBRD)
        mov     w2, #0x301
        str     w2, [x21, #0x30]        // CR: UART, TX, RX enable

        lsr     x0, x23, #2             // 0.25 s of idle-high line
        bl      delay

        ldr     x28, =MALL              // header on all bit-banged pins
        adr     x0, s_hello
        bl      puts
        adr     x0, _start
        bl      puthex
        adr     x0, s_crlf
        bl      puts

        mov     x26, #BEACONS
2:      bl      beacon
        subs    x26, x26, #1
        b.ne    2b
        bl      ramtest
3:      bl      beacon
        b       3b

// One beacon round, takes 1 s: LED on, one line per pin, one UART line,
// LED off (+ 4 quick blinks if RAM FAIL), wait out the second.
beacon: stp     x29, x30, [sp, #-16]!
        stp     x19, x26, [sp, #-16]!
        mrs     x19, cntpct_el0
        add     x25, x25, #1
        str     w22, [x20, #GPSET1]     // LED on
        adr     x26, pintab
1:      ldr     w28, [x26], #4          // pin mask, 0 ends the table
        ldrsw   x1, [x26], #4           // label offset from pintab
        cbz     w28, 2f
        adr     x0, pintab
        add     x0, x0, x1
        bl      puts
        bl      tail
        b       1b
2:      ldr     w9, [x20, #GPFSEL1]     // pin 8 -> ALT0 (PL011 TXD)
        bic     w9, w9, #(7 << 12)
        orr     w9, w9, #(4 << 12)
        str     w9, [x20, #GPFSEL1]
        mov     x28, #0
        adr     x0, s_uart
        bl      puts
        bl      tail
        bl      udrain
        ldr     w9, [x20, #GPFSEL1]     // pin 8 -> output again (latched high)
        bic     w9, w9, #(7 << 12)
        orr     w9, w9, #(1 << 12)
        str     w9, [x20, #GPFSEL1]
        str     w22, [x20, #GPCLR1]     // LED off
        cmp     x24, #2
        b.ne    4f
        mov     x26, #4                 // RAM FAIL: 4 quick blinks
3:      lsr     x0, x23, #4
        bl      delay
        str     w22, [x20, #GPSET1]
        lsr     x0, x23, #4
        bl      delay
        str     w22, [x20, #GPCLR1]
        subs    x26, x26, #1
        b.ne    3b
4:      add     x0, x19, x23            // until 1 s after the round started
        bl      until
        ldp     x19, x26, [sp], #16
        ldp     x29, x30, [sp], #16
        ret

// Rest of a beacon line: counter, RAM state, UART state, CRLF.
tail:   stp     x29, x30, [sp, #-16]!
        mov     x0, x25
        bl      putdec
        cbz     x24, 1f
        adr     x0, s_ramok
        cmp     x24, #1
        b.eq    2f
        adr     x0, s_ramfail
2:      bl      puts
1:      adr     x0, s_uok
        cbz     x18, 3f
        adr     x0, s_ustuck
3:      bl      puts
        adr     x0, s_crlf
        bl      puts
        ldp     x29, x30, [sp], #16
        ret

// RAM test, reported bit-banged on all pins. LED solid on while it runs.
ramtest:
        stp     x29, x30, [sp, #-16]!
        stp     x19, x26, [sp, #-16]!
        str     w22, [x20, #GPSET1]
        ldr     x28, =MALL
        adr     x0, s_ram
        bl      puts
        mov     x24, #1
        mov     x19, #0                 // pass 0: address, pass 1: inverse
pass:   adr     x0, s_pass
        bl      puts
        ldr     x26, =RAM_START
        ldr     x16, =RAM_END
wr:     mov     x17, x26
        cbz     x19, 1f
        mvn     x17, x26
1:      str     x17, [x26], #8
        cmp     x26, x16
        b.lo    wr
        ldr     x26, =RAM_START
rd:     ldr     x7, [x26]
        mov     x17, x26
        cbz     x19, 2f
        mvn     x17, x26
2:      cmp     x7, x17
        b.ne    bad
        add     x26, x26, #8
        tst     x26, #0x3ffffff         // a dot every 64 MB
        b.ne    3f
        mov     w0, #'.'
        bl      putc
3:      cmp     x26, x16
        b.lo    rd
        adr     x0, s_ok
        bl      puts
        b       next
bad:    mov     x24, #2
        stp     x7, x17, [sp, #-16]!    // read, expected
        adr     x0, s_bad
        bl      puts
        mov     x0, x26
        bl      puthex
        adr     x0, s_read
        bl      puts
        ldr     x0, [sp]
        bl      puthex
        adr     x0, s_want
        bl      puts
        ldr     x0, [sp, #8]
        bl      puthex
        adr     x0, s_crlf
        bl      puts
        add     sp, sp, #16
next:   add     x19, x19, #1
        cmp     x19, #2
        b.lo    pass
        adr     x0, s_resok
        cmp     x24, #2
        b.ne    4f
        adr     x0, s_resbad
4:      bl      puts
        str     w22, [x20, #GPCLR1]
        ldp     x19, x26, [sp], #16
        ldp     x29, x30, [sp], #16
        ret

// putc: w0 = char, to the PL011 (x28 = 0) or bit-banged on GPIO mask x28.
// Uses only w0 and x8-x15.
putc:   cbnz    x28, bbputc
        mrs     x10, cntpct_el0
        lsr     x11, x23, #6            // ~15 ms timeout per char
        add     x10, x10, x11
1:      ldr     w9, [x21, #UART_FR]
        tbz     w9, #5, 2f              // TX FIFO not full
        mrs     x11, cntpct_el0
        cmp     x11, x10
        b.lo    1b
        mov     x18, #1                 // UART stuck: drop the char
        ret
2:      str     w0, [x21, #UART_DR]
        ret

// 8N1 frame: start bit, 8 data bits LSB first, stop bit, 1 extra idle bit.
// Edges are placed at absolute times t0 + i * x27, so there is no drift.
bbputc:
#ifdef TRACE
        str     x30, [sp, #-16]!
#endif
        mov     w11, #0x300
        orr     w11, w11, w0            // bit 8 = stop, bit 9 = extra idle
        mrs     x12, cntpct_el0
        str     w28, [x20, #GPCLR0]     // start bit
#ifdef TRACE
        bl      trace
#endif
        mov     x13, #1
1:      madd    x14, x13, x27, x12
2:      mrs     x15, cntpct_el0
        cmp     x15, x14
        b.lo    2b
        cmp     x13, #11
        b.hs    5f
        tbz     w11, #0, 3f
        str     w28, [x20, #GPSET0]
        b       4f
3:      str     w28, [x20, #GPCLR0]
4:
#ifdef TRACE
        bl      trace
#endif
        lsr     w11, w11, #1
        add     x13, x13, #1
        b       1b
5:
#ifdef TRACE
        ldr     x30, [sp], #16
#endif
        ret

#ifdef TRACE
// QEMU check only: print pin 8's level ('_' low, '^' high) on the UART.
// Must keep x11-x15, w28. Clobbers x8, x9 (bbputc saves its own x30 in TRACE builds).
trace:  tst     w28, #M8
        b.eq    2f
        ldr     w8, [x20, #GPLEV0]
        tst     w8, #M8
        mov     w8, #'_'
        b.eq    1f
        mov     w8, #'^'
1:      ldr     w9, [x21, #UART_FR]
        tbnz    w9, #5, 1b
        str     w8, [x21, #UART_DR]
2:      ret
#endif

// Wait (with timeout) until the PL011 has shifted out its last bit.
udrain: mrs     x10, cntpct_el0
        lsr     x11, x23, #2            // 250 ms
        add     x10, x10, x11
1:      ldr     w9, [x21, #UART_FR]
        tbz     w9, #3, 2f              // BUSY clear
        mrs     x11, cntpct_el0
        cmp     x11, x10
        b.lo    1b
        mov     x18, #1
2:      ret

// x0 = NUL-terminated string
puts:   stp     x29, x30, [sp, #-16]!
        str     x19, [sp, #-16]!
        mov     x19, x0
1:      ldrb    w0, [x19], #1
        cbz     w0, 2f
        bl      putc
        b       1b
2:      ldr     x19, [sp], #16
        ldp     x29, x30, [sp], #16
        ret

// x0 = value, printed in decimal
putdec: stp     x29, x30, [sp, #-48]!
        add     x10, sp, #47
        strb    wzr, [x10]
        mov     x9, x0
        mov     x11, #10
1:      udiv    x12, x9, x11
        msub    x13, x12, x11, x9
        add     w13, w13, #'0'
        sub     x10, x10, #1
        strb    w13, [x10]
        mov     x9, x12
        cbnz    x9, 1b
        mov     x0, x10
        bl      puts
        ldp     x29, x30, [sp], #48
        ret

// x0 = value, printed as 0x + 16 hex digits (uses x16, x17)
puthex: stp     x29, x30, [sp, #-16]!
        mov     x16, x0
        mov     w0, #'0'
        bl      putc
        mov     w0, #'x'
        bl      putc
        mov     x17, #60
1:      lsr     x0, x16, x17
        and     x0, x0, #0xf
        cmp     x0, #10
        b.lo    2f
        add     x0, x0, #('a' - '0' - 10)
2:      add     x0, x0, #'0'
        bl      putc
        subs    x17, x17, #4
        b.ge    1b
        ldp     x29, x30, [sp], #16
        ret

// x0 = timer ticks to wait
delay:  mrs     x8, cntpct_el0
        add     x0, x0, x8
// x0 = absolute timer value to wait for
until:  mrs     x8, cntpct_el0
        cmp     x8, x0
        b.lo    until
        ret

hang:   wfe
        b       hang

        .balign 4
pintab: .word   M8,  s_bb8  - pintab    // pin 8 first: the expected wire
        .word   M7,  s_bb7  - pintab
        .word   M10, s_bb10 - pintab
        .word   M11, s_bb11 - pintab
        .word   M12, s_bb12 - pintab
        .word   0, 0

s_hello: .asciz "\r\n\r\n=== RETRO-TV PI TEST v3 (9600 8N1) ===\r\nCPU core 0 running, loaded at "
s_bb7:   .asciz "\r\n[BB pin 7] PI ALIVE "
s_bb8:   .asciz "\r\n[BB pin 8] PI ALIVE "
s_bb10:  .asciz "\r\n[BB pin 10] PI ALIVE "
s_bb11:  .asciz "\r\n[BB pin 11] PI ALIVE "
s_bb12:  .asciz "\r\n[BB pin 12] PI ALIVE "
s_uart:  .asciz "\r\n[UART pin 8] PI ALIVE "
s_ramok: .asciz " RAM OK"
s_ramfail: .asciz " RAM FAIL"
s_uok:   .asciz " uart ok"
s_ustuck: .asciz " UART STUCK"
s_ram:   .asciz "\r\nRAM test 0x00400000-0x20000000 (first 512 MB)\r\n"
s_pass:  .asciz "pass "
s_ok:    .asciz " OK\r\n"
s_bad:   .asciz " FAIL at "
s_read:  .asciz " read "
s_want:  .asciz " expected "
s_crlf:  .asciz "\r\n"
s_resok: .asciz "RESULT: RAM OK\r\n"
s_resbad: .asciz "RESULT: RAM FAIL\r\n"
        .balign 8
