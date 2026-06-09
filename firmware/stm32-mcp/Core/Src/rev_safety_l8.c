/* SPDX-License-Identifier: BSD-3-Clause */
#include "rev_safety_l8.h"
#include "tof_l8_status.h"

/*
 * VL53L8CX target_status codes (per ST UM3109 and the driver header
 * comment "5 & 9 means ranging OK" in vl53l8cx_api.h):
 *
 *    5  Range valid                                        — primary
 *    6  Wrap around not performed (typical for long range) — valid range
 *    9  Range valid with large pulse                       — primary
 *   10  Range valid, no target at previous range           — valid range
 *
 * All four are documented as valid distance measurements. Anything else
 * (including 0 = "ranging data not updated", 3 = "sigma too high",
 * 11 = "measurement consistency failed") must be rejected — those are the
 * VL53L1 "valid" codes and have completely different semantics here.
 *
 * Earlier revisions copied the L1 whitelist {0, 3, 6, 11} verbatim, which
 * rejected every normal status=5 frame and tripped REV_SAFETY_CAUSE_TOF_BLIND
 * after `tof_blind_frames` clean reads, producing a spurious rear emergency
 * brake whenever the sensor was actually working.
 *
 * Bench testing showed the VL53L8CX becomes unstable near its 4 m published
 * range limit. The safety supervisor therefore only trusts measured depths
 * up to REV_SAFETY_L8_TRUSTED_MAX_MM. Valid-status values beyond that cap are
 * treated as capped clearance; non-valid statuses remain degraded live data
 * even if they carry a plausible close or far distance.
 */

static int zone_has_trusted_range(const Tof_Zone_t *zone) {
  return zone &&
         zone->range_mm > 0u &&
         zone->range_mm <= REV_SAFETY_L8_TRUSTED_MAX_MM &&
         TofL8_StatusIsRangeValid(zone->status);
}

static int zone_is_far_clear(const Tof_Zone_t *zone) {
  return zone &&
         zone->range_mm > REV_SAFETY_L8_TRUSTED_MAX_MM &&
         TofL8_StatusIsRangeValid(zone->status);
}

RevSafetyTofReading_t RevSafetyL8_SelectReverseReading(const Tof_Frame_t *frame) {
  RevSafetyTofReading_t out = {0};
  if (!frame ||
      frame->sensor_type != TOF_SENSOR_VL53L8CX ||
      frame->layout != REV_SAFETY_L8_LAYOUT ||
      frame->zone_count < 16u) {
    return out;
  }

  const Tof_Zone_t *a = &frame->zones[REV_SAFETY_L8_ZONE_ROW3_COL2];
  const Tof_Zone_t *b = &frame->zones[REV_SAFETY_L8_ZONE_ROW3_COL3];
  uint16_t min_mm = 0u;

  if (zone_has_trusted_range(a)) min_mm = a->range_mm;
  if (zone_has_trusted_range(b) && (min_mm == 0u || b->range_mm < min_mm)) {
    min_mm = b->range_mm;
  }

  if (min_mm > 0u) {
    out.tof_class = REV_SAFETY_TOF_VALID;
    out.depth_m = (float)min_mm / 1000.0f;
  } else if (zone_is_far_clear(a) && zone_is_far_clear(b)) {
    /* Both selected zones produced valid-status ranges, but only beyond the
     * trusted safety band. Report capped clearance rather than feeding the
     * unstable far values into the EMA. */
    out.tof_class = REV_SAFETY_TOF_CLEAR;
    out.depth_m = REV_SAFETY_L8_CLEAR_DEPTH_M;
  } else {
    /* The frame is alive, but the selected safety zones did not produce a
     * trusted distance. Treat it as degraded live data: hold the previous
     * supervisor depth and let driver-dead/frame-gap catch true sensor loss. */
    out.tof_class = REV_SAFETY_TOF_PARTIAL;
  }
  return out;
}

RevSafetyTofReading_t RevSafetyL8_SelectFrontReading(const Tof_Frame_t *frame) {
  return RevSafetyL8_SelectReverseReading(frame);
}
