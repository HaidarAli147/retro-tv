#!/bin/bash
# Installs the Retro TV phone remote on the Pi. Run as your normal user
# (NOT with sudo), from the folder that contains these files:
#   bash install_remote.sh
#
# What it does:
#   1. Backs up your current ~/tv.py to ~/tv.py.before-phone-remote (once)
#   2. Installs python3-qrcode (draws the QR code)
#   3. Copies tv.py, remote_server.py and remote_page.html to your home folder
#   4. Lets the logged-in desktop user create a virtual keyboard/mouse
#      (/dev/uinput) - the same kind of rule Steam uses for controllers
#
# It does NOT touch the Arduino bridge, its service, the GPIO shutdown
# service, your playlist or your chime. Undo with: bash uninstall_remote.sh
set -e
cd "$(dirname "$0")"

if [ "$(id -u)" -eq 0 ]; then
    echo "Run this as your normal user, not with sudo." >&2
    exit 1
fi
for f in tv.py remote_server.py remote_page.html; do
    [ -f "$f" ] || { echo "Missing $f next to this script." >&2; exit 1; }
done
python3 -m py_compile tv.py remote_server.py

echo "== 1/4 Backing up your current tv.py =="
if [ -f "$HOME/tv.py" ] && [ ! -f "$HOME/tv.py.before-phone-remote" ]; then
    cp "$HOME/tv.py" "$HOME/tv.py.before-phone-remote"
    echo "saved $HOME/tv.py.before-phone-remote"
else
    echo "backup already exists (or no tv.py yet) - keeping it"
fi

echo "== 2/4 Installing python3-qrcode =="
sudo apt install -y python3-qrcode

echo "== 3/4 Copying the remote files =="
cp tv.py remote_server.py remote_page.html "$HOME/"
chmod +x "$HOME/tv.py"

echo "== 4/4 Allowing the virtual keyboard/mouse =="
# "uaccess" gives access only to whoever is logged in at the Pi's screen,
# not to every program in a group. The file name must sort before 73-.
RULE=/etc/udev/rules.d/60-retro-tv-uinput.rules
echo 'KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"' \
    | sudo tee "$RULE" >/dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=uinput || true

echo
echo "Done. Reboot so the TV app restarts with the remote:"
echo "    sudo reboot"
echo "Then open PHONE REMOTE on the TV's home screen and scan the QR code."
