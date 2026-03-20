#include <Servo.h>

static const int ESC_PIN = 8;
static const int STEER_PIN = 4;

Servo esc;
Servo steering;

void setup() {
  Serial.begin(115200);
  Serial.println("Stopping motor and centering steering...");

  esc.attach(ESC_PIN);
  esc.write(90);
  steering.attach(STEER_PIN);
  steering.write(90);
  delay(1000);

  esc.detach();
  steering.detach();

  Serial.println("Motor neutral, steering centered, signals detached.");
}

void loop() {
}
