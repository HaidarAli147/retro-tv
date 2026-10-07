# Pi test v3.1: code running? timer? which pin? UART? RAM?

`serialtest.img` (2276 bytes, SHA256 starts `AF509BAEB635`) is a bare-metal program
(no Linux) that the Pi's firmware runs instead of the kernel (`kernel=serialtest.img`
in `config.txt`).

## What it does
- **LED, from the moment it starts:** the first instructions switch the green ACT LED
  **on**, then give **3 quick dark blinks** timed by plain countdown loops (no timer
  needed, so this proves our code started even if every timer is dead), then **solid
  on for 2 s**, then **5 rounds of one short flash per second**, then the **RAM test**
  (LED toggles at every 64 MB mark: slow, irregular on/off), then **one short flash
  per second** forever if RAM is OK, or **one flash + 4 quick flashes** each second if
  RAM failed. (Firmware error codes are groups of flashes with a ~2 s pause; they
  never start with "3 quick dark blinks then 2 s on".)
- **Text, 9600 8N1:** a header (load address, device-tree address, exception level,
  timer used), then every second `[BB pin N] PI ALIVE k` bit-banged on header
  **pins 8, 7, 10, 11, 12** one at a time (GPIO driven directly, no UART), so the text
  names the pin the wire is on. Then `[UART pin 8] PI ALIVE k` from the PL011 UART
  (what Linux uses). If the UART never drains, lines say `UART STUCK`; it is then
  skipped, so nothing can hang.
- **Timer:** uses the ARM generic timer. If its counter does not move, it switches to
  the BCM system timer; the header says `ARM TIMER FROZEN` and **every** line ends in
  `ARM-TIMER-FROZEN` (a frozen ARM timer would also explain Linux hanging).
- **RAM test:** `0x00400000` up to `0x20000000` (or the device tree, if lower), two passes
  (address, inverted address), uncached. Prints `w` per 64 MB written and `.` per 64 MB
  checked. Can take a few minutes. A `FAIL at` line gives address, value read and value
  expected. `RAM OK` does not fully clear the RAM (Linux uses it cached and much faster).
- Position independent: works whether the firmware loads it at 0x80000 or 0x200000.
  (v2 tested RAM from 0x200000 and overwrote itself there; confirmed in QEMU.)

Checked in QEMU raspi3b (Pi 3 build, same GPIO/UART at 0x3F000000): loaded at 0x80000
(EL2) and 0x200000 (EL3), the TRACE build's pin-8 waveform decodes to the expected text
with 0 framing errors; forced system timer, fake stuck UART and fake RAM failure all
behave as described. Every literal load is naturally aligned (needed with the MMU off).
Two adversarial review passes (platform facts, assembly, electrical, procedure).

## Arduino side
Upload `../pi_serial_bridge/pi_serial_bridge.ino` (v3) to the Uno. It reads the Pi on
**Uno pin 10** (SoftwareSerial 9600), prints to the Serial Monitor at **115200**, and
after every 10 s of silence prints the byte count and pin 10's level, measured with the
Uno's pull-up on and off: `HIGH` (something drives it high, or no wire), `weak LOW`
(undriven Pi pin, or no wire), `LOW` (wire on a GND pin, or the Pi pin pulled/driven
low), `unstable` (loose wire?). The level never proves our code runs (the firmware
itself idles pin 8 high); only the LED and the text do.

Wiring (Pi off): Pi **pin 8** -> Uno **pin 10** (the socket marked ~10, not ~11),
Pi **pin 6 (GND)** -> Uno **GND**. Nothing on Uno pins 0/1, no RESET wire.
Nothing else on the Pi header. In this test **pins 7, 8, 10, 11, 12 are live outputs**:
never connect GND to them.
Pi header, outer row from the corner: pin 2 = 5V, 4 = 5V, 6 = GND, 8 = TXD, 10, 12.

## Steps
0. Upload the v3 sketch. The Serial Monitor (115200) must show `BRIDGE v3 READY`.
1. PowerShell, USB stick in the PC as D: (fresh copies of `prep_usb_serial.ps1` and
   `serialtest.img` in Downloads):
   ```
   cd $env:USERPROFILE\Downloads
   powershell -ExecutionPolicy Bypass -File .\prep_usb_serial.ps1 -Mode serialtest -Root D:\
   ```
   The output must show `version 2026-10-07b` and `(2276 bytes, SHA256 AF509BAEB635)`.
2. Eject D:, USB stick into the Pi (no SD card), wire as above.
3. Serial Monitor open, then power the Pi and **film the LED** from power-on until the
   RAM test is running. The first 10-20 s are the bootloader. Leave it running about
   10 minutes. Then send the Serial Monitor text, making sure it includes the first
   lines (`=== RETRO-TV PI TEST v3.1 ...`): scroll to the top, or photograph the start
   and the end.

## Results
| Serial Monitor | LED after the rainbow | Meaning / next step |
|---|---|---|
| header + `[BB pin 8]` + `[UART pin 8]` lines | 3 blinks, 2 s on, flashes, RAM toggling | Code, timer, pin 8, wire and UART all work. Note the RAM result, then run `-Mode linux` with the 9600 script |
| `[BB pin 8]` lines, UART lines garbled/missing or `UART STUCK` | same | Pin and wire fine; PL011 clock/setup problem (Linux console needs a fix) |
| `ARM TIMER FROZEN` / `ARM-TIMER-FROZEN` | same | The ARM generic timer does not count: a board/firmware fault that also stops Linux |
| `[BB pin 7/10/11/12]` lines | same | The wire is on that pin: move it to pin 8 |
| nothing, bridge `HIGH`, `weak LOW` or `LOW` | 3 blinks, 2 s on, then flashes | Our code runs but nothing readable reaches Uno pin 10. Power off, photograph the header, move the Pi end of the wire to pin 10 and run again. `[BB pin 10]` text = wire, Uno and GND are fine; then put it back on pin 8: text now = it was on the wrong pin before; nothing again = pin 8 (GPIO14) is dead or held low (only that pin: Linux's console can use another UART, so not by itself a reason to replace the Pi). Nothing on pin 10 either = wire, Uno socket or GND problem |
| nothing | 3 blinks, then on for good | Our code started but stopped during setup: send the video |
| nothing | on for good, no blinks | Our code never ran (the firmware left the LED on): check step 1's output, `config.txt`, and that no SD card is in |
| nothing | groups of quick flashes with a ~2 s pause | Firmware error code: our code did NOT start. Count long and short flashes from the video (7 short = `serialtest.img` not found: redo step 1 and paste its output; others: send the counts) |
| nothing | off, nothing after the rainbow | Our code never started: check step 1's output and `config.txt`; if both are right, the board can't run code |
| `w`/dots stop, LED frozen for over 5 min | stuck | Froze while accessing RAM around that address: RAM/SoC fault |
| `RAM FAIL ...` | flash + 4 quick flashes | Bad RAM: send the `FAIL at` lines (address, read, expected) |

## Undo
```
cd $env:USERPROFILE\Downloads
powershell -ExecutionPolicy Bypass -File .\prep_usb_serial.ps1 -Mode undo -Root D:\
```
