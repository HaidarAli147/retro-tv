// Pi serial bridge: shows the Raspberry Pi's serial output in the Serial Monitor.
// Wiring: Pi pin 8 (TXD) -> Uno pin 10, Pi pin 6 (GND) -> Uno GND. Nothing on Uno pins 0/1.
// Serial Monitor: 115200 baud. The Pi side runs at 9600 (serialtest.img and
// prep_usb_serial.ps1 -Mode linux both use 9600).
#include <SoftwareSerial.h>

SoftwareSerial pi(10, 11);  // RX = pin 10 (from Pi, pull-up on), TX = pin 11 (unused)

unsigned long bytes = 0;
unsigned long lastByte = 0;
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
    lastByte = millis();
  }
  // every 10 s of silence, say so and show the line level:
  // HIGH = idle line or no wire (pull-up), LOW = wire on GND or the Pi pin held low
  unsigned long now = millis();
  if (now - lastByte >= 10000 && now - lastReport >= 10000) {
    lastReport = now;
    Serial.print(F("\r\n[bridge] nothing new for 10 s, "));
    Serial.print(bytes);
    Serial.print(F(" bytes so far, pin 10 is "));
    Serial.println(digitalRead(10) ? F("HIGH (idle line, or no wire)")
                                   : F("LOW (wire on a GND pin, or the Pi pin is held low)"));
  }
}
