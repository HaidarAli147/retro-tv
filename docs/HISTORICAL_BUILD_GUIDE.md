# Historical guide — obsolete paths, wiring and software

Use the current root README and platform folders instead. The text below is preserved as history.

# Current TV app update

For the Python/GTK app's speaker-percentage indicator, automatic web-app icons,
current installation copies and validation limits, see
[Speaker volume and web-app icons](docs/TV_VOLUME_AND_ICONS.md).
The older build guide below still contains legacy Kodi/display/wiring details;
it is not the current app installation guide.

> **Current enclosure status (2026-10-10):** The project has moved to a 22-inch HDMI monitor. Start with the [current design review and measurement checklist](enclosure_work/DESIGN_REVIEW_22IN.md) and `enclosure_22in.scad`. Monitor values remain placeholders: do not cut from them. The 14-inch enclosure instructions below are historical.

# Retro-TV media box — final build

A 14" laptop panel in a retro-TV case, driven by an LVDS controller board,
with a Raspberry Pi running Kodi (OSMC) and an Arduino Uno handling the
front controls.

**There is no IR receiver in this build.** Navigation comes from the
joystick. The remote and the IR parts were dropped.

## Controls

| Control | Action |
|---|---|
| Joystick | up / down / left / right |
| Joystick press | enter / select |
| Knob | volume up / down |
| Button | hold 2 seconds to shut the Pi down safely |

## Files

| File | Where it goes |
|---|---|
| `rpi_controller_final.ino` | Arduino Uno |
| `rpi_bridge.py` | Pi, at `/opt/rpi-bridge/rpi_bridge.py` |
| `rpi-bridge.service` | Pi, at `/etc/systemd/system/rpi-bridge.service` |
| `enclosure_v7.scad` | Editable 3D source (OpenSCAD) |
| `side_frame.stl` | Front + back + sides, one piece |
| `bottom_panel.stl` | Floor, with Pi and Arduino standoffs |
| `top_panel.stl` | Vented lid |
| `panel_cover.stl` | Cover that pins the screen panel |

## Wiring

The Uno has one 5V pin, so join the joystick and knob 5V leads into it. It
has three GND pins, so give each part its own.

| Part | Pin | Arduino |
|---|---|---|
| Joystick | GND | GND |
| Joystick | +5V | 5V |
| Joystick | VRx | A0 |
| Joystick | VRy | A1 |
| Joystick | SW | D2 |
| Knob | outer leg | 5V |
| Knob | middle (wiper) | A2 |
| Knob | other outer leg | GND |
| Button | one leg | D4 |
| Button | other leg | GND |

Wire the joystick by the labels printed on its board, not by the order of
the pins. Getting GND and +5V backwards is what destroyed the IR receiver
earlier in this project.

The button is a 4-leg tactile switch: the two legs on the same side are
permanently joined, so use one leg from the front and one from the back,
and leave the other two unconnected.

Arduino to Pi is a single USB cable. It carries power and data.

## Software

Flash `rpi_controller_final.ino` to the Uno. It needs no libraries. Put it
in a folder whose name matches the file, e.g.
`rpi_controller_final/rpi_controller_final.ino`.

Test it before touching the Pi: open Serial Monitor at **9600 baud** and
confirm each control prints its command.

Then on the Pi:

```
sudo apt update
sudo apt install -y python3-serial python3-evdev
sudo mkdir -p /opt/rpi-bridge
sudo cp rpi_bridge.py /opt/rpi-bridge/rpi_bridge.py
sudo cp rpi-bridge.service /etc/systemd/system/rpi-bridge.service
sudo systemctl daemon-reload
sudo systemctl enable --now rpi-bridge.service
```

Check it and watch its log:

```
sudo systemctl status rpi-bridge.service
sudo journalctl -u rpi-bridge.service -f
```

The service runs as root, which it needs for `/dev/uinput` and for the
shutdown. It finds the Arduino's serial port by itself and reconnects if
the cable is pulled, so there is no port name to edit.

If the knob does nothing in Kodi, install Kodi's **Keymap Editor** add-on
and bind `VOLUMEUP` / `VOLUMEDOWN`. Kodi does not always map those keys by
default. The arrow keys and enter work with no setup.

## Enclosure

Frame 384 × 215 × 260 mm, walls 3 mm.

Assembly order:
1. Screw the bottom panel on. Mount the Pi and Arduino on its standoffs.
2. Mount the joystick behind the front wall with 4 self-tapping M2 screws.
   Push the knob and button through their holes from the front.
3. Drop the screen panel in from the top. It slides down between the front
   wall and the side guides and rests on two ledges.
4. Drop the cover in right behind it. Two lips hold it from behind.
5. Screw the top panel on.

Cables leave through the opening in the back wall, 120 × 40 mm. Vents are
in the lid and high on both side walls.

### Check these before cutting or printing

These are typical 14" values, not measured from your panel:

| Variable | Set to | What it is |
|---|---|---|
| `screen_w`, `screen_h` | 310 × 174 | visible (lit) area |
| `panel_outline_w`, `panel_outline_h` | 324 × 206 | panel outer size |
| `panel_t` | 6 | panel thickness |
| `panel_bottom_extra` | 20 | opening bottom edge to panel bottom edge |

Measure yours with calipers and change them at the top of
`enclosure_v7.scad`. Everything else is derived from them, so the channel,
guides, ledges and cover all resize on their own. Re-export the STLs after
any change.

### Printing

At 384 × 260 mm the frame is larger than a normal printer bed (~220–250 mm).
Laser-cut it from 3 mm acrylic or plywood, or split it for printing. The
other three parts are flat and easy.

Sliding clearance is 0.4 mm. If the panel binds or rattles, change
`fit_clr` and re-export.

## Still to do

The LVDS driver board is not in the model yet. When it arrives, measure its
length, width, mounting hole positions and connector positions, and add its
standoffs plus rear cutouts for HDMI, VGA and power.

