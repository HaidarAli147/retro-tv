# Speaker volume and web-app icons

## Status

This change implements the requested speaker indicator and automatic web-app
icons. Matching the supplied design is **pending**: attachment metadata/text
was available, but its image could not be downloaded or viewed in this session.
The existing theme is retained pending an accessible reference.

## Current sources and installation

`raspberry_pi/tv.py` is the app source; the duplicate `pi_kit/` was consolidated.
`raspberry_pi/install_tv.sh` embeds the same source. Keep both synchronized whenever
the app changes. Files under `downloads_archive/` and `.bak` files are history.

On an existing configured Pi, replace the installed `~/tv.py` with the current
`raspberry_pi/tv.py` copy, then restart the app as the desktop user (not with sudo).
This preserves `~/.config/brack-tv/apps.json`, channel-resume state and web logins.
The one-file installer also replaces the bundled playlist and chime, so copy
only `tv.py` when preserving a customized playlist.

The existing full setup script still requires a working graphical desktop.
It has not been changed to install the separate power-button service in this task.

## What the volume bar means

- On the Pi, the home-screen bar reports `wpctl get-volume @DEFAULT_AUDIO_SINK@`
  in the logged-in desktop user's PipeWire session. It polls off the UI thread
  every 500 ms, with only one request in flight and a one-second command timeout.
- Turning the Arduino knob or changing the system volume triggers an on-screen
  percentage bar. Mute is shown alongside the stored percentage; the bar empties.
- mpv starts at 100% on Linux so it no longer adds a hidden 70% attenuation.
  **Playback may therefore sound louder than the previous build at the same
  speaker setting.** Start with a low system volume when checking the update.
- Output values over 100% are displayed honestly; the graphical bar fills at 100%.
- Missing `wpctl`, a disconnected/unavailable sink, or command failure displays
  `SPEAKER UNAVAILABLE`, not a made-up percentage. Polling continues for recovery.
- This is the default PipeWire output level, not a measurement of loudness or a
  separate physical speaker dial. An app manually routed to a different output
  can have a different level.
- The existing bridge still assumes desktop UID 1000. If it targets the wrong
  user's session, knob control must be configured separately; this indicator
  reads the actual session running the app.
- Windows playback, named-pipe IPC, and browser launching are preserved. The
  Windows startup OSD is explicitly labelled `PLAYER`; Windows system speaker
  percentage is not implemented and the home bar says so.

## Automatic app icons

Add a website using App Store as before. New and existing saved web apps, plus
TOD, discover icons automatically when their tiles are built. The app checks
the site's declared touch/icon links, then `/favicon.ico`, including relative
links and redirects. The first successfully decoded icon is shown.

Icons load on two background workers and are cached as PNGs for seven days in
`~/.cache/brack-tv/app-icons`. A cached icon can be used offline. Missing,
unsupported, oversized or inaccessible images leave the app's initials visible;
the tile can still launch. Requests use HTTP(S), bounded response sizes/timeouts,
no saved browser cookies and no third-party favicon service. Rebuilding/deleting
tiles cancels queued work and ignores callbacks belonging to the old tile row.
Sites exposing icons only through JavaScript or web manifests can fall back to
initials if they have no usable HTML icon or favicon.

## Verification

Run from the repository with the app's GTK/GdkPixbuf Python packages installed:

```sh
/usr/bin/python3 -m unittest discover -s tests -v
python3 -m py_compile raspberry_pi/tv.py
bash -n raspberry_pi/install_tv.sh
bash -n raspberry_pi/setup.sh
```

The offline tests exercise mocked PipeWire output/failures, mute and recovery,
single in-flight reads, icon discovery/cache and fallback, real GdkPixbuf image
decoding, resource limits, obsolete callbacks, and distribution consistency.
They do **not** establish hardware, live network, playback or Windows behavior.

Still to check on the working Pi: knob updates during playback and web apps,
mute/unmute, output reconnection/switching, icon fetching on real websites,
joystick focus, and layout on the actual display. GTK could be imported in the
development environment, but no graphical display was available for visual QA.
