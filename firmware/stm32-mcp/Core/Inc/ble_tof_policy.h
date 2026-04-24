/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef BLE_TOF_POLICY_H
#define BLE_TOF_POLICY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BLE_TOF_MODE_DRIVE 0u
#define BLE_TOF_MODE_DEBUG 1u
#define BLE_TOF_MODE_PARK  2u

int BLE_Tof_ConfigWriteAllowed(uint8_t mode, uint8_t sensor_type);

#ifdef __cplusplus
}
#endif

#endif /* BLE_TOF_POLICY_H */
