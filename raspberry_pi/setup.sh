#!/bin/bash
# Retro TV one-shot setup. Run on the Pi (NOT with sudo):
#   bash ~/raspberry_pi/setup.sh
set -e
cd "$(dirname "$0")"

echo "== 1/5 Installing packages (needs internet) =="
sudo apt update
sudo apt install -y mpv python3-gi gir1.2-gtk-3.0 gir1.2-webkit2-4.1 \
    python3-serial python3-evdev wireplumber pipewire-pulse

echo "== 2/5 Installing the TV app =="
cp tv.py channels.m3u chime.wav "$HOME/"
chmod +x "$HOME/tv.py"

echo "== 3/5 Installing the Arduino bridge =="
sudo mkdir -p /opt/rpi-bridge
sudo cp rpi_bridge.py /opt/rpi-bridge/rpi_bridge.py
sudo cp rpi-bridge.service /etc/systemd/system/rpi-bridge.service
sudo systemctl daemon-reload
sudo systemctl enable --now rpi-bridge.service

echo "== 4/5 Starting the TV app at login =="
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/retro-tv.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Retro TV
Exec=python3 $HOME/tv.py
DESK

echo "== 5/5 Audio: headphone jack as default =="
ID=$(wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep -i "built-in audio" | grep -o '[0-9]\+\.' | head -1 | tr -d .)
if [ -n "$ID" ]; then wpctl set-default "$ID"; wpctl set-volume @DEFAULT_AUDIO_SINK@ 70%; echo "default sink $ID"; else echo "headphone sink not found; after reboot run: wpctl status"; fi
echo "Done. Reboot with: sudo reboot"
