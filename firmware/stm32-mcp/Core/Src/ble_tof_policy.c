/* SPDX-License-Identifier: BSD-3-Clause */
#include "ble_tof_policy.h"

#include "tof_types.h"

int BLE_Tof_ConfigWriteAllowed(uint8_t mode, uint8_t sensor_type)
{
  if (mode == BLE_TOF_MODE_DEBUG) return 1;
  return sensor_type == TOF_SENSOR_VL53L5CX;
}
