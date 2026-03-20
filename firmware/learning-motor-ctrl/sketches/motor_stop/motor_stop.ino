#include <Servo.h>

static const int ESC_PIN = 8;
static const int THROTTLE_NEUTRAL = 90;

Servo esc;

void setup() {
  Serial.begin(115200);
  Serial.println("Stopping motor...");

  esc.attach(ESC_PIN);
  esc.write(THROTTLE_NEUTRAL);
  delay(1000);
  esc.detach();

  Serial.println("ESC set to neutral and signal detached.");
}

void loop() {
}
