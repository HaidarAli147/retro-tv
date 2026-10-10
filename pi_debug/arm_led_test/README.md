# ARM LED test (optional; not a conclusive hardware diagnosis)

This bare-metal program replaces Linux for one diagnostic boot. The source
parks the secondary cores and attempts to blink the ACT LED from core 0:
**3 quick flashes, about 1 s pause, repeating**.

Status as of 2026-10-10: no completed result is recorded in PROJECT_LOG.md.
Ask whether it has already been attempted before recommending it again.
The source and existing binary have not been validated on this user's Pi
by this review. Do not use this test alone to decide to replace the board.

## Interpretation limits

| Observation | What it supports |
|---|---|
| Clear repeating three-flash pattern | At least one ARM core executes this small program with the memory and peripherals it uses. This does not validate all RAM, all cores, power under Linux load, or the complete board. Linux startup remains to be investigated. |
| No expected pattern (off, steady, or other flashes) | Inconclusive: loading/configuration, board-specific LED mapping, peripheral addressing, test implementation, power or hardware could explain it. It does not prove processor/RAM damage. |

The program assumes GPIO42 and the low-peripheral GPIO address 0xFE200000.
These assumptions and the active boot configuration must be checked before
interpreting a negative result. Ordinary ACT activity stopping during an OS
boot also does not, by itself, prove that the processor halted.

## Optional procedure (only after choosing this as the next test)

1. With Pi power disconnected, put the SD card in the PC. Back up its current
   `config.txt` to the PC and record any existing kernel/64-bit overrides.
2. Copy `blink.img` from this directory to the root of `bootfs`; keep the
   existing OS files. Resolve conflicting active overrides before proceeding.
3. Add at the bottom of `config.txt`:
   ```
   [all]
   kernel=blink.img
   arm_64bit=1
   ```
4. Save and safely eject. With power disconnected, insert the card and remove
   external GPIO/Arduino connections. Connect power; HDMI is optional.
5. Observe for about 30 seconds. Report the exact LED pattern (or a short
   video) before choosing another test. No further tests are implied here.

## Restore normal boot

Disconnect Pi power, return the card to the PC and restore the exact saved
`config.txt`. The unused `blink.img` can remain. Safely eject before booting.
