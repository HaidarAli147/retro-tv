#!/usr/bin/env bash
# Install Raspberry Pi OS's Wayland-native on-screen keyboard for labwc.
# Run as the logged-in graphical desktop user (never with sudo).
set -euo pipefail
if [[ $(id -u) == 0 ]]; then echo "Run as the desktop user, not root." >&2; exit 1; fi
if [[ "${XDG_SESSION_TYPE:-}" != "wayland" && "${XDG_CURRENT_DESKTOP:-}" != *labwc* ]]; then
  echo "Note: this helper is intended for a Raspberry Pi OS labwc/Wayland session."
fi
sudo apt-get update
sudo apt-get install -y squeekboard dbus-user-session
gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true
# Raspberry Pi OS ordinarily starts squeekboard as part of desktop session.
# If the DBus service is absent, start it once within the existing Wayland session.
if ! busctl --user --no-pager list 2>/dev/null | grep -q 'sm.puri.OSK0'; then
  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    nohup squeekboard > "${XDG_RUNTIME_DIR:-/tmp}/retro-tv-squeekboard.log" 2>&1 < /dev/null &
  else
    echo "Run this once from a terminal INSIDE the Pi desktop to start the keyboard." >&2
  fi
fi
echo "Enabled the Raspberry Pi OS on-screen keyboard."
echo "Text-entry fields in compatible native Wayland apps open it automatically."
echo "For other apps use the taskbar keyboard icon or the helper: bash keyboard-toggle.sh show"
