#!/usr/bin/env python3
"""Arduino serial commands -> virtual keyboard events via evdev.

Reads plain text lines from the Arduino (LEFT / RIGHT / UP / DOWN / ENTER)
and replays them as key press+release events on a virtual input device, so
Kodi or any other app sees ordinary keyboard input.

VOL_UP / VOL_DOWN are handled separately: they change the system (PipeWire)
volume directly via wpctl, rather than going through the keyboard. That way
the knob controls whatever speaker is actually plugged into the Pi, for any
app - not just one app's own internal volume.

POWER is also handled separately: it shuts the machine down directly rather
than going through the keyboard, so it works no matter what is on screen.

Needs root for /dev/uinput and for the shutdown. The systemd unit runs it
as root; to run it by hand use sudo.
"""
import glob
import logging
import os
import subprocess
import sys
import time

import serial
from evdev import UInput, ecodes as e

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("rpi_bridge")

BAUD_RATE = 9600
CANDIDATE_PORTS = ["/dev/ttyUSB0", "/dev/ttyACM0", "/dev/ttyUSB1", "/dev/ttyACM1"]
RECONNECT_DELAY = 2      # seconds between reconnect attempts
# Tried in order. Distros put shutdown in different places, and a missing
# binary must not take the bridge down with it.
SHUTDOWN_CMDS = [
    ["/sbin/shutdown", "-h", "now"],
    ["/usr/sbin/shutdown", "-h", "now"],
    ["systemctl", "poweroff"],
]

# uid of the desktop user whose PipeWire session owns the speaker. The
# bridge runs as root (systemd, for /dev/uinput), but PipeWire/wpctl only
# talk to one user's session, found via that user's XDG_RUNTIME_DIR - root
# does not pick this up automatically. 1000 is the default first-user uid
# on Raspberry Pi OS; change this if your desktop user has a different uid
# ("id -u <username>" on the Pi to check).
AUDIO_RUNTIME_UID = 1000
VOLUME_STEP = "5%"

KEY_MAP = {
    "LEFT":     e.KEY_LEFT,
    "RIGHT":    e.KEY_RIGHT,
    "UP":       e.KEY_UP,
    "DOWN":     e.KEY_DOWN,
    "ENTER":    e.KEY_ENTER,
    # joystick button held down - acts as back / escape
    "BACK":     e.KEY_ESC,
}


def _wpctl(*args):
    """Run a wpctl command against the desktop user's PipeWire session."""
    env = dict(os.environ, XDG_RUNTIME_DIR="/run/user/%d" % AUDIO_RUNTIME_UID)
    try:
        subprocess.run(
            ["wpctl", *args], env=env, check=True,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return True
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        log.warning("wpctl %s failed: %s", " ".join(args), exc)
        return False

# Mouse mode: the Arduino sends these instead once you double-press the
# joystick button. Pixels moved per event; the sketch repeats every 30ms,
# so this works out to roughly 400 pixels a second.
MOUSE_STEP = 12
MOUSE_MOVES = {
    "M_LEFT":  (-MOUSE_STEP, 0),
    "M_RIGHT": (MOUSE_STEP, 0),
    "M_UP":    (0, -MOUSE_STEP),
    "M_DOWN":  (0, MOUSE_STEP),
}


def find_port():
    for path in CANDIDATE_PORTS:
        if glob.glob(path):
            return path
    matches = sorted(glob.glob("/dev/ttyUSB*") + glob.glob("/dev/ttyACM*"))
    return matches[0] if matches else None


def open_serial():
    while True:
        port = find_port()
        if port:
            try:
                ser = serial.Serial(port, BAUD_RATE, timeout=1)
                log.info("Connected to Arduino on %s", port)
                return ser
            except serial.SerialException as exc:
                log.warning("Failed to open %s: %s", port, exc)
        else:
            log.warning("No Arduino serial device found, retrying...")
        time.sleep(RECONNECT_DELAY)


def main():
    # Advertise a full keyboard's key range, not just the 7 keys we send.
    # A device offering only a handful of keys is not always classified as a
    # keyboard, and then apps like Kodi ignore it.
    all_keys = sorted(set(range(e.KEY_ESC, e.KEY_COMPOSE + 1)) | set(KEY_MAP.values()))
    ui = UInput({e.EV_KEY: all_keys}, name="rpi-arduino-controller")
    # A separate device for the pointer. Keeping mouse and keyboard apart is
    # more reliable than one device claiming to be both.
    mouse = UInput(
        {
            e.EV_REL: [e.REL_X, e.REL_Y],
            e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT],
        },
        name="rpi-arduino-mouse",
    )
    # give udev a moment to publish the new devices before sending anything
    time.sleep(0.5)
    log.info("Virtual keyboard and mouse created")

    ser = open_serial()
    try:
        while True:
            try:
                line = ser.readline().decode(errors="ignore").strip()
            except (serial.SerialException, OSError) as exc:
                log.warning("Serial error (%s), reconnecting...", exc)
                try:
                    ser.close()
                except Exception:
                    pass
                ser = open_serial()
                continue

            if not line:
                continue

            if line == "POWER":
                log.info("Power button held - shutting down")
                for cmd in SHUTDOWN_CMDS:
                    try:
                        subprocess.run(cmd, check=True)
                        break
                    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
                        log.warning("%s failed: %s", cmd[0], exc)
                else:
                    log.error("No working shutdown command found")
                continue

            if line == "VOL_UP":
                if _wpctl("set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", VOLUME_STEP + "+"):
                    log.info("System volume up")
                continue

            if line == "VOL_DOWN":
                if _wpctl("set-volume", "@DEFAULT_AUDIO_SINK@", VOLUME_STEP + "-"):
                    log.info("System volume down")
                continue

            if line in MOUSE_MOVES:
                dx, dy = MOUSE_MOVES[line]
                if dx:
                    mouse.write(e.EV_REL, e.REL_X, dx)
                if dy:
                    mouse.write(e.EV_REL, e.REL_Y, dy)
                mouse.syn()
                continue

            if line == "M_CLICK":
                mouse.write(e.EV_KEY, e.BTN_LEFT, 1)
                mouse.syn()
                mouse.write(e.EV_KEY, e.BTN_LEFT, 0)
                mouse.syn()
                log.info("Mouse click")
                continue

            if line in ("MOUSE_ON", "MOUSE_OFF"):
                log.info("Mouse mode %s", "on" if line == "MOUSE_ON" else "off")
                continue

            keycode = KEY_MAP.get(line)
            if keycode is None:
                log.debug("Unknown command: %r", line)
                continue

            ui.write(e.EV_KEY, keycode, 1)
            ui.syn()
            ui.write(e.EV_KEY, keycode, 0)
            ui.syn()
            log.info("Sent key for %s", line)
    finally:
        try:
            ser.close()
        except Exception:
            pass
        ui.close()
        mouse.close()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log.info("Shutting down")
        sys.exit(0)
