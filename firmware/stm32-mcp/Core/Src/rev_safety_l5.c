/* SPDX-License-Identifier: BSD-3-Clause */
#include "rev_safety_l5.h"

static int l5_status_is_valid(uint8_t status) {
  return status == 0u || status == 3u || status == 6u || status == 11u;
}

static int zone_is_valid(const Tof_Zone_t *zone) {
  return zone && zone->range_mm > 0u && l5_status_is_valid(zone->status);
}

RevSafetyTofReading_t RevSafetyL5_SelectReverseReading(const Tof_Frame_t *frame) {
  RevSafetyTofReading_t out = {0};
  if (!frame ||
      frame->sensor_type != TOF_SENSOR_VL53L5CX ||
      frame->layout != REV_SAFETY_L5_LAYOUT ||
      frame->zone_count < 16u) {
    return out;
  }

  const Tof_Zone_t *a = &frame->zones[REV_SAFETY_L5_ZONE_ROW3_COL2];
  const Tof_Zone_t *b = &frame->zones[REV_SAFETY_L5_ZONE_ROW3_COL3];
  uint16_t min_mm = 0u;

  if (zone_is_valid(a)) min_mm = a->range_mm;
  if (zone_is_valid(b) && (min_mm == 0u || b->range_mm < min_mm)) {
    min_mm = b->range_mm;
  }

  if (min_mm > 0u) {
    out.tof_class = REV_SAFETY_TOF_VALID;
    out.depth_m = (float)min_mm / 1000.0f;
  }
  return out;
}
