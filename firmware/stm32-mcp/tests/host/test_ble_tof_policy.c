/* SPDX-License-Identifier: BSD-3-Clause */
#include "ble_tof_policy.h"
#include "tof_types.h"

#include <assert.h>
#include <stdint.h>

static void test_debug_allows_l1_and_l5_config(void)
{
  assert(BLE_Tof_ConfigWriteAllowed(BLE_TOF_MODE_DEBUG,
                                    TOF_SENSOR_VL53L1CB));
  assert(BLE_Tof_ConfigWriteAllowed(BLE_TOF_MODE_DEBUG,
                                    TOF_SENSOR_VL53L5CX));
}

static void test_drive_and_park_allow_l5_debug_config(void)
{
  assert(BLE_Tof_ConfigWriteAllowed(BLE_TOF_MODE_DRIVE,
                                    TOF_SENSOR_VL53L5CX));
  assert(BLE_Tof_ConfigWriteAllowed(BLE_TOF_MODE_PARK,
                                    TOF_SENSOR_VL53L5CX));
}

static void test_drive_and_park_lock_legacy_l1_config(void)
{
  assert(!BLE_Tof_ConfigWriteAllowed(BLE_TOF_MODE_DRIVE,
                                     TOF_SENSOR_VL53L1CB));
  assert(!BLE_Tof_ConfigWriteAllowed(BLE_TOF_MODE_PARK,
                                     TOF_SENSOR_VL53L1CB));
}

int main(void)
{
  test_debug_allows_l1_and_l5_config();
  test_drive_and_park_allow_l5_debug_config();
  test_drive_and_park_lock_legacy_l1_config();
  return 0;
}
