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

#define BLE_TOF_STATE_IDLE    0u
#define BLE_TOF_STATE_RUNNING 1u
#define BLE_TOF_STATE_ERROR   2u

typedef struct {
  uint8_t state;
  uint8_t last_error;
} BLE_TofStatusDecision_t;

int BLE_Tof_ConfigWriteAllowed(uint8_t mode, uint8_t sensor_type);
int BLE_Tof_FrameStreamAllowed(uint8_t mode);
int BLE_Tof_ResultIsHealthFailure(int rc);
BLE_TofStatusDecision_t BLE_Tof_StatusForResult(int rc);

#ifdef __cplusplus
}
#endif

#endif /* BLE_TOF_POLICY_H */
