/* SPDX-License-Identifier: BSD-3-Clause */
#include "ble_actuator_policy.h"

BleActuatorCommand_t BLE_ActuatorPolicy_ApplyWatchdog(
    BleActuatorCommand_t desired,
    int16_t neutral_us,
    int watchdog_trip) {
  if (!watchdog_trip) {
    return desired;
  }

  BleActuatorCommand_t neutral = {
      .steering_us = neutral_us,
      .throttle_us = neutral_us,
  };
  return neutral;
}
