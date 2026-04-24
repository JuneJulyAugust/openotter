/* SPDX-License-Identifier: BSD-3-Clause */
#include "tof_l5.h"

#include <assert.h>
#include <stdint.h>

static void test_accepts_4x4_and_8x8_configs(void)
{
  Tof_Config_t cfg = {
      .sensor_type = TOF_SENSOR_VL53L5CX,
      .layout = 4,
      .profile = TOF_PROFILE_L5_CONTINUOUS,
      .frequency_hz = 15,
      .integration_ms = 20,
      .budget_ms = 0,
  };
  assert(TofL5_ValidateConfig(&cfg) == TOF_STATUS_OK);

  cfg.layout = 8;
  cfg.frequency_hz = 10;
  assert(TofL5_ValidateConfig(&cfg) == TOF_STATUS_OK);
}

static void test_rejects_bad_layout_sensor_and_rate(void)
{
  Tof_Config_t cfg = {
      .sensor_type = TOF_SENSOR_VL53L5CX,
      .layout = 3,
      .profile = TOF_PROFILE_L5_CONTINUOUS,
      .frequency_hz = 10,
      .integration_ms = 20,
      .budget_ms = 0,
  };
  assert(TofL5_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);

  cfg.layout = 8;
  cfg.sensor_type = TOF_SENSOR_VL53L1CB;
  assert(TofL5_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);

  cfg.sensor_type = TOF_SENSOR_VL53L5CX;
  cfg.frequency_hz = 0;
  assert(TofL5_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);

  cfg.frequency_hz = 61;
  assert(TofL5_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);

  cfg.frequency_hz = 10;
  cfg.integration_ms = 1;
  assert(TofL5_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);
}

static void test_rejects_timing_that_cannot_fit_rate(void)
{
  Tof_Config_t cfg = {
      .sensor_type = TOF_SENSOR_VL53L5CX,
      .layout = 8,
      .profile = TOF_PROFILE_L5_CONTINUOUS,
      .frequency_hz = 60,
      .integration_ms = 20,
      .budget_ms = 0,
  };
  assert(TofL5_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);

  cfg.frequency_hz = 10;
  assert(TofL5_ValidateConfig(&cfg) == TOF_STATUS_OK);
}

int main(void)
{
  test_accepts_4x4_and_8x8_configs();
  test_rejects_bad_layout_sensor_and_rate();
  test_rejects_timing_that_cannot_fit_rate();
  return 0;
}
