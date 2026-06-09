/* SPDX-License-Identifier: BSD-3-Clause */
#include "tof_l8.h"

#include <assert.h>
#include <stdint.h>

static void test_accepts_4x4_and_8x8_configs(void)
{
  Tof_Config_t cfg = {
      .sensor_type = TOF_SENSOR_VL53L8CX,
      .layout = 4,
      .profile = TOF_PROFILE_L8_CONTINUOUS,
      .frequency_hz = 15,
      .integration_ms = 20,
      .budget_ms = 0,
  };
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_OK);

  cfg.layout = 8;
  cfg.frequency_hz = 10;
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_OK);

  cfg.layout = 4;
  cfg.frequency_hz = TOF_L8_MAX_FREQ_4X4_HZ;
  cfg.integration_ms = 10;
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_OK);

  cfg.layout = 8;
  cfg.frequency_hz = TOF_L8_MAX_FREQ_8X8_HZ;
  cfg.integration_ms = 20;
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_OK);

  cfg.integration_ms = 0;
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_OK);
}

static void test_accepts_reverse_safety_config(void)
{
  Tof_Config_t cfg = {
      .sensor_type = TOF_SENSOR_VL53L8CX,
      .layout = 4,
      .profile = TOF_PROFILE_L8_CONTINUOUS,
      .frequency_hz = 30,
      .integration_ms = 20,
      .budget_ms = 0,
  };
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_OK);
}

static void test_rejects_bad_layout_sensor_and_rate(void)
{
  assert(TofL8_ValidateConfig(0) == TOF_STATUS_BAD_CONFIG);

  Tof_Config_t cfg = {
      .sensor_type = TOF_SENSOR_VL53L8CX,
      .layout = 3,
      .profile = TOF_PROFILE_L8_CONTINUOUS,
      .frequency_hz = 10,
      .integration_ms = 20,
      .budget_ms = 0,
  };
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);

  cfg.layout = 8;
  cfg.sensor_type = TOF_SENSOR_VL53L1CB;
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);

  cfg.sensor_type = TOF_SENSOR_VL53L8CX;
  cfg.profile = 0;
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);

  cfg.profile = TOF_PROFILE_L8_CONTINUOUS;
  cfg.frequency_hz = 0;
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);

  cfg.layout = 4;
  cfg.frequency_hz = 61;
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);

  cfg.layout = 8;
  cfg.frequency_hz = 16;
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);

  cfg.frequency_hz = 10;
  cfg.integration_ms = 1;
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);

  cfg.integration_ms = 1001;
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);
}

static void test_rejects_timing_that_cannot_fit_rate(void)
{
  Tof_Config_t cfg = {
      .sensor_type = TOF_SENSOR_VL53L8CX,
      .layout = 8,
      .profile = TOF_PROFILE_L8_CONTINUOUS,
      .frequency_hz = 60,
      .integration_ms = 20,
      .budget_ms = 0,
  };
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);

  cfg.frequency_hz = 10;
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_OK);

  cfg.layout = 4;
  cfg.frequency_hz = 60;
  cfg.integration_ms = 11;
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_OK);

  cfg.integration_ms = 12;
  assert(TofL8_ValidateConfig(&cfg) == TOF_STATUS_BAD_CONFIG);
}

int main(void)
{
  test_accepts_4x4_and_8x8_configs();
  test_accepts_reverse_safety_config();
  test_rejects_bad_layout_sensor_and_rate();
  test_rejects_timing_that_cannot_fit_rate();
  return 0;
}
