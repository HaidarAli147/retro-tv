// Pi serial bridge v3: shows the Raspberry Pi's serial output in the Serial Monitor.
// Wiring: Pi pin 8 (TXD) -> Uno pin 10, Pi pin 6 (GND) -> Uno GND. Nothing on Uno pins 0/1.
// Serial Monitor: 115200 baud. The Pi side runs at 9600 (serialtest.img and
// prep_usb_serial.ps1 -Mode linux both use 9600).
#include <SoftwareSerial.h>

SoftwareSerial pi(10, 11);  // RX = pin 10 (from the Pi); pin 11 is released in setup()

unsigned long bytes = 0;
unsigned long lastByte = 0;
unsigned long lastReport = 0;

void setup() {
  Serial.begin(115200);
  pi.begin(9600);
  pinMode(11, INPUT);  // SoftwareSerial drives its TX pin; we never send, so let it float
  Serial.println(F("BRIDGE v3 READY - waiting for the Pi on pin 10 (9600 baud)"));
}

// Line level with the Uno's pull-up on and off:
//   on HIGH, off HIGH = something drives it high (the test idling), or no wire
//   on HIGH, off LOW  = a Pi pin nobody drives (its own pull-down), or no wire
//   on LOW,  off LOW  = wire on a GND pin, or the Pi pin is driven low
void reportLevel() {
  pi.stopListening();
  pinMode(10, INPUT);
  delayMicroseconds(500);
  int pullOff = digitalRead(10);
  pinMode(10, INPUT_PULLUP);
  delayMicroseconds(500);
  int pullOn = digitalRead(10);
  pi.listen();
  if (pullOn && pullOff) {
    Serial.println(F("HIGH (driven high, or no wire)"));
  } else if (pullOn) {
    Serial.println(F("weak LOW (a Pi pin nobody drives, or no wire)"));
  } else if (!pullOff) {
    Serial.println(F("LOW (wire on a GND pin, or the Pi pin driven low)"));
  } else {
    Serial.println(F("unstable (loose wire?)"));
  }
}

void loop() {
  while (pi.available()) {
    Serial.write(pi.read());
    bytes++;
    lastByte = millis();
  }
  unsigned long now = millis();
  if (now - lastByte >= 10000 && now - lastReport >= 10000) {
    lastReport = now;
    Serial.print(F("\r\n[bridge] nothing new for 10 s, "));
    Serial.print(bytes);
    Serial.print(F(" bytes so far, pin 10: "));
    reportLevel();
  }
}
