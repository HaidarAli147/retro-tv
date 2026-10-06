// Tests ONLY the joystick's press button. Nothing else.
// Open Serial Monitor at 9600 baud and press the stick in.
// It prints only when the pin changes, so a quiet screen means the
// button is not reaching D2 at all.

const int SW_PIN = 2;

void setup() {
  Serial.begin(9600);
  pinMode(SW_PIN, INPUT_PULLUP);
  Serial.println("Ready. Press the joystick button.");
  Serial.print("Resting state: ");
  Serial.println(digitalRead(SW_PIN) == LOW ? "LOW (stuck pressed?)" : "HIGH (correct)");
}

void loop() {
  static int last = -1;
  static unsigned long pressedAt = 0;

  int v = digitalRead(SW_PIN);
  if (v != last) {
    if (v == LOW) {
      pressedAt = millis();
      Serial.println("PRESSED");
    } else {
      Serial.print("released after ");
      Serial.print(millis() - pressedAt);
      Serial.println(" ms");
    }
    last = v;
  }
  delay(20);
}
