/* SPDX-License-Identifier: BSD-3-Clause */
#include "ble_drive_policy.h"

#include "ble_tof_policy.h"

int BLE_DrivePolicy_ThrottleAllowed(uint8_t mode, int safety_config_ready)
{
  if (mode != BLE_TOF_MODE_DRIVE) return 1;
  return safety_config_ready ? 1 : 0;
}
