# Raspberry Pi software

## Copy from PC using a USB drive

1. Download the repository ZIP from GitHub (`Code > Download ZIP`) and extract it.
2. Copy the entire `raspberry_pi` folder to a USB drive.
3. Boot the Pi into its working graphical desktop, plug in the USB drive,
   and use File Manager to copy that folder to your home folder.
4. Open a terminal on the Pi and run:

```sh
cd ~/raspberry_pi
bash setup.sh
```

Run setup as your normal desktop user, not with `sudo bash`. It requests sudo
for package/service installation and needs internet. It installs the app to
your home folder, installs the Arduino bridge, and adds desktop-login autostart.
It does not install a desktop on Raspberry Pi OS Lite.

After setup, launch with:

```sh
python3 ~/tv.py
```

For an already configured Pi where you only want to update the app while
keeping a customized playlist:

```sh
cp ~/raspberry_pi/tv.py ~/tv.py
```

Close and reopen the app after copying.

## Wayland system-wide on-screen keyboard (labwc)

Your Pi desktop uses labwc/Wayland. Install Raspberry Pi OS's Squeekboard,
not X11-only Onboard/Matchbox, from a terminal opened **on the Pi desktop**:

```sh
cd ~/raspberry_pi
bash keyboard-setup.sh
```

The desktop keyboard is independent of Retro TV; text fields in compatible
Wayland apps can request it automatically. Retro TV's App Store name/URL fields
also request it when focused (after updating `tv.py`). For embedded WebKit websites, Retro TV now detects editable HTML fields and
requests the keyboard automatically on focus and hides it on blur. Dynamic
sites and iframe behavior still require testing on the Pi. In other Xwayland
programs outside Retro TV, automatic focus detection is not guaranteed:
use the Pi panel's keyboard icon, or run `bash ~/raspberry_pi/keyboard-toggle.sh show`
from a desktop terminal. Hide it with the helper's `hide` argument.

**Important:** Older Squeekboard builds can sit *behind actual fullscreen*
windows in labwc. If the keyboard appears but is invisible, exit fullscreen
with F11 or use a non-fullscreen maximized window. Keyboard support in custom
websites also depends on the site's fields and the toolkit's Wayland integration.
The joystick's mouse mode can click web fields and on-screen keys; pure
joystick-arrow-only typing outside TV's own LIVE search is not implemented.
This setup is for Raspberry Pi OS, not the Windows version of `tv.py`.

## Power button

`setup.sh` still does not install the separate GPIO3 service. From this folder,
install it separately if it is not already configured:

```sh
sudo apt install -y python3-gpiozero
sudo mkdir -p /opt/rpi-bridge
sudo cp power_button.py /opt/rpi-bridge/power_button.py
sudo cp power-button.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now power-button.service
```

The button connects only to Pi GPIO3 (physical pin 5) and GND. Hold for two seconds
to request shutdown. Physical operation remains to be checked on your Pi.

## Other files

- `tv.py`: current app source, also runnable on Windows.
- `install_tv.sh`: self-contained app/playlist/chime installer, for a previously
  configured system; it does not install dependencies or services.
- `rpi_bridge.py`, `rpi-bridge.service`: Uno serial-to-input bridge.
- `run_tv_windows.bat`, `README_WINDOWS.txt`: existing Windows support.
- `diagnostics/`: Pi boot investigation files, including tools run from Windows.
  These are not required for normal installation. Do not copy bootloader files
  onto the SD card as part of transferring the TV app.
- `tv.py.pre_windows.bak`: historical backup, not the current app.

If the Pi still stops at a rainbow or black screen, transferring these files
will not repair that boot problem. First get it booting into its desktop.
