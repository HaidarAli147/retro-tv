# Arduino Uno files

Open `rpi_controller_final/rpi_controller_final.ino` in Arduino IDE and upload
it to the Uno. Keep the sketch inside its matching folder. The firmware uses
9600 baud and controls joystick navigation, mouse mode and the volume knob.
Connect the Uno to the Pi with USB after uploading.

| Folder | Purpose |
|---|---|
| rpi_controller_final/ | Current firmware; use this for the TV |
| button_test/ | Separate button diagnostic |
| raw_diagnostic/ | Separate raw-input diagnostic |
| ir_dump/ | Older IR diagnostic; not the current build |
| rpi_controller_ir/ | Older IR controller; not the current build |

Diagnostic sketches replace the main firmware when uploaded; upload the current
sketch again afterward. The power button is handled separately by the Pi GPIO3
script, not the Uno. Firmware contents were not changed by this reorganization.
