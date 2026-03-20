#include <Servo.h>

// ---------------------------------------------------------------------------
// Pin assignments
// ---------------------------------------------------------------------------
static const int ESC_PIN = 8;    // brushless motor via ESC
static const int STEER_PIN = 4;  // steering servo (front wheel angle)

// ---------------------------------------------------------------------------
// Timing
// ---------------------------------------------------------------------------
static const unsigned long ARM_DELAY_MS = 3000;
static const int RAMP_STEP_DELAY_MS = 50;
static const int STEER_STEP_DELAY_MS = 10;
static const int PAUSE_MS = 1000;
static const int HOLD_MS = 2000;

// ---------------------------------------------------------------------------
// Motor throttle mapping (max 40%)
//   neutral = 90, forward 91..126, reverse 89..54
// ---------------------------------------------------------------------------
static const int THROTTLE_NEUTRAL = 90;
static const int FWD_MAX = 126;
static const int REV_MAX = 54;

static int fwdPct(int pct) { return THROTTLE_NEUTRAL + (int)((long)pct * 90 / 100); }
static int revPct(int pct) { return THROTTLE_NEUTRAL - (int)((long)pct * 90 / 100); }

// ---------------------------------------------------------------------------
// Steering range
//   neutral = 90, left = 50, right = 130
// ---------------------------------------------------------------------------
static const int STEER_NEUTRAL = 90;
static const int STEER_LEFT = 50;
static const int STEER_RIGHT = 130;

// ---------------------------------------------------------------------------
// Hardware objects
// ---------------------------------------------------------------------------
Servo esc;
Servo steering;

// ---------------------------------------------------------------------------
// Motor helpers
// ---------------------------------------------------------------------------

void motorArm() {
  Serial.println("Arming ESC...");
  esc.attach(ESC_PIN);
  esc.write(THROTTLE_NEUTRAL);
  delay(ARM_DELAY_MS);
  Serial.println("ESC armed.");
}

void motorRampTo(int target) {
  int current = esc.read();
  int step = (target > current) ? 1 : -1;

  Serial.print("  motor ");
  Serial.print(current);
  Serial.print(" -> ");
  Serial.println(target);

  while (current != target) {
    current += step;
    esc.write(current);
    delay(RAMP_STEP_DELAY_MS);
  }
}

void motorIdle() {
  motorRampTo(THROTTLE_NEUTRAL);
}

void motorForward(int pct) {
  int throttle = constrain(fwdPct(pct), THROTTLE_NEUTRAL + 1, FWD_MAX);
  Serial.print("[FWD ");
  Serial.print(pct);
  Serial.println("%]");
  motorRampTo(throttle);
}

void motorReverse(int pct) {
  int throttle = constrain(revPct(pct), REV_MAX, THROTTLE_NEUTRAL - 1);
  Serial.print("[REV ");
  Serial.print(pct);
  Serial.println("%]");
  motorRampTo(throttle);
}

// ---------------------------------------------------------------------------
// Steering helpers
// ---------------------------------------------------------------------------

void steerTo(int angle) {
  int current = steering.read();
  int step = (angle > current) ? 1 : -1;

  Serial.print("  steer ");
  Serial.print(current);
  Serial.print(" -> ");
  Serial.println(angle);

  while (current != angle) {
    current += step;
    steering.write(current);
    delay(STEER_STEP_DELAY_MS);
  }
}

void steerCenter()  { steerTo(STEER_NEUTRAL); }
void steerLeft()    { steerTo(STEER_LEFT); }
void steerRight()   { steerTo(STEER_RIGHT); }

// ---------------------------------------------------------------------------
// Combined helpers
// ---------------------------------------------------------------------------

void hold(unsigned long ms) { delay(ms); }

void pause() {
  motorIdle();
  steerCenter();
  delay(PAUSE_MS);
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

void setup() {
  Serial.begin(115200);
  Serial.println("=== Combined Motor + Steering Demo ===");

  steering.attach(STEER_PIN);
  steerCenter();
  motorArm();
}

// ---------------------------------------------------------------------------
// Demo routine
// ---------------------------------------------------------------------------

void loop() {
  // --- Straight line, increasing speed ---
  Serial.println("\n-- Straight forward 10%-40% --");
  steerCenter();
  motorForward(10); hold(HOLD_MS); motorIdle(); delay(PAUSE_MS);
  motorForward(20); hold(HOLD_MS); motorIdle(); delay(PAUSE_MS);
  motorForward(30); hold(HOLD_MS); motorIdle(); delay(PAUSE_MS);
  motorForward(40); hold(HOLD_MS);
  pause();

  // --- Straight reverse, increasing speed ---
  Serial.println("\n-- Straight reverse 10%-40% --");
  steerCenter();
  motorReverse(10); hold(HOLD_MS); motorIdle(); delay(PAUSE_MS);
  motorReverse(20); hold(HOLD_MS); motorIdle(); delay(PAUSE_MS);
  motorReverse(30); hold(HOLD_MS); motorIdle(); delay(PAUSE_MS);
  motorReverse(40); hold(HOLD_MS);
  pause();

  // --- Left turn at 20% ---
  Serial.println("\n-- Left turn forward 20% --");
  steerLeft();
  motorForward(20); hold(HOLD_MS);
  pause();

  // --- Right turn at 20% ---
  Serial.println("\n-- Right turn forward 20% --");
  steerRight();
  motorForward(20); hold(HOLD_MS);
  pause();

  // --- Slalom: alternate left/right while driving ---
  Serial.println("\n-- Slalom at 15% --");
  motorForward(15);
  steerLeft();  hold(HOLD_MS);
  steerRight(); hold(HOLD_MS);
  steerLeft();  hold(HOLD_MS);
  steerRight(); hold(HOLD_MS);
  pause();

  // --- Reverse with steering ---
  Serial.println("\n-- Reverse left turn 15% --");
  steerLeft();
  motorReverse(15); hold(HOLD_MS);
  pause();

  Serial.println("\n-- Reverse right turn 15% --");
  steerRight();
  motorReverse(15); hold(HOLD_MS);
  pause();

  Serial.println("\n=== Cycle complete. Restarting in 5s... ===");
  delay(5000);
}
