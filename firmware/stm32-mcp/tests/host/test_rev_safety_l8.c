/* SPDX-License-Identifier: BSD-3-Clause */
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "rev_safety_l8.h"
#include "tof_l8_status.h"

static int g_fails = 0;

/*
 * VL53L8CX target_status codes (per ST UM2884 §5.5.6):
 *   0  ranging data not updated   (INVALID)
 *   2  target phase                (INVALID)
 *   3  sigma estimator too high   (INVALID)
 *   4  target consistency failed  (INVALID)
 *   5  range valid                (VALID, primary)
 *   6  wrap-around not performed  (VALID)
 *   9  range valid w/ large pulse (VALID, primary)
 *  10  range valid, no prev target(VALID)
 *  11  measurement consistency failed (INVALID)
 *  14  no documented mapping; treat as INVALID
 */

static Tof_Frame_t make_l8_4x4(void) {
  Tof_Frame_t f;
  memset(&f, 0, sizeof(f));
  f.sensor_type = TOF_SENSOR_VL53L8CX;
  f.layout = 4;
  f.zone_count = 16;
  for (uint8_t i = 0; i < 16; ++i) {
    f.zones[i].status = 14u;
    f.zones[i].range_mm = 0u;
  }
  return f;
}

static void expect_class(const char *label,
                         RevSafetyTofClass_t got,
                         RevSafetyTofClass_t want) {
  if (got != want) {
    fprintf(stderr, "FAIL %s: class got %d want %d\n", label, got, want);
    g_fails++;
  }
}

static void expect_near(const char *label, float got, float want, float tol) {
  if (fabsf(got - want) > tol) {
    fprintf(stderr, "FAIL %s: got %.4f want %.4f (tol %.4f)\n",
            label, got, want, tol);
    g_fails++;
  }
}

static void test_uses_min_of_row3_center_zones(void) {
  Tof_Frame_t f = make_l8_4x4();
  f.zones[9].range_mm = 900u;
  f.zones[9].status = 5u;          /* range valid */
  f.zones[10].range_mm = 700u;
  f.zones[10].status = 5u;

  RevSafetyTofReading_t r = RevSafetyL8_SelectReverseReading(&f);

  expect_class("min class", r.tof_class, REV_SAFETY_TOF_VALID);
  expect_near("min depth", r.depth_m, 0.7f, 1e-6f);
}

static void test_front_reader_matches_rear_center_selection(void) {
  Tof_Frame_t f = make_l8_4x4();
  f.zones[9].range_mm = 900u;
  f.zones[9].status = 5u;
  f.zones[10].range_mm = 650u;
  f.zones[10].status = 9u;

  RevSafetyTofReading_t r = RevSafetyL8_SelectFrontReading(&f);

  expect_class("front min class", r.tof_class, REV_SAFETY_TOF_VALID);
  expect_near("front min depth", r.depth_m, 0.65f, 1e-6f);
}

static void test_status_validity_set_is_l8_specific(void) {
  for (uint8_t status = 0u; status < 16u; ++status) {
    int want = status == 5u || status == 6u ||
               status == 9u || status == 10u;
    if (TofL8_StatusIsRangeValid(status) != want) {
      fprintf(stderr, "FAIL status %u validity mismatch\n", (unsigned)status);
      g_fails++;
    }
  }
}

static void test_uses_single_valid_selected_zone(void) {
  Tof_Frame_t f = make_l8_4x4();
  f.zones[9].range_mm = 1000u;
  f.zones[9].status = 2u;          /* target phase — INVALID */
  f.zones[10].range_mm = 850u;
  f.zones[10].status = 9u;         /* range valid w/ large pulse */

  RevSafetyTofReading_t r = RevSafetyL8_SelectReverseReading(&f);

  expect_class("single class", r.tof_class, REV_SAFETY_TOF_VALID);
  expect_near("single depth", r.depth_m, 0.85f, 1e-6f);
}

static void test_degrades_invalid_selected_zones(void) {
  /* Both selected zones gave usable info to neither pipeline:
   *   zone 9  — undocumented status 14 with non-zero range and flags=1
   *             ("target seen, status not in any valid set"): near_invalid.
   *   zone 10 — status 4 with non-zero range and flags=1
   *             ("target consistency failed"):                 near_invalid.
   * The frame is alive but the selected safety ROI is degraded, so it must
   * not feed bogus ranges or the blind-frame counter. */
  Tof_Frame_t f = make_l8_4x4();
  f.zones[9].range_mm = 500u;
  f.zones[9].status = 14u;
  f.zones[9].flags = 1u;
  f.zones[10].range_mm = 600u;
  f.zones[10].status = 4u;
  f.zones[10].flags = 1u;

  RevSafetyTofReading_t r = RevSafetyL8_SelectReverseReading(&f);

  expect_class("invalid selected", r.tof_class, REV_SAFETY_TOF_PARTIAL);
  expect_near("invalid depth", r.depth_m, 0.0f, 1e-6f);
}

