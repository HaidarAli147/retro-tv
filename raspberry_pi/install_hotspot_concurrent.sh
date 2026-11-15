#!/bin/bash
# Lets the TV run its own Wi-Fi hotspot AND stay connected to your normal Wi-Fi
# at the same time (otherwise the single Wi-Fi radio can only do one of the two).
#
# Run as your normal user, NOT with sudo (it asks for your password where needed):
#     bash install_hotspot_concurrent.sh            # set it up
#     bash install_hotspot_concurrent.sh --remove   # undo
#
# What it does:
#   1. checks that your Wi-Fi adapter can serve a hotspot and a normal connection together
#      (it asks the adapter itself; if the answer is no, nothing is changed)
#   2. installs "iw" if missing
#   3. creates a second, virtual Wi-Fi interface called ap0 on the same adapter
#   4. adds one udev rule (/etc/udev/rules.d/70-retro-tv-ap0.rules) so ap0 comes back
#      after every reboot
# tv.py notices ap0 by itself: HOTSPOT AUTO then keeps the hotspot on beside your Wi-Fi.
# The hotspot uses the same channel as your Wi-Fi (a Wi-Fi chip can only do one at a time);
# if your router changes channel, restart the TV app.
set -u
AP=ap0
RULE=/etc/udev/rules.d/70-retro-tv-ap0.rules

die() { echo "ERROR: $*" >&2; exit 1; }

# Reads `iw phy ... info` text on stdin; exit 0 if one "valid interface combination"
# allows managed + AP at once (total >= 2). Each combination starts with "*" and may
# continue on the next line(s).
combos_allow_both() {
    awk '
        function check() {
            if (rec ~ /managed/ && rec ~ /AP/ && match(rec, /total <= [0-9]+/) &&
                substr(rec, RSTART + 9, RLENGTH - 9) + 0 >= 2) found = 1
        }
        /^[[:space:]]*\*/ { check(); rec = $0; next }
        { rec = rec " " $0 }
        END { check(); exit !found }'
}

if [ "${1:-}" = "--check-combos" ]; then      # used by the tests: reads iw output on stdin
    combos_allow_both
    exit $?
fi

if [ "$(id -u)" -eq 0 ]; then
    die "Run this as your normal user, not with sudo."
fi

if [ "${1:-}" = "--remove" ]; then
    nmcli connection down RetroTV-Hotspot >/dev/null 2>&1
    nmcli connection delete RetroTV-Hotspot >/dev/null 2>&1
    sudo iw dev "$AP" del >/dev/null 2>&1
    sudo rm -f "$RULE"
    sudo udevadm control --reload-rules
    echo "Removed. The hotspot will use the single radio again (only when there is no network)."
    exit 0
fi

command -v nmcli >/dev/null 2>&1 || die "NetworkManager (nmcli) is not installed."

echo "== 1/4 Finding your Wi-Fi adapter =="
DEV="${1:-$(nmcli -t -f DEVICE,TYPE device | awk -F: -v ap="$AP" '$2=="wifi" && $1!=ap {print $1; exit}')}"
[ -n "$DEV" ] || die "No Wi-Fi adapter found."
echo "adapter: $DEV"

echo
echo "== 2/4 Installing iw (if needed) =="
if ! command -v iw >/dev/null 2>&1; then
    sudo apt-get install -y iw || die "Could not install iw."
fi
IW="$(command -v iw)"

PHY="$("$IW" dev "$DEV" info 2>/dev/null | awk '/wiphy/ {print "phy" $2; exit}')"
[ -n "$PHY" ] || die "Could not find the radio (phy) behind $DEV."
MAC="$(cat "/sys/class/ieee80211/$PHY/macaddress" 2>/dev/null)"
[ -n "$MAC" ] || die "Could not read the radio's address."

echo
echo "== 3/4 Asking the adapter whether it can do both at once =="
INFO="$("$IW" phy "$PHY" info 2>/dev/null)"
echo "$INFO" | grep -q '^[[:space:]]*\* AP$' || die "This adapter cannot act as a hotspot (no AP mode). Nothing was changed."
COMBOS="$(echo "$INFO" | sed -n '/valid interface combinations/,/Device supports/p')"
echo "$COMBOS" | grep -v "Device supports" | sed 's/^/    /'
# one combination must allow normal Wi-Fi (managed) and AP together, with room for 2+
# (iw wraps each long combination over two lines, so the lines are joined first)
if ! echo "$COMBOS" | combos_allow_both; then
    die "This adapter cannot be a hotspot and join a Wi-Fi at the same time. Nothing was changed. The TV will keep using the single-radio mode (hotspot only when there is no network)."
fi
echo "OK: the adapter allows both."

echo
echo "== 4/4 Creating $AP and making it permanent =="
if ! ip link show "$AP" >/dev/null 2>&1; then
    sudo "$IW" phy "$PHY" interface add "$AP" type __ap || die "Could not create $AP."
fi
STA_MAC="$(cat "/sys/class/net/$DEV/address" 2>/dev/null)"
AP_MAC="$(cat "/sys/class/net/$AP/address" 2>/dev/null)"
if [ -n "$STA_MAC" ] && [ "$STA_MAC" = "$AP_MAC" ]; then
    # two interfaces must not share an address: flip the "locally administered" bit
    NEW="$(python3 - "$STA_MAC" <<'EOF'
import sys
b = [int(x, 16) for x in sys.argv[1].split(":")]
b[0] |= 0x02
b[5] ^= 0x01
print(":".join("%02x" % x for x in b))
EOF
)"
    sudo ip link set dev "$AP" address "$NEW"
fi
echo "SUBSYSTEM==\"ieee80211\", ACTION==\"add\", ATTR{macaddress}==\"$MAC\", RUN+=\"$IW phy %k interface add $AP type __ap\"" \
    | sudo tee "$RULE" >/dev/null
sudo udevadm control --reload-rules
sudo nmcli device set "$AP" managed yes >/dev/null 2>&1
sleep 3
STATE="$(nmcli -t -f DEVICE,STATE device | awk -F: -v ap="$AP" '$1==ap {print $2}')"
echo "$AP state in NetworkManager: ${STATE:-not listed}"
case "$STATE" in
    unmanaged|unavailable|"")
        echo "WARNING: NetworkManager is not using $AP yet. Reboot once, then run:  nmcli device" >&2 ;;
esac

echo
echo "Done. Restart the TV app. With HOTSPOT on AUTO the hotspot now runs beside your Wi-Fi."
echo "Undo any time:  bash install_hotspot_concurrent.sh --remove"
