#include <Servo.h>

// ---------------------------------------------------------------------------
// Pin & timing configuration
// ---------------------------------------------------------------------------
static const int ESC_PIN = 8;
static const unsigned long ARM_DELAY_MS = 3000;
static const int RAMP_STEP_DELAY_MS = 50;
static const int PAUSE_MS = 1000;
static const int HOLD_MS = 2000;

// ---------------------------------------------------------------------------
// Throttle mapping
//   Servo.write() range: 0..180  ->  PWM 1000..2000us
//   ESC neutral = 90 (1500us)
//   Forward:  91..180   Reverse: 89..0
//   40% forward max = 90 + 0.4*90 = 126
//   40% reverse max = 90 - 0.4*90 = 54
// ---------------------------------------------------------------------------
static const int NEUTRAL = 90;
static const int FWD_MAX = 126;  // 40% forward
static const int REV_MAX = 54;   // 40% reverse

// Percentage-to-throttle helpers (10% steps = 9 servo units per 10%)
static int fwdPct(int pct) { return NEUTRAL + (int)((long)pct * 90 / 100); }
static int revPct(int pct) { return NEUTRAL - (int)((long)pct * 90 / 100); }

// ---------------------------------------------------------------------------
// Low-level helpers
// ---------------------------------------------------------------------------
Servo esc;

void arm() {
  Serial.println("Arming ESC — ensure battery is connected...");
  esc.attach(ESC_PIN);
  esc.write(NEUTRAL);
  delay(ARM_DELAY_MS);
  Serial.println("ESC armed.");
}

void rampTo(int target) {
  int current = esc.read();
  int step = (target > current) ? 1 : -1;

  Serial.print("  ramp ");
  Serial.print(current);
  Serial.print(" -> ");
  Serial.println(target);

  while (current != target) {
    current += step;
    esc.write(current);
    delay(RAMP_STEP_DELAY_MS);
  }
}

void idle() {
  rampTo(NEUTRAL);
}

void pause() {
  delay(PAUSE_MS);
}

// ---------------------------------------------------------------------------
// Demo building blocks
// ---------------------------------------------------------------------------

void demoForward(int pct) {
  int throttle = constrain(fwdPct(pct), NEUTRAL + 1, FWD_MAX);
  Serial.print("[FWD ");
  Serial.print(pct);
  Serial.print("%] throttle=");
  Serial.println(throttle);
  rampTo(throttle);
  delay(HOLD_MS);
}

void demoReverse(int pct) {
  int throttle = constrain(revPct(pct), REV_MAX, NEUTRAL - 1);
  Serial.print("[REV ");
  Serial.print(pct);
  Serial.print("%] throttle=");
  Serial.println(throttle);
  rampTo(throttle);
  delay(HOLD_MS);
}

void demoBrake() {
  Serial.println("[BRAKE]");
  idle();
  pause();
}

// ---------------------------------------------------------------------------
// Setup & main loop
// ---------------------------------------------------------------------------

void setup() {
  Serial.begin(115200);
  Serial.println("=== Brushless Motor Demo (max 40%) ===");
  arm();
}

void loop() {
  Serial.println("\n-- Forward 10% -> 40% --");
  demoForward(10); demoBrake();
  demoForward(20); demoBrake();
  demoForward(30); demoBrake();
  demoForward(40); demoBrake();

  Serial.println("\n-- Reverse 10% -> 40% --");
  demoReverse(10); demoBrake();
  demoReverse(20); demoBrake();
  demoReverse(30); demoBrake();
  demoReverse(40); demoBrake();

  Serial.println("\n=== Cycle complete. Restarting in 5s... ===");
  delay(5000);
}
