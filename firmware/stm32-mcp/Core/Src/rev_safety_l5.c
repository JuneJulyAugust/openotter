/* SPDX-License-Identifier: BSD-3-Clause */
#include "rev_safety_l5.h"

/*
 * VL53L5CX target_status codes (per ST UM2884 §5.5.6 and the driver header
 * comment "5 & 9 means ranging OK" in vl53l5cx_api.h):
 *
 *    5  Range valid                                        — primary
 *    6  Wrap around not performed (typical for long range) — valid range
 *    9  Range valid with large pulse                       — primary
 *   10  Range valid, no target at previous range           — valid range
 *
 * All four are documented as valid distance measurements. Anything else
 * (including 0 = "ranging data not updated", 3 = "sigma too high",
 * 11 = "measurement consistency failed") must be rejected — those are the
 * VL53L1 "valid" codes and have completely different semantics on L5.
 *
 * Earlier revisions copied the L1 whitelist {0, 3, 6, 11} verbatim, which
 * rejected every normal status=5 frame and tripped REV_SAFETY_CAUSE_TOF_BLIND
 * after `tof_blind_frames` clean reads, producing a spurious rear emergency
 * brake whenever the sensor was actually working.
 */
static int l5_status_is_valid(uint8_t status) {
  return status == 5u || status == 6u || status == 9u || status == 10u;
}

#define REV_SAFETY_L5_CLEAR_MIN_MM 4000u

static int zone_is_valid(const Tof_Zone_t *zone) {
  return zone && zone->range_mm > 0u && l5_status_is_valid(zone->status);
}

static int zone_is_clear(const Tof_Zone_t *zone) {
  if (!zone) return 0;
  if (zone->range_mm == 0u && zone->flags == 0u) return 1;
  return zone->status == 2u && zone->range_mm >= REV_SAFETY_L5_CLEAR_MIN_MM;
}

static int zone_is_near_invalid(const Tof_Zone_t *zone) {
  return zone && !zone_is_valid(zone) && !zone_is_clear(zone);
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
  } else if (zone_is_clear(a) && zone_is_clear(b)) {
    /* Both selected zones confirmed no near target — safe to report CLEAR
     * and let the supervisor smoothe its depth toward the synthetic 4 m
     * value. */
    out.tof_class = REV_SAFETY_TOF_CLEAR;
    out.depth_m = REV_SAFETY_TOF_CLEAR_DEPTH_M;
  } else if ((zone_is_clear(a) || zone_is_clear(b)) &&
             (zone_is_near_invalid(a) || zone_is_near_invalid(b))) {
    /* Mixed: one zone is solidly clear, the other saw a target but could
     * not measure phase (status 2 with flags > 0, or any non-whitelisted
     * status with non-zero range). Do NOT report CLEAR — the uncertain
     * zone may be observing a real obstacle the supervisor must not
     * average away. Do NOT report INVALID either, or the blind-frame
     * counter would trip TOF_BLIND on benign single-zone flicker. */
    out.tof_class = REV_SAFETY_TOF_PARTIAL;
  }
  return out;
}
