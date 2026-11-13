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

## Update only `tv.py` from GitHub (existing Raspberry Pi installation)

Use this procedure on the **Raspberry Pi graphical desktop**, as the normal desktop
user. It updates only the installed `~/tv.py`, **not** your `channels.m3u`,
saved web apps, Arduino firmware, services, or the rest of the repository.
Do **not** run `setup.sh` just to update this one file: that installer also
copies the playlist and sound file.

**Step 1: Check/install dependencies** (first installation only; requires internet):

```sh
sudo apt update
sudo apt install -y mpv python3-gi gir1.2-gtk-3.0 gir1.2-webkit2-4.1 network-manager
```

`NetworkManager` must manage the Wi-Fi device for the in-app Wi-Fi settings
to function. Avoid replacing an already-working network configuration just
for this update. The existing Arduino bridge and PipeWire installation are
separate and are not reinstalled by these commands.

**Step 2: Back up the running copy** (run before replacing it):

```sh
cp ~/tv.py ~/tv.py.backup
```

If `~/tv.py` does not exist yet, skip that command. The procedure otherwise
assumes Retro-TV is already set up.

**Step 3: Download just the Python file** into a temporary path:

```sh
curl -fL https://raw.githubusercontent.com/HaidarAli147/retro-tv/main/raspberry_pi/tv.py -o ~/tv.py.new
```

**Step 4: Check Python syntax, then install only that file:**

```sh
python3 -m py_compile ~/tv.py.new
mv ~/tv.py.new ~/tv.py
```

Run these only if the download succeeded. If compilation fails, do not run
the `mv` command; leave the previous `~/tv.py` in place. A successful syntax
check is **not** a full hardware or UI functionality test.

**Step 5: Close the old app and launch the updated one:**

```sh
python3 ~/tv.py
```

Do not run the graphical app with `sudo`. If you have a desktop autostart
entry from `setup.sh`, it already launches `~/tv.py` at login; closing
and reopening the TV app is enough.

**Restore the previous version** if something goes wrong:

```sh
cp ~/tv.py.backup ~/tv.py
python3 ~/tv.py
```

**Optional: if you are working inside a local Git checkout** and want to
update *only its tracked application file* without checking out other paths:

```sh
cd ~/retro-tv
git fetch origin main
git restore --source=origin/main -- raspberry_pi/tv.py
```

This option updates `~/retro-tv/raspberry_pi/tv.py` and does **not**
automatically update the installed `~/tv.py`; copy it there explicitly only
if that is the intended source. `git restore` overwrites any uncommitted
local edits to the named file.

### New interface features and current testing status

The current `tv.py` source includes a Shift-capable on-screen keyboard for
Retro-TV text entry, a SETTINGS tile with Wi-Fi scanning/connection via
`nmcli`, configurable Esc / Back behavior, and an App Store form to append
live channels to the currently selected M3U playlist. The app is also intended
to show an on-screen keyboard in embedded web forms.

Controls: move/select with the joystick, use SHIFT to change letter case,
and use DONE to finish text entry. **DONE on the App Store URL field now
submits the app**, just like Enter. The visible **ADD WEBSITE APP** control
also submits the name/URL. Choose **+ ADD NEW LIVE TV CHANNEL**, fill the
channel name, stream URL, optional category/logo, then focus **SAVE CHANNEL**
to append the stream to the M3U playlist. The channel editor is above the
installed-app list so it remains reachable. Up/down moves through App Store
actions; joystick press activates the selected action. Esc/long-press backs
out of a step; Settings can switch between **back one step** and **always
home**. LIVE TV search keyboard remains available.

**Unverified:** these combined changes were committed from source review, not
tested on a physical Raspberry Pi. Some web login fields, joystick focus,
NetworkManager configurations, and playback may need adjustment after testing.
The `raspberry_pi/install_tv.sh` embedded app copy has not been synchronized
with this newer `tv.py`; use the single-file update above rather than that
installer when you need these changes.

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


## Goaaal Live Match Viewer (camera feed, not scoreboard)

Retro TV's **GOAAAL LIVE** home tile opens `https://appendhub.com/go-wall/app/?match-view`. It is a camera-only viewer for matches streamed from the Goaaal VAR controller, not a scoreboard or an IPTV channel.

1. Start a Goaaal display/controller session elsewhere and connect the VAR camera phones.
2. Open **GOAAAL LIVE** on Retro TV; type the eight-digit match code shown on the controller in **Live Match Viewer**, then select **Connect to live match**.
3. On the Goaaal controller, choose **📺 Send live match** under the camera you want on Retro TV. You can change cameras without leaving the viewer.

