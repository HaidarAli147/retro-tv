# Retro TV

A Python/GTK TV interface with mpv playback, web-app tiles, Arduino Uno joystick
and volume controls, and a separate Raspberry Pi GPIO3 shutdown button.

## Files

| Folder | Contents |
|---|---|
| [raspberry_pi/](raspberry_pi/) | TV app, playlists, sounds, installers, bridge, services, power-button script, Windows launcher and Pi diagnostics |
| [arduino/](arduino/) | Current Uno firmware and separate diagnostic/older sketches |
| [enclosure_work/](enclosure_work/) | Enclosure models and design review |
| [docs/](docs/) | Software notes and historical build guide |
| [pptx_work/](pptx_work/) | Current project-fair PowerPoint, supplied source deck and refresh script |
| [tests/](tests/) | Offline app checks |
| downloads_archive/ | Historical snapshots; not installation sources |

Start with [raspberry_pi/README.md](raspberry_pi/README.md) to transfer and install
the Pi software. Flash [arduino/rpi_controller_final/rpi_controller_final.ino](arduino/rpi_controller_final/rpi_controller_final.ino)
to the Uno using Arduino IDE.

The old root files and duplicate `pi_kit/` have been consolidated. Existing
installed paths (`~/tv.py`, `/opt/rpi-bridge/`, systemd units) are unchanged.
The Arduino firmware has one current source; all copies were identical before consolidation.
Future app changes must also update the embedded source in
`raspberry_pi/install_tv.sh`.

## Current design

The frame is reported complete. The project moved to a 22-inch HDMI monitor;
future sizes are customer-specific. See the
[current design review](enclosure_work/DESIGN_REVIEW_22IN.md).
CAD monitor dimensions remain placeholders, not final cutting measurements.

## Notes

- [Speaker volume and automatic icons](docs/TV_VOLUME_AND_ICONS.md)
- [Windows instructions](raspberry_pi/README_WINDOWS.txt)
- [Project log](PROJECT_LOG.md) (old paths describe the layout at that time)
- [Historical build guide](docs/HISTORICAL_BUILD_GUIDE.md) (obsolete Kodi, wiring and 14-inch instructions)

Do not connect the power button to both boards. The current button connects
only to Pi GPIO3 (physical pin 5) and GND; it is not on Arduino D4.
