/* SPDX-License-Identifier: BSD-3-Clause */
#include "ble_tof_policy.h"

#include "tof_types.h"

int BLE_Tof_ConfigWriteAllowed(uint8_t mode, uint8_t sensor_type)
{
  /* External FE61 writes are bench-debug only. Drive safety config is applied
   * internally through BLE_Tof_EnforceSafetyConfig(), not through this gate. */
  (void)sensor_type;
  return mode == BLE_TOF_MODE_DEBUG;
}

int BLE_Tof_FrameStreamAllowed(uint8_t mode)
{
  return mode == BLE_TOF_MODE_DEBUG;
}
