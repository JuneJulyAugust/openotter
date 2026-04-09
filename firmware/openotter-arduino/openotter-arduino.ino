#include <Servo.h>

/**
 * OpenOtter Arduino Control Module
 *
 * Protocols:
 *   Input: "S:float,M:float\n"
 *          S (steering): -1.0 (left) to 1.0 (right), 0.0 (center)
 *          M (motor): -1.0 (rev) to 1.0 (fwd), 0.0 (neutral)
 *   Output: Serial feedback on command receipt and state
 */

// --- Pin assignments ---
static const int ESC_PIN = 8;
static const int STEER_PIN = 4;

// --- Ranges and Constants ---
static const int STEER_NEUTRAL = 90;
static const int STEER_LEFT = 50;
static const int STEER_RIGHT = 130;

static const int MOTOR_NEUTRAL = 90;
static const int MOTOR_FWD_MAX = 126; // 40% cap as per demo
static const int MOTOR_REV_MAX = 54;

static const unsigned long ARM_DELAY_MS = 3000;
static const unsigned long HEARTBEAT_TIMEOUT_MS = 2000; // Neutralize if no command for 2s

// --- Hardware ---
Servo esc;
Servo steering;

// --- State ---
unsigned long last_cmd_time = 0;
bool armed = false;

void setup() {
  Serial.begin(115200);

  steering.attach(STEER_PIN);
  steering.write(STEER_NEUTRAL);

  armESC();

  Serial.println("INFO: Arduino ready");
  last_cmd_time = millis();
}

void armESC() {
  Serial.println("INFO: Arming ESC...");
  esc.attach(ESC_PIN);
  esc.write(MOTOR_NEUTRAL);
  delay(ARM_DELAY_MS);
  armed = true;
  Serial.println("INFO: ESC armed");
}

void loop() {
  if (Serial.available() > 0) {
    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line.length() > 0) {
      processCommand(line);
    }
  }

  // Safety timeout (Neutralization disabled per user request for debugging)
  if (armed && (millis() - last_cmd_time > HEARTBEAT_TIMEOUT_MS)) {
    // neutralize();
    // Periodically log timeout to serial for debugging
    static unsigned long last_log = 0;
    if (millis() - last_log > 1000) {
      Serial.println("WARN: Safety timeout (Neutralization disabled)");
      last_log = millis();
    }
  }
}

void processCommand(String line) {
  // Expected format: S:0.00,M:0.00
  int s_idx = line.indexOf("S:");
  int m_idx = line.indexOf(",M:");

  if (s_idx != -1 && m_idx != -1) {
    String s_str = line.substring(s_idx + 2, m_idx);
    String m_str = line.substring(m_idx + 3);

    float s_val = s_str.toFloat();
    float m_val = m_str.toFloat();

    applyCommands(s_val, m_val);
    last_cmd_time = millis();

    // Ack back for debugging
    Serial.print("ACK: S=");
    Serial.print(s_val);
    Serial.print(" M=");
    Serial.println(m_val);
  } else {
    // Serial.print("ERR: Invalid format: ");
    // Serial.println(line);
  }
}

void applyCommands(float steer, float motor) {
  // Map steering: -1.0 -> 50, 0.0 -> 90, 1.0 -> 130
  int steer_angle;
  if (steer >= 0) {
    steer_angle = STEER_NEUTRAL + (int)(steer * (float)(STEER_RIGHT - STEER_NEUTRAL));
  } else {
    steer_angle = STEER_NEUTRAL + (int)(steer * (float)(STEER_NEUTRAL - STEER_LEFT));
  }
  steer_angle = constrain(steer_angle, STEER_LEFT, STEER_RIGHT);
  steering.write(steer_angle);

  // Map motor: -1.0 -> 54, 0.0 -> 90, 1.0 -> 126
  int motor_val;
  if (motor >= 0) {
    motor_val = MOTOR_NEUTRAL + (int)(motor * (float)(MOTOR_FWD_MAX - MOTOR_NEUTRAL));
  } else {
    motor_val = MOTOR_NEUTRAL + (int)(motor * (float)(MOTOR_NEUTRAL - MOTOR_REV_MAX));
  }
  motor_val = constrain(motor_val, MOTOR_REV_MAX, MOTOR_FWD_MAX);
  esc.write(motor_val);
}

void neutralize() {
  steering.write(STEER_NEUTRAL);
  esc.write(MOTOR_NEUTRAL);
}
