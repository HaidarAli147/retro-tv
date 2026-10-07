# Pi test v3: code running? which pin? UART? RAM?

`serialtest.img` is a bare-metal program (no Linux) that the Pi's firmware runs
instead of the kernel (`kernel=serialtest.img` in `config.txt`). Version 3:

1. **Green ACT LED blinks once a second** from the moment it starts. Any blinking
   means our code runs on the ARM cores.
2. Every second it sends `[BB pin N] PI ALIVE k` on header **pins 7, 8, 10, 11 and 12**,
   one pin at a time, by switching the pin directly (bit-banged 9600 8N1, timed by
   the ARM timer; no UART involved). The text names the pin the wire is on.
3. Then `[UART pin 8] PI ALIVE k` through the PL011 UART on pin 8 (what Linux uses).
   If the UART never drains, the lines say `UART STUCK` instead of hanging.
4. After 5 rounds: RAM test `0x00400000-0x20000000` (first 512 MB; LED solid on,
   dots every 64 MB, reported on all five pins), then the rounds repeat forever with
   `RAM OK` / `RAM FAIL`. LED: 1 blink/s = OK, 1 + 4 quick blinks/s = FAIL.

It is position independent and prints its load address: newer firmware may load
64-bit images at 0x200000 instead of 0x80000. (v2 tested RAM from 0x200000 and so
overwrote itself when loaded there; confirmed in QEMU.)

Checked in QEMU raspi3b (Pi 3 build: same GPIO/UART at 0x3F000000), loaded at both
0x80000 and 0x200000: the TRACE build prints every pin-8 level, and decoding it
gave 2775 characters with 0 framing errors and the expected text; the UART lines
and the RAM pass/fail reports print correctly.

## Arduino side
Upload `../pi_serial_bridge/pi_serial_bridge.ino` to the Uno. It reads the Pi on
**Uno pin 10** (SoftwareSerial 9600) and prints to the Serial Monitor at **115200**.
Every 10 s of silence it prints whether pin 10 is HIGH (idle / no wire) or LOW
(wire on a GND pin, or the Pi pin held low).

Wiring (Pi off): Pi **pin 8** -> Uno **pin 10**, Pi **pin 6 (GND)** -> Uno **GND**.
Nothing on Uno pins 0/1, no RESET wire. Leave Pi pins 7, 10, 11, 12 free.
Pi header, outer row from the corner: pin 2 = 5V, 4 = 5V, 6 = GND, 8 = TXD, 10 = RXD, 12.

## Steps
1. PC: `powershell -ExecutionPolicy Bypass -File prep_usb_serial.ps1 -Mode serialtest -Root D:\`
   (copies `serialtest.img` from next to the script onto the boot drive and sets `config.txt`).
2. Eject, USB stick into the Pi (no SD card), wire as above.
3. Open the Serial Monitor (115200), then power the Pi. Watch the LED for 10 s.

## Results
| Serial Monitor | LED | Meaning / next step |
|---|---|---|
| `[BB pin 8]` and `[UART pin 8]` lines | blinking | Code, pin 8, wire and UART all work. Note the `RAM` result, then run `-Mode linux` |
| `[BB pin 8]` lines, UART lines garbled, missing or `UART STUCK` | blinking | Pin and wire fine; the PL011 clock/setup is the problem (Linux console needs a fix) |
| `[BB pin 7/10/11/12]` lines | blinking | The wire is on that pin: move it to pin 8 |
| nothing, bridge says pin 10 **LOW** | any | Pi-side wire is on a GND pin (6/9/14...) or pin 8 is held low |
| nothing, bridge says pin 10 **HIGH** | blinking | Code runs but no signal reaches Uno pin 10: check both ends of the wire and GND |
| nothing | not blinking | Our code never runs (check `config.txt` has `kernel=serialtest.img`; if it does, the board can't run code) |
| `RAM FAIL ...` | 1 + 4 quick blinks | Bad RAM on the board -> replace the Pi |

## Undo
`prep_usb_serial.ps1 -Mode undo -Root D:\`