The Pi needs network access and a WebRTC-capable browser engine. The embedded WebKitGTK view may lack suitable codecs or WebRTC support on some Raspberry Pi OS images. If it fails, use Chromium on the Pi to open the same viewer link; this path is not a guaranteed hardware-accelerated mpv stream. The Goaaal website and Retro TV additions must both be deployed to use the new feature.

## Phone remote (test branch `feature/phone-remote`, not on main)

A **PHONE REMOTE** tile on the Home screen shows a QR code, the Pi's address
and a 6-digit code. Any phone **on the same Wi-Fi** that scans it gets a remote:
D-pad, OK, Back, volume/mute, a text box that types on the TV (Wi-Fi passwords,
URLs) and a touchpad with left/right click and scroll. There is no power button
on the phone on purpose.

**At start-up the TV now opens the PHONE REMOTE screen** instead of resuming
live TV. The last channel stays highlighted in LIVE TV but does not autoplay.
If the remote cannot start (files missing, no free port), the TV falls back to
the old behaviour and resumes live TV.

Files: `remote_server.py` (small web server started by `tv.py`, runs as your
user, never root) and `remote_page.html` (the phone page). It makes its own
virtual keyboard and mouse, so it **does not use or change `rpi_bridge.py`**;
the joystick keeps working alongside it.

Install (from the folder with these files, as your normal user):

    bash install_remote.sh
    sudo reboot

The installer backs up `~/tv.py` to `~/tv.py.before-phone-remote`, installs
`python3-qrcode`, copies the three files to your home folder and adds
`/etc/udev/rules.d/60-retro-tv-uinput.rules` (lets only the user logged in at
the Pi's screen create a virtual keyboard/mouse - no group changes). It does not touch the Arduino bridge, the shutdown
button service, the playlist or the chime. **Do not run `setup.sh` for this**:
it would replace the bridge in `/opt/rpi-bridge`.

Undo:

    bash uninstall_remote.sh

Checks: `python3 -m unittest tests.test_remote_server -v` (no display needed).
Typing is English letters, numbers and symbols only, and assumes a US
keyboard layout on the Pi (check: `cat /etc/default/keyboard`; with a UK
layout, `@ " # ~ \ |` would come out wrong). Too many wrong codes from
different phones makes a new code (the TV redraws the QR); paired phones
keep working. The REMOTE screen says
"KEYS/MOUSE OFF" if the uinput permission is missing; volume still works then.

## Sound output (Settings)

Settings now has **SOUND OUTPUT** at the top. Press **LEFT / RIGHT** (joystick,
keyboard or the phone remote) or click ◀ ▶ to switch between the outputs the Pi
has: speaker (3.5 mm jack), TV / monitor (HDMI), or any USB / Bluetooth speaker.
It changes PipeWire's default output (`wpctl set-default`), so live TV, the
chime, web apps and the volume knob all follow it. The choice is saved in
`~/.config/retro-tv/preferences.json` and applied again at start-up if that
output is present. Note: the Pi 4's headphone jack cannot detect whether
speakers are plugged in, so this is a manual choice.

## Resolution (Settings)

Settings has **RESOLUTION** under SOUND OUTPUT. In Settings, **UP / DOWN** move
the yellow box between SOUND OUTPUT, RESOLUTION and the Wi-Fi list; **LEFT /
RIGHT** change the highlighted setting. RESOLUTION lists only the modes your
monitor reports (via `wlr-randr`, installed by `install_remote.sh`). After a
change the TV shows **KEEP? PRESS OK (15)**: press OK (or click KEEP) to keep
it; BACK or waiting 15 seconds goes back to the old resolution, so a mode the
monitor can't show never leaves you with a black screen. The kept choice is
saved in `~/.config/retro-tv/preferences.json` and restored 3 seconds after the
TV app starts. Lower resolutions make everything bigger but slightly softer.

## Screen size (Settings)

The TV app now **sizes itself to the screen**. It was designed for 720p, so
by default (**SCREEN SIZE: AUTO**) it scales everything by screen height ÷ 720:
1080p = 150%, 4K = 300%. The top row of Settings, **SCREEN SIZE**, lets you
pick AUTO or a fixed 50% – 400% with LEFT / RIGHT; it changes instantly and is
saved in `~/.config/retro-tv/preferences.json` (`"ui_scale"`). Text, tiles,
lists, keyboards, the QR code, logos and web-app zoom all follow it, and it
re-fits automatically when the screen resolution changes. SCREEN SIZE keeps
the picture sharp; RESOLUTION (below it) changes the real HDMI mode.
