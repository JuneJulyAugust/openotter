#include <Servo.h>

static const int SERVO_PIN = 4;
static const int NEUTRAL_ANGLE = 90;

Servo myServo;

void setup() {
  Serial.begin(115200);
  Serial.println("Centering servo...");

  myServo.attach(SERVO_PIN);
  myServo.write(NEUTRAL_ANGLE);
  delay(1000);
  myServo.detach();

  Serial.print("Servo centered at ");
  Serial.print(NEUTRAL_ANGLE);
  Serial.println(" degrees and detached.");
}

void loop() {
}
