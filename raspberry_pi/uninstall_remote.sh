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
sudo rm -f /etc/udev/rules.d/99-retro-tv-uinput.rules
sudo udevadm control --reload-rules

echo
echo "Removed. Your user is still in the 'input' group; to remove that too:"
echo "    sudo gpasswd -d $USER input"
echo "Log out and back in (or reboot) to finish."
