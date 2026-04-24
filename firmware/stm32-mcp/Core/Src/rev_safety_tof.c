/* SPDX-License-Identifier: BSD-3-Clause */

#include "rev_safety_tof.h"

static int status_is_range_valid(uint8_t status) {
  return status == 0u || status == 3u || status == 6u || status == 11u;
}

static int status_is_no_target(uint8_t status) {
  return status == 14u || status == 255u;
}

RevSafetyTofReading_t RevSafety_ClassifyTofReading(uint16_t range_mm,
                                                   uint8_t status) {
  RevSafetyTofReading_t out = {0};

  if (status_is_range_valid(status) && range_mm > 0u) {
    out.tof_class = REV_SAFETY_TOF_VALID;
    out.depth_m   = (float)range_mm / 1000.0f;
    return out;
  }

  if (range_mm == 0u && status_is_no_target(status)) {
    out.tof_class = REV_SAFETY_TOF_CLEAR;
    out.depth_m   = REV_SAFETY_TOF_CLEAR_DEPTH_M;
    return out;
  }

  out.tof_class = REV_SAFETY_TOF_INVALID;
  out.depth_m   = 0.0f;
  return out;
}
