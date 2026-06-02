/* SPDX-License-Identifier: BSD-3-Clause */
#include "ble_tof_policy.h"
#include "tof_types.h"

#include <assert.h>
#include <stdint.h>

static void test_debug_allows_only_l8_config(void)
{
  assert(BLE_Tof_ConfigWriteAllowed(BLE_TOF_MODE_DEBUG,
                                    TOF_SENSOR_VL53L8CX));
  assert(!BLE_Tof_ConfigWriteAllowed(BLE_TOF_MODE_DEBUG,
                                     TOF_SENSOR_VL53L1CB));
  assert(!BLE_Tof_ConfigWriteAllowed(BLE_TOF_MODE_DEBUG,
                                     TOF_SENSOR_NONE));
}

static void test_drive_and_park_lock_external_config(void)
{
  assert(!BLE_Tof_ConfigWriteAllowed(BLE_TOF_MODE_DRIVE,
                                     TOF_SENSOR_VL53L1CB));
  assert(!BLE_Tof_ConfigWriteAllowed(BLE_TOF_MODE_PARK,
                                     TOF_SENSOR_VL53L1CB));
  assert(!BLE_Tof_ConfigWriteAllowed(BLE_TOF_MODE_DRIVE,
                                     TOF_SENSOR_VL53L8CX));
  assert(!BLE_Tof_ConfigWriteAllowed(BLE_TOF_MODE_PARK,
                                     TOF_SENSOR_VL53L8CX));
}

static void test_frame_streams_only_in_debug(void)
{
  assert(BLE_Tof_FrameStreamAllowed(BLE_TOF_MODE_DEBUG));
  assert(!BLE_Tof_FrameStreamAllowed(BLE_TOF_MODE_DRIVE));
  assert(!BLE_Tof_FrameStreamAllowed(BLE_TOF_MODE_PARK));
}

static void expect_status_decision(int rc, uint8_t state, uint8_t last_error)
{
  BLE_TofStatusDecision_t decision = BLE_Tof_StatusForResult(rc);

  assert(decision.state == state);
  assert(decision.last_error == last_error);
}

static void test_status_ok_clears_error_and_reports_running(void)
{
  expect_status_decision(TOF_STATUS_OK, BLE_TOF_STATE_RUNNING, 0u);
}

static void test_hardware_health_failures_report_error_state(void)
{
  expect_status_decision(TOF_STATUS_NO_SENSOR,
                         BLE_TOF_STATE_ERROR,
                         TOF_STATUS_NO_SENSOR);
  expect_status_decision(TOF_STATUS_BOOT_FAILED,
                         BLE_TOF_STATE_ERROR,
                         TOF_STATUS_BOOT_FAILED);
  expect_status_decision(TOF_STATUS_IO,
                         BLE_TOF_STATE_ERROR,
                         TOF_STATUS_IO);
  expect_status_decision(TOF_STATUS_DRIVER_MISSING,
                         BLE_TOF_STATE_ERROR,
                         TOF_STATUS_DRIVER_MISSING);
  expect_status_decision(TOF_STATUS_DRIVER_DEAD,
                         BLE_TOF_STATE_ERROR,
                         TOF_STATUS_DRIVER_DEAD);
}

static void test_policy_and_config_failures_keep_running_state(void)
{
  expect_status_decision(TOF_STATUS_BAD_CONFIG,
                         BLE_TOF_STATE_RUNNING,
                         TOF_STATUS_BAD_CONFIG);
  expect_status_decision(TOF_STATUS_LOCKED_IN_DRIVE,
                         BLE_TOF_STATE_RUNNING,
                         TOF_STATUS_LOCKED_IN_DRIVE);
}

int main(void)
{
  test_debug_allows_only_l8_config();
  test_drive_and_park_lock_external_config();
  test_frame_streams_only_in_debug();
  test_status_ok_clears_error_and_reports_running();
  test_hardware_health_failures_report_error_state();
  test_policy_and_config_failures_keep_running_state();
  return 0;
}
