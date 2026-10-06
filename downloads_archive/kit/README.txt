RETRO TV - REINSTALL KIT
========================
PART 1 - Flash the card (Raspberry Pi Imager, on this PC)
  Device: Raspberry Pi 4   OS: Raspberry Pi OS (64-bit) with desktop
  Click "Edit settings" / customisation and set:
    Hostname .......... Brack-Study
    Username/password . alshowaikh / (your password)
    Wi-Fi ............. your network name AND ITS PASSWORD, country BH
    Locale ............ your timezone
    Services .......... enable SSH (optional)
    Raspberry Pi Connect: enable, and paste a NEW auth key from
                          connect.raspberrypi.com (the old one was shared in chat; revoke it)
  Write the card.

PART 2 - Right after flashing, while the card is still in the PC (drive "bootfs")
  1. Copy this whole folder to bootfs and rename it "kit"  ->  bootfs:\kit
  2. Open bootfs:\cmdline.txt and add this to the END of the single line (a space first):
        video=HDMI-A-1:1280x720@60D
     Keep it one line. Also delete "quiet splash" there so you can see boot text.
  3. Eject the card.

PART 3 - First boot on the Pi
  Use the Pi's own 5V 3A supply. Plug in the Arduino USB. Boot to the desktop
  (use a normal TV/monitor the first time if the retro TV stays black).
  Open a terminal and run:
        bash /boot/firmware/kit/setup.sh
        sudo reboot

PART 4 - Check
  Volume knob:  wpctl status      (headphone jack should be the default sink)
  Bridge:       sudo systemctl status rpi-bridge
  Raspberry Pi Connect shows the device online.

NOT in this kit (you add these yourself)
  - Alkass 1 / Alkass 2 channels (expiring tokens) - add to channels.m3u
  - Your saved web-app sign-ins in tv.py (TOD etc.) - sign in again
  - Arduino sketch rpi_controller_final.ino is only needed if you re-flash the Uno
