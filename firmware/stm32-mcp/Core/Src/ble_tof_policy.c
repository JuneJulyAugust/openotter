/* SPDX-License-Identifier: BSD-3-Clause */
#include "ble_tof_policy.h"

#include "tof_types.h"

int BLE_Tof_ConfigWriteAllowed(uint8_t mode, uint8_t sensor_type)
{
  (void)sensor_type;
  return mode == BLE_TOF_MODE_DEBUG;
}

int BLE_Tof_FrameStreamAllowed(uint8_t mode)
{
  return mode == BLE_TOF_MODE_DEBUG;
}
