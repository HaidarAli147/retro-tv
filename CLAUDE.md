# Retro TV project

## Project log (required)
Record **everything that happens** in `PROJECT_LOG.md`, not just file changes:
tests proposed, instructions given, results the user reports (photos, LED
patterns, screen output), decisions, hardware the user does or doesn't have,
and dead ends. One table row per event, newest at the top:
`| YYYY-MM-DD | Area | What happened |`. Add the row in the same commit as the
related change, and commit + push log-only updates too.

## Repo notes
- Keep LF line endings (`core.autocrlf=false`); scripts run on the Pi.
- `network-config` / `user-data` are gitignored (Wi-Fi password, Pi Connect key). Never commit them.
- The Pi and the user's PC are local hardware a cloud session can't reach: give steps, the user runs them.

## Current layout
- Raspberry Pi software and diagnostics: `raspberry_pi/`.
- Current Uno firmware: `arduino/rpi_controller_final/rpi_controller_final.ino`.
- Keep `raspberry_pi/tv.py` and the embedded source in `raspberry_pi/install_tv.sh` consistent.
- Historical archives and old log paths are not active installation sources.
- Direct main updates were authorized once for the platform-folder reorganization only; subsequent work uses the user's branch workflow.
