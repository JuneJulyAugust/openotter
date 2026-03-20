#include <Servo.h>

static const int SERVO_PIN = 4;
static const int ANGLE_MIN = 50;
static const int ANGLE_MAX = 130;
static const int STEP_DELAY_MS = 10;

Servo myServo;

void setup() {
  Serial.begin(115200);
  myServo.attach(SERVO_PIN);
  Serial.println("Servo sweep started.");
}

void loop() {
  for (int pos = ANGLE_MIN; pos <= ANGLE_MAX; pos++) {
    myServo.write(pos);
    delay(STEP_DELAY_MS);
  }
  for (int pos = ANGLE_MAX; pos >= ANGLE_MIN; pos--) {
    myServo.write(pos);
    delay(STEP_DELAY_MS);
  }
}
