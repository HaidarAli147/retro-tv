# Serial + RAM test (run after the ARM LED test)

`serialtest.img` is a bare-metal program (no Linux) that:
1. sends text out of the Pi's serial pin (GPIO14 / pin 8, 9600 baud),
2. tests the first 512 MB of RAM twice (dots show progress),
3. then blinks the green LED forever: **3 flashes + pause = RAM OK**, **10 fast flashes + pause = RAM FAIL**.

Built at 9600 baud by default (`-DBAUD=115200` for 115200); the Uno's SoftwareSerial
reads 9600 reliably. Checked in QEMU (Pi 3 model, same UART/GPIO at a different address) with
`serialtest_qemu_pi3.img`; both the OK and the FAIL report print correctly.

## Quick way: the prep script
From the `pi_debug` folder, with the USB stick (or SD card) plugged into the PC:
```
powershell -ExecutionPolicy Bypass -File prep_usb_serial.ps1 -Mode serialtest
```
It finds the boot drive, backs up `config.txt`/`cmdline.txt` to Downloads, copies
`serialtest.img` and sets `config.txt`. Then continue at step 3 below.
After this test, `-Mode linux` sets the drive to boot Linux with its messages on the
serial pin (corrected `earlycon=pl011,mmio32,0xfe201000`); `-Mode undo` restores everything.

## Steps (by hand)
1. Put the SD card in the PC, open `bootfs`, copy `serialtest.img` next to `kernel8.img`.
2. In `config.txt`, at the bottom, change `kernel=blink.img` to `kernel=serialtest.img`.
   The bottom should read:
   ```
   [all]
   kernel=serialtest.img
   arm_64bit=1
   ```
3. Upload `../pi_serial_bridge/pi_serial_bridge.ino` to the Uno (it reads the Pi on pin 10 and
   prints to the Serial Monitor). Wiring (Pi powered off): Pi **pin 8** -> Uno **pin 10**,
   Pi **pin 6 (GND)** -> Uno **GND**. Nothing on Uno pins 0/1, no RESET wire.
   On the Pi's outer row, counting from the corner pin: 5V, 5V, GND (pin 6), **TXD (pin 8)**.
4. On the PC start the serial reader first: Arduino IDE Serial Monitor at **115200** (the bridge's
   USB side; it shows `BRIDGE READY`),
   or `read_pi_serial.ps1` (log goes to Downloads\pi_boot_serial_log.txt).
5. Power the Pi. Wait until the LED starts its flash pattern (up to a few minutes).

Expected text:
```
=== RETRO-TV ARM TEST ===
CPU core 0 running, serial OK
RAM test 0x00200000-0x20000000 (first 512 MB)
pass ........ OK
pass ........ OK
RESULT: RAM OK
alive
```

## Results
| What you get | Meaning |
|---|---|
| Text + `RESULT: RAM OK` | Serial wiring works and the first 512 MB is fine. Next: boot Linux with the corrected `earlycon` and read where the kernel stops |
| Text + `FAIL at ...` / `RAM FAIL` | Bad memory on the board (RAM is soldered on) -> replace the Pi. Send the FAIL line |
| No text, LED does 3 or 10 flashes | Serial path broken (wire one pin off, or GPIO14 damaged). LED still gives the RAM result |
| LED stays solid on for over 5 minutes | Froze during the RAM test -> memory fault |

## Undo
Remove the 3 lines at the bottom of `config.txt`.
