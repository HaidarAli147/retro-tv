// Final controller sketch: decodes IR remote button presses and sends
// the same command strings the Pi bridge already expects (LEFT/RIGHT/
// UP/DOWN/ENTER/VOL_UP/VOL_DOWN), so rpi_bridge.py needs no changes.
//
// Fill in the hex codes below using ir_dump.ino first.

#include <IRremote.hpp>

const int IR_RECEIVE_PIN = 3;

#define IR_UP     0x00000000  // fill in from ir_dump.ino
#define IR_DOWN   0x00000000
#define IR_LEFT   0x00000000
#define IR_RIGHT  0x00000000
#define IR_OK     0x00000000
#define IR_VOLUP  0x00000000
#define IR_VOLDN  0x00000000

uint32_t lastCode = 0;

void sendCommand(uint32_t code) {
  switch (code) {
    case IR_UP:    Serial.println("UP");       break;
    case IR_DOWN:  Serial.println("DOWN");     break;
    case IR_LEFT:  Serial.println("LEFT");     break;
    case IR_RIGHT: Serial.println("RIGHT");    break;
    case IR_OK:    Serial.println("ENTER");    break;
    case IR_VOLUP: Serial.println("VOL_UP");   break;
    case IR_VOLDN: Serial.println("VOL_DOWN"); break;
    default: break; // unmapped button, ignore
  }
}

void setup() {
  Serial.begin(9600);
  IrReceiver.begin(IR_RECEIVE_PIN);
}

void loop() {
  if (IrReceiver.decode()) {
    uint32_t code = IrReceiver.decodedIRData.decodedRawData;

    if (code == 0xFFFFFFFF) {
      // NEC repeat signal (button held down) - reuse the last real code
      sendCommand(lastCode);
    } else if (code != 0) {
      lastCode = code;
      sendCommand(code);
    }

    IrReceiver.resume();
  }
}
