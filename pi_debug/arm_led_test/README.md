# ARM LED test (no USB drive needed)

Checks whether the Pi 4's ARM cores can run any code at all. `blink.img` is a
144-byte bare-metal program that the firmware loads from the SD card instead
of Linux. It only blinks the green ACT LED: **3 quick flashes, 1 s pause, repeat**.

## Steps (Windows PC)
1. Put the SD card in the PC and open the `bootfs` drive.
2. Copy `blink.img` into the root of `bootfs` (next to `kernel8.img`; don't delete anything).
3. Open `config.txt` in Notepad, go to the **very bottom** and add:
   ```
   [all]
   kernel=blink.img
   arm_64bit=1
   ```
4. Save, eject, put the card in the Pi. Connect only power (HDMI optional).
5. Watch the green LED for ~30 s after the rainbow (film it if unsure).

## Results
| Green LED | Meaning |
|---|---|
| 3 flashes, pause, repeating | ARM cores run code from the card. The board is alive; the failure is inside Linux startup |
| Off, steady on, or random flicker that stops | ARM cores never run code -> board fault (SoC/power). Replace the Pi |

## Undo
Delete the 3 added lines from `config.txt` (and `blink.img` if you like).
