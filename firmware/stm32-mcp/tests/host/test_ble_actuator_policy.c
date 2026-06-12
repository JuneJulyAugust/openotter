/* SPDX-License-Identifier: BSD-3-Clause */
#include "ble_actuator_policy.h"

#include <assert.h>

static void test_watchdog_trip_neutralizes_steering_and_throttle(void) {
  BleActuatorCommand_t desired = {
      .steering_us = 2000,
      .throttle_us = 1700,
  };

  BleActuatorCommand_t out =
      BLE_ActuatorPolicy_ApplyWatchdog(desired, 1500, 1);

  assert(out.steering_us == 1500);
  assert(out.throttle_us == 1500);
}

static void test_no_watchdog_preserves_desired_command(void) {
  BleActuatorCommand_t desired = {
      .steering_us = 1000,
      .throttle_us = 1600,
  };

  BleActuatorCommand_t out =
      BLE_ActuatorPolicy_ApplyWatchdog(desired, 1500, 0);

  assert(out.steering_us == 1000);
  assert(out.throttle_us == 1600);
}

int main(void) {
  test_watchdog_trip_neutralizes_steering_and_throttle();
  test_no_watchdog_preserves_desired_command();
  return 0;
}
