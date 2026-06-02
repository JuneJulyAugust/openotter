/* SPDX-License-Identifier: BSD-3-Clause */
#include "ble_tof_policy.h"

#include "tof_types.h"

int BLE_Tof_ConfigWriteAllowed(uint8_t mode, uint8_t sensor_type)
{
  /* External FE61 writes are bench-debug only. Drive safety config is applied
   * internally through BLE_Tof_EnforceSafetyConfig(), not through this gate. */
  return mode == BLE_TOF_MODE_DEBUG && sensor_type == TOF_SENSOR_VL53L8CX;
}

int BLE_Tof_FrameStreamAllowed(uint8_t mode)
{
  return mode == BLE_TOF_MODE_DEBUG;
}

int BLE_Tof_ResultIsHealthFailure(int rc)
{
  return rc == TOF_STATUS_NO_SENSOR ||
         rc == TOF_STATUS_BOOT_FAILED ||
         rc == TOF_STATUS_IO ||
         rc == TOF_STATUS_DRIVER_MISSING ||
         rc == TOF_STATUS_DRIVER_DEAD;
}

BLE_TofStatusDecision_t BLE_Tof_StatusForResult(int rc)
{
  BLE_TofStatusDecision_t decision = {
      .state = BLE_TOF_STATE_RUNNING,
      .last_error = 0,
  };

  if (rc == TOF_STATUS_OK) return decision;

  decision.last_error = (uint8_t)rc;
  if (BLE_Tof_ResultIsHealthFailure(rc)) {
    decision.state = BLE_TOF_STATE_ERROR;
  }
  return decision;
}