static void test_rejects_non_4x4_l8_frame(void) {
  Tof_Frame_t f = make_l8_4x4();
  f.layout = 8;
  f.zone_count = 64;
  f.zones[9].range_mm = 500u;
  f.zones[9].status = 5u;
  f.zones[10].range_mm = 400u;
  f.zones[10].status = 5u;

  RevSafetyTofReading_t r = RevSafetyL8_SelectReverseReading(&f);

  expect_class("non-4x4", r.tof_class, REV_SAFETY_TOF_INVALID);
}

/* Regression: VL53L1 status codes must NOT be treated as valid on L8.
 * VL53L1 RangeStatus 0 = RANGE_VALID, but L8 target_status 0 = "data not
 * updated". Earlier code copied the L1 whitelist {0,3,6,11} to L8, which
 * (a) rejected real status=5 frames as invalid (false TOF_BLIND brake)
 * and (b) accepted real status=0/11 frames as valid.
 */
static void test_l1_valid_codes_are_degraded_on_l8(void) {
  uint8_t l1_valid_only_codes[2] = {0u, 11u};
  for (size_t i = 0; i < sizeof(l1_valid_only_codes); ++i) {
    Tof_Frame_t f = make_l8_4x4();
    f.zones[9].range_mm = 500u;
    f.zones[9].status = l1_valid_only_codes[i];
    f.zones[10].range_mm = 500u;
    f.zones[10].status = l1_valid_only_codes[i];

    RevSafetyTofReading_t r = RevSafetyL8_SelectReverseReading(&f);
    char label[64];
    snprintf(label, sizeof(label), "L1 status %u degraded on L8",
             (unsigned)l1_valid_only_codes[i]);
    expect_class(label, r.tof_class, REV_SAFETY_TOF_PARTIAL);
  }
}

/* Regression: status 6 (wrap-around not performed) and status 10 (range
 * valid, no previous target) are both documented as valid range readings
 * on VL53L8CX (UM2884) and must be accepted. */
static void test_l8_marginal_valid_codes(void) {
  uint8_t l8_valid_codes[2] = {6u, 10u};
  for (size_t i = 0; i < sizeof(l8_valid_codes); ++i) {
    Tof_Frame_t f = make_l8_4x4();
    f.zones[9].range_mm = 750u;
    f.zones[9].status = l8_valid_codes[i];
    /* Other selected zone is invalid so we know depth comes from zone 9. */

    RevSafetyTofReading_t r = RevSafetyL8_SelectReverseReading(&f);
    char label[64];
    snprintf(label, sizeof(label), "L8 status %u accepted",
             (unsigned)l8_valid_codes[i]);
    expect_class(label, r.tof_class, REV_SAFETY_TOF_VALID);
    expect_near(label, r.depth_m, 0.75f, 1e-6f);
  }
}

static void test_l8_valid_ranges_above_trusted_cap_are_clear(void) {
  Tof_Frame_t f = make_l8_4x4();
  f.zones[9].range_mm = 3900u;
  f.zones[9].status = 5u;
  f.zones[10].range_mm = 4300u;
  f.zones[10].status = 9u;

  RevSafetyTofReading_t r = RevSafetyL8_SelectReverseReading(&f);

  expect_class("far valid ranges clear", r.tof_class, REV_SAFETY_TOF_CLEAR);
  expect_near("far valid ranges capped depth", r.depth_m,
              REV_SAFETY_L8_CLEAR_DEPTH_M, 1e-6f);
}

static void test_l8_trusted_cap_is_inclusive_valid_depth(void) {
  Tof_Frame_t f = make_l8_4x4();
  f.zones[9].range_mm = REV_SAFETY_L8_TRUSTED_MAX_MM;
  f.zones[9].status = 5u;
  f.zones[10].range_mm = 4200u;
  f.zones[10].status = 9u;

  RevSafetyTofReading_t r = RevSafetyL8_SelectReverseReading(&f);

  expect_class("trusted cap inclusive class",
               r.tof_class, REV_SAFETY_TOF_VALID);
  expect_near("trusted cap inclusive depth", r.depth_m,
              REV_SAFETY_L8_CLEAR_DEPTH_M, 1e-6f);
}

static void test_l8_far_valid_with_near_valid_uses_near_depth(void) {
  Tof_Frame_t f = make_l8_4x4();
  f.zones[9].range_mm = 3950u;
  f.zones[9].status = 5u;
  f.zones[10].range_mm = 1600u;
  f.zones[10].status = 9u;

  RevSafetyTofReading_t r = RevSafetyL8_SelectReverseReading(&f);

  expect_class("far valid + near valid class",
               r.tof_class, REV_SAFETY_TOF_VALID);
  expect_near("far valid + near valid depth", r.depth_m, 1.6f, 1e-6f);
}

