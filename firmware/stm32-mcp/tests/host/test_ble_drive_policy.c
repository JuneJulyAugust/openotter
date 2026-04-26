/* SPDX-License-Identifier: BSD-3-Clause */
#include "ble_drive_policy.h"
#include "ble_tof_policy.h"

#include <assert.h>

static void test_drive_blocks_throttle_until_safety_config_ready(void)
{
  assert(!BLE_DrivePolicy_ThrottleAllowed(BLE_TOF_MODE_DRIVE, 0));
  assert(BLE_DrivePolicy_ThrottleAllowed(BLE_TOF_MODE_DRIVE, 1));
}

static void test_non_drive_modes_do_not_depend_on_safety_config(void)
{
  assert(BLE_DrivePolicy_ThrottleAllowed(BLE_TOF_MODE_DEBUG, 0));
  assert(BLE_DrivePolicy_ThrottleAllowed(BLE_TOF_MODE_PARK, 0));
}

int main(void)
{
  test_drive_blocks_throttle_until_safety_config_ready();
  test_non_drive_modes_do_not_depend_on_safety_config();
  return 0;
}
