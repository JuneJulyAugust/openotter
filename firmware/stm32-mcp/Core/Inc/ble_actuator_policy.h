/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef BLE_ACTUATOR_POLICY_H
#define BLE_ACTUATOR_POLICY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  int16_t steering_us;
  int16_t throttle_us;
} BleActuatorCommand_t;

BleActuatorCommand_t BLE_ActuatorPolicy_ApplyWatchdog(
    BleActuatorCommand_t desired,
    int16_t neutral_us,
    int watchdog_trip);

#ifdef __cplusplus
}
#endif

#endif /* BLE_ACTUATOR_POLICY_H */