static void test_l8_non_ok_far_status_is_degraded_not_clear(void) {
  Tof_Frame_t f = make_l8_4x4();
  f.zones[9].range_mm = 0u;
  f.zones[9].status = 255u;
  f.zones[9].flags = 0u;
  f.zones[10].range_mm = 4300u;
  f.zones[10].status = 2u;        /* target phase at/out of range */
  f.zones[10].flags = 1u;

  RevSafetyTofReading_t r = RevSafetyL8_SelectReverseReading(&f);

  expect_class("non-ok far status degraded",
               r.tof_class, REV_SAFETY_TOF_PARTIAL);
  expect_near("non-ok far status zero depth", r.depth_m, 0.0f, 1e-6f);
}

static void test_l8_far_valid_with_unreliable_other_is_degraded(void) {
  Tof_Frame_t f = make_l8_4x4();
  f.zones[9].range_mm = 4200u;
  f.zones[9].status = 5u;
  f.zones[10].range_mm = 600u;
  f.zones[10].status = 2u;
  f.zones[10].flags = 1u;

  RevSafetyTofReading_t r = RevSafetyL8_SelectReverseReading(&f);

  expect_class("far valid + unreliable -> partial",
               r.tof_class, REV_SAFETY_TOF_PARTIAL);
}

static void test_l8_non_ok_statuses_are_degraded_even_at_zero_range(void) {
  /* One selected zone observes a target it cannot phase-measure (status 2,
   * range_mm > 0, flags > 0); the other reports a non-OK zero-range value.
   * Neither selected zone produced a trusted L8 measurement, but the frame is
   * alive and should not trip TOF_BLIND by itself. */
  Tof_Frame_t f = make_l8_4x4();
  f.zones[9].range_mm = 1000u;
  f.zones[9].status = 2u;
  f.zones[9].flags = 1u;
  f.zones[10].range_mm = 0u;
  f.zones[10].status = 2u;
  f.zones[10].flags = 0u;

  RevSafetyTofReading_t r = RevSafetyL8_SelectReverseReading(&f);

  expect_class("non-ok status2 pair -> partial",
               r.tof_class, REV_SAFETY_TOF_PARTIAL);
}

static void test_l8_both_zones_near_invalid_becomes_degraded(void) {
  /* Both selected zones are near_invalid (no usable distance in either).
   * The frame is still alive, so the supervisor should hold its previous
   * reading instead of hard-failing reverse on consecutive bogus ranges. */
  Tof_Frame_t f = make_l8_4x4();
  f.zones[9].range_mm = 0u;
  f.zones[9].status = 2u;
  f.zones[9].flags = 1u;
  f.zones[10].range_mm = 800u;
  f.zones[10].status = 2u;
  f.zones[10].flags = 1u;

  RevSafetyTofReading_t r = RevSafetyL8_SelectReverseReading(&f);

  expect_class("both near_invalid -> partial",
               r.tof_class, REV_SAFETY_TOF_PARTIAL);
}

static void test_l8_far_non_ok_status_with_near_invalid_other_is_degraded(void) {
  /* One zone reports a non-valid far value and the other shows target present
   * but phase unmeasurable. Neither selected zone produced a trusted
   * measurement, but this is live degraded data rather than a dead sensor. */
  Tof_Frame_t f = make_l8_4x4();
  f.zones[9].range_mm = 4200u;
  f.zones[9].status = 2u;
  f.zones[9].flags = 0u;
  f.zones[10].range_mm = 600u;
  f.zones[10].status = 2u;
  f.zones[10].flags = 1u;

  RevSafetyTofReading_t r = RevSafetyL8_SelectReverseReading(&f);

  expect_class("far non-ok + near_invalid -> partial",
               r.tof_class, REV_SAFETY_TOF_PARTIAL);
}

int main(void) {
  test_status_validity_set_is_l8_specific();
  test_uses_min_of_row3_center_zones();
  test_front_reader_matches_rear_center_selection();
  test_uses_single_valid_selected_zone();
  test_degrades_invalid_selected_zones();
  test_rejects_non_4x4_l8_frame();
  test_l1_valid_codes_are_degraded_on_l8();
  test_l8_marginal_valid_codes();
  test_l8_valid_ranges_above_trusted_cap_are_clear();
  test_l8_trusted_cap_is_inclusive_valid_depth();
  test_l8_far_valid_with_near_valid_uses_near_depth();
  test_l8_non_ok_far_status_is_degraded_not_clear();
  test_l8_far_valid_with_unreliable_other_is_degraded();
  test_l8_non_ok_statuses_are_degraded_even_at_zero_range();
  test_l8_both_zones_near_invalid_becomes_degraded();
  test_l8_far_non_ok_status_with_near_invalid_other_is_degraded();
  if (g_fails == 0) {
    printf("rev_safety_l8 tests: OK\n");
    return 0;
  }
  printf("rev_safety_l8 tests: %d FAIL\n", g_fails);
  return 1;
}
