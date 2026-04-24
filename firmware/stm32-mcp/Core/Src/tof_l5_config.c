/* SPDX-License-Identifier: BSD-3-Clause */
#include "tof_l5.h"

static uint8_t max_freq_for_layout(uint8_t layout)
{
  switch (layout) {
    case 4: return TOF_L5_MAX_FREQ_4X4_HZ;
    case 8: return TOF_L5_MAX_FREQ_8X8_HZ;
    default: return 0;
  }
}

int TofL5_ValidateConfig(const Tof_Config_t *cfg)
{
  if (cfg == 0) return TOF_STATUS_BAD_CONFIG;
  if (cfg->sensor_type != TOF_SENSOR_VL53L5CX) return TOF_STATUS_BAD_CONFIG;
  if (cfg->profile != TOF_PROFILE_L5_CONTINUOUS) return TOF_STATUS_BAD_CONFIG;

  uint8_t max_freq = max_freq_for_layout(cfg->layout);
  if (max_freq == 0) return TOF_STATUS_BAD_CONFIG;
  if (cfg->frequency_hz == 0 || cfg->frequency_hz > max_freq) {
    return TOF_STATUS_BAD_CONFIG;
  }

  if (cfg->integration_ms > 0) {
    if (cfg->integration_ms < 2u || cfg->integration_ms > 1000u) {
      return TOF_STATUS_BAD_CONFIG;
    }
    uint32_t period_ms = 1000u / cfg->frequency_hz;
    if (period_ms == 0 || cfg->integration_ms > period_ms) {
      return TOF_STATUS_BAD_CONFIG;
    }
  }

  return TOF_STATUS_OK;
}
