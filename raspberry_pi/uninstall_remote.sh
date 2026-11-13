#!/bin/bash
# Removes the Retro TV phone remote and restores your previous tv.py.
# Run as your normal user (NOT with sudo):  bash uninstall_remote.sh
set -e

if [ "$(id -u)" -eq 0 ]; then
    echo "Run this as your normal user, not with sudo." >&2
    exit 1
fi

if [ -f "$HOME/tv.py.before-phone-remote" ]; then
    cp "$HOME/tv.py.before-phone-remote" "$HOME/tv.py"
    echo "restored your previous tv.py"
else
    echo "no backup found at $HOME/tv.py.before-phone-remote - tv.py left as is"
fi

rm -f "$HOME/remote_server.py" "$HOME/remote_page.html"
sudo rm -f /etc/udev/rules.d/60-retro-tv-uinput.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=uinput || true

echo
echo "Removed. Reboot to finish:  sudo reboot"
