// Diagnostic sketch: prints raw sensor values only, no logic/thresholds.
// Use this to see what the hardware is actually reporting.

const int JOYSTICK_X_PIN = A0;
const int JOYSTICK_Y_PIN = A1;
const int VOLUME_PIN     = A2;
const int ENTER_BTN_PIN  = 2;

void setup() {
  Serial.begin(9600);
  pinMode(ENTER_BTN_PIN, INPUT_PULLUP);
}

void loop() {
  int x = analogRead(JOYSTICK_X_PIN);
  int y = analogRead(JOYSTICK_Y_PIN);
  int v = analogRead(VOLUME_PIN);
  int btn = digitalRead(ENTER_BTN_PIN);

  Serial.print("X="); Serial.print(x);
  Serial.print(" Y="); Serial.print(y);
  Serial.print(" VOL="); Serial.print(v);
  Serial.print(" BTN="); Serial.println(btn == LOW ? "PRESSED" : "released");

  delay(200);
}
