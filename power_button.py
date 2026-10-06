#!/usr/bin/env python3
"""Hold-to-shutdown for a button on GPIO3 (physical pin 5).

Powering ON is handled by the Pi's own hardware: shorting GPIO3 to GND
while the Pi is halted wakes it, with no software involved. This script
covers the other direction - while the Pi is running it watches the same
pin and shuts down only after the button is held, so a knock does nothing.

Wiring: button one leg -> pin 5 (GPIO3), other leg -> any GND pin.
No resistor needed; GPIO3 has a fixed pull-up on the Pi board.
"""
import logging
import subprocess
import sys
import time

from gpiozero import Button

BUTTON_PIN = 3        # BCM 3 = physical pin 5
HOLD_SECONDS = 2.0    # how long the button must be held
SHUTDOWN_CMDS = [
    ["/sbin/shutdown", "-h", "now"],
    ["/usr/sbin/shutdown", "-h", "now"],
    ["systemctl", "poweroff"],
]

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("power_button")


def shutdown():
    log.info("Power button held %.1fs - shutting down", HOLD_SECONDS)
    for cmd in SHUTDOWN_CMDS:
        try:
            subprocess.run(cmd, check=True)
            return
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            log.warning("%s failed: %s", cmd[0], exc)
    log.error("No working shutdown command found")


def main():
    # hold_time makes gpiozero fire only after a sustained press
    button = Button(BUTTON_PIN, hold_time=HOLD_SECONDS)
    button.when_held = shutdown
    log.info("Watching GPIO%d, hold %.1fs to shut down", BUTTON_PIN, HOLD_SECONDS)
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log.info("Stopping")
        sys.exit(0)
