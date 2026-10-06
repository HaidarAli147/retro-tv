// =====================================================================
//  Retro-TV controller  -  FINAL
//
//  Joystick  -> navigation, or mouse pointer in mouse mode
//  Knob      -> VOL_UP / VOL_DOWN
//
//  The joystick button does three jobs, so no keyboard is ever needed:
//      quick press    ENTER   (or a mouse click in mouse mode)
//      double press   toggles MOUSE MODE on and off
//      hold ~0.6s     BACK    (escape)
//
//  In mouse mode the stick moves a pointer instead of sending arrow keys,
//  which is what makes web pages like TOD usable. Directions repeat much
//  faster in that mode so the pointer glides rather than crawls.
//
//  Prints plain text lines over serial at 9600 baud. rpi_bridge.py on the
//  Raspberry Pi turns them into key presses and mouse movement.
//
//  The power button is NOT on the Arduino. It wires to the Pi's GPIO3
//  (physical pin 5) and GND - see power_button.py. Never wire that button
//  to both boards: the Arduino pulls its pins to 5V, the Pi's GPIO is 3.3V.
//
//  WIRING
//    Joystick GND -> GND        Joystick +5V -> 5V
//    Joystick VRx -> A0         Joystick VRy -> A1
//    Joystick SW  -> D2
//    Knob outer leg -> 5V   middle (wiper) -> A2   other outer leg -> GND
//  The Uno has one 5V pin, so join the joystick and knob 5V leads into it.
//  It has three GND pins, so give each part its own.
// =====================================================================

const int JOYSTICK_X_PIN  = A0;
const int JOYSTICK_Y_PIN  = A1;
const int JOYSTICK_SW_PIN = 2;
const int VOLUME_PIN      = A2;

// Joystick. Raise JOYSTICK_DEADZONE if a centred stick drifts and sends
// stray directions; lower it if the stick feels unresponsive.
const int JOYSTICK_CENTER   = 512;
const int JOYSTICK_DEADZONE = 200;
const unsigned long NAV_REPEAT_DELAY = 150;  // ms between repeats, menus
const unsigned long MOUSE_REPEAT     = 30;   // ms between repeats, pointer

// Button timing
const unsigned long PRESS_DEBOUNCE = 30;   // ms, ignores contact bounce
const unsigned long BACK_HOLD_MS   = 600;  // ms held before it means BACK
const unsigned long DOUBLE_GAP     = 300;  // ms window to catch a second press

// Volume knob. Averaging plus a commit threshold is what stops the
// phantom VOL_UP/VOL_DOWN chatter a raw analogRead produces.
const int VOL_SAMPLES        = 8;
const int VOL_TRIGGER_DELTA  = 40;
const unsigned long VOL_INTERVAL = 120;

int lastVolCommitted = -1;
unsigned long lastVolTime = 0;
unsigned long lastNavTime = 0;

unsigned long swPressStart    = 0;
unsigned long lastReleaseTime = 0;
bool swWasPressed  = false;
bool backFired     = false;
bool pendingClick  = false;
bool doubleHandled = false;
bool mouseMode     = false;

int readVolumeAveraged() {
  long sum = 0;
  for (int i = 0; i < VOL_SAMPLES; i++) {
    sum += analogRead(VOLUME_PIN);
    delayMicroseconds(200);
  }
  return sum / VOL_SAMPLES;
}

void setup() {
  Serial.begin(9600);
  pinMode(JOYSTICK_SW_PIN, INPUT_PULLUP);
  lastVolCommitted = readVolumeAveraged();
}

void loop() {
  unsigned long now = millis();

  // --- Joystick direction: arrows in menus, pointer in mouse mode ---
  unsigned long navDelay = mouseMode ? MOUSE_REPEAT : NAV_REPEAT_DELAY;
  if (now - lastNavTime > navDelay) {
    int xVal = analogRead(JOYSTICK_X_PIN);
    int yVal = analogRead(JOYSTICK_Y_PIN);

    if (xVal < JOYSTICK_CENTER - JOYSTICK_DEADZONE) {
      Serial.println(mouseMode ? "M_LEFT" : "LEFT");   lastNavTime = now;
    } else if (xVal > JOYSTICK_CENTER + JOYSTICK_DEADZONE) {
      Serial.println(mouseMode ? "M_RIGHT" : "RIGHT"); lastNavTime = now;
    } else if (yVal < JOYSTICK_CENTER - JOYSTICK_DEADZONE) {
      Serial.println(mouseMode ? "M_UP" : "UP");       lastNavTime = now;
    } else if (yVal > JOYSTICK_CENTER + JOYSTICK_DEADZONE) {
      Serial.println(mouseMode ? "M_DOWN" : "DOWN");   lastNavTime = now;
    }
  }

  // --- Button: tap = select, double tap = mouse mode, hold = back ---
  bool pressed = (digitalRead(JOYSTICK_SW_PIN) == LOW);

  if (pressed && !swWasPressed) {                 // pressed just now
    swPressStart = now;
    backFired = false;
    if (pendingClick && (now - lastReleaseTime <= DOUBLE_GAP)) {
      pendingClick  = false;                      // second tap in the window
      doubleHandled = true;
      mouseMode = !mouseMode;
      Serial.println(mouseMode ? "MOUSE_ON" : "MOUSE_OFF");
    }
  } else if (pressed && !backFired && (now - swPressStart >= BACK_HOLD_MS)) {
    Serial.println("BACK");                       // held long enough
    backFired    = true;
    pendingClick = false;
  } else if (!pressed && swWasPressed) {          // released
    if (!backFired && !doubleHandled && (now - swPressStart >= PRESS_DEBOUNCE)) {
      pendingClick    = true;                     // wait, it may be a double
      lastReleaseTime = now;
    }
    doubleHandled = false;
  }

  // a single tap only counts once the double-tap window has passed
  if (pendingClick && (now - lastReleaseTime > DOUBLE_GAP)) {
    Serial.println(mouseMode ? "M_CLICK" : "ENTER");
    pendingClick = false;
  }

  swWasPressed = pressed;

  // --- Volume knob ---
  if (now - lastVolTime >= VOL_INTERVAL) {
    lastVolTime = now;
    int avgVol = readVolumeAveraged();
    int delta  = avgVol - lastVolCommitted;
    if (abs(delta) >= VOL_TRIGGER_DELTA) {
      Serial.println(delta > 0 ? "VOL_UP" : "VOL_DOWN");
      lastVolCommitted = avgVol;
    }
  }
}
