#!/bin/bash
# Lets phones on the TV's own hotspot open  http://retrotv.remote:<port>  instead of numbers.
# Works ONLY on the hotspot (its built-in DNS answers the name); on your home Wi-Fi the
# router doesn't know it, and the TV keeps showing the number address there.
#
# Run as your normal user, NOT with sudo (it asks for your password where needed):
#     bash install_hotspot_name.sh            # set it up
#     bash install_hotspot_name.sh --remove   # undo
# It writes one file: /etc/NetworkManager/dnsmasq-shared.d/retro-tv.conf
# Then restart the TV app (it switches the hotspot off and on).
set -u
NAME=retrotv.remote
ADDR=10.42.0.1
DIR=/etc/NetworkManager/dnsmasq-shared.d
FILE=$DIR/retro-tv.conf

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Run this as your normal user, not with sudo." >&2; exit 1
fi
if [ "${1:-}" = "--remove" ]; then
    sudo rm -f "$FILE"
    nmcli connection down RetroTV-Hotspot >/dev/null 2>&1
    echo "Removed. The TV shows the number address again after restarting the TV app."
    exit 0
fi
command -v nmcli >/dev/null 2>&1 || { echo "ERROR: NetworkManager (nmcli) is not installed." >&2; exit 1; }
sudo mkdir -p "$DIR" || exit 1
echo "address=/$NAME/$ADDR" | sudo tee "$FILE" >/dev/null || exit 1
sudo chmod 644 "$FILE"
# the hotspot's DNS reads the file only when it starts
nmcli connection down RetroTV-Hotspot >/dev/null 2>&1
echo "Done: on the TV's hotspot, $NAME now points to the TV ($ADDR)."
echo "Restart the TV app. On the phone, type the full address shown on the TV, with http://"
echo "Undo any time:  bash install_hotspot_name.sh --remove"
