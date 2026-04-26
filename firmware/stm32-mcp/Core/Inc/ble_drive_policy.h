/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef BLE_DRIVE_POLICY_H
#define BLE_DRIVE_POLICY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int BLE_DrivePolicy_ThrottleAllowed(uint8_t mode, int safety_config_ready);

#ifdef __cplusplus
}
#endif

#endif /* BLE_DRIVE_POLICY_H */
