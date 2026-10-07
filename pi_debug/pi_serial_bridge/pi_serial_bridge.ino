// Pi serial bridge: shows the Raspberry Pi's serial output in the Serial Monitor.
// Wiring: Pi pin 8 (TXD) -> Uno pin 10, Pi pin 6 (GND) -> Uno GND. Nothing on Uno pins 0/1.
// Serial Monitor: 115200 baud. The Pi side runs at 9600 (serialtest.img and
// prep_usb_serial.ps1 -Mode linux both use 9600).
#include <SoftwareSerial.h>

SoftwareSerial pi(10, 11);  // RX = pin 10 (from Pi), TX = pin 11 (unused)

unsigned long bytes = 0;
unsigned long lastReport = 0;

void setup() {
  Serial.begin(115200);
  pi.begin(9600);
  Serial.println(F("BRIDGE READY - waiting for the Pi on pin 10 (9600 baud)"));
}

void loop() {
  while (pi.available()) {
    Serial.write(pi.read());
    bytes++;
  }
  // until anything arrives, say so every 10 s so a silent Pi is obvious
  if (bytes == 0 && millis() - lastReport >= 10000) {
    lastReport = millis();
    Serial.println(F("[bridge] nothing from the Pi yet"));
  }
}
