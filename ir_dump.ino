// Diagnostic version: prints full decode detail (protocol, address,
// command), not just raw hex, so we can see WHY it's reading 0x0.

#include <IRremote.hpp>

const int IR_RECEIVE_PIN = 3;

void setup() {
  Serial.begin(9600);
  IrReceiver.begin(IR_RECEIVE_PIN);
  Serial.println("IR receiver ready. Press buttons on the remote.");
}

void loop() {
  if (IrReceiver.decode()) {
    IrReceiver.printIRResultShort(&Serial);
    IrReceiver.resume();
  }
}
