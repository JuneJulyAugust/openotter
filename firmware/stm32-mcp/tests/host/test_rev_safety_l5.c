/* SPDX-License-Identifier: BSD-3-Clause */
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "rev_safety_l5.h"

static int g_fails = 0;

/*
 * VL53L5CX target_status codes (per ST UM2884 §5.5.6):
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

static Tof_Frame_t make_l5_4x4(void) {
  Tof_Frame_t f;
  memset(&f, 0, sizeof(f));
  f.sensor_type = TOF_SENSOR_VL53L5CX;
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
  Tof_Frame_t f = make_l5_4x4();
  f.zones[9].range_mm = 900u;
  f.zones[9].status = 5u;          /* range valid */
  f.zones[10].range_mm = 700u;
  f.zones[10].status = 5u;

  RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);

  expect_class("min class", r.tof_class, REV_SAFETY_TOF_VALID);
  expect_near("min depth", r.depth_m, 0.7f, 1e-6f);
}

static void test_uses_single_valid_selected_zone(void) {
  Tof_Frame_t f = make_l5_4x4();
  f.zones[9].range_mm = 1000u;
  f.zones[9].status = 2u;          /* target phase — INVALID */
  f.zones[10].range_mm = 850u;
  f.zones[10].status = 9u;         /* range valid w/ large pulse */

  RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);

  expect_class("single class", r.tof_class, REV_SAFETY_TOF_VALID);
  expect_near("single depth", r.depth_m, 0.85f, 1e-6f);
}

static void test_rejects_invalid_selected_zones(void) {
  /* Both selected zones gave usable info to neither pipeline:
   *   zone 9  — undocumented status 14 with non-zero range and flags=1
   *             ("target seen, status not in any valid set"): near_invalid.
   *   zone 10 — status 4 with non-zero range and flags=1
   *             ("target consistency failed"):                 near_invalid.
   * Two near_invalid zones means the frame is genuinely blind and must
   * trip the supervisor's blind-frame counter. This is distinct from the
   * mixed PARTIAL case where one zone gave usable info. */
  Tof_Frame_t f = make_l5_4x4();
  f.zones[9].range_mm = 500u;
  f.zones[9].status = 14u;
  f.zones[9].flags = 1u;
  f.zones[10].range_mm = 600u;
  f.zones[10].status = 4u;
  f.zones[10].flags = 1u;

  RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);

  expect_class("invalid selected", r.tof_class, REV_SAFETY_TOF_INVALID);
  expect_near("invalid depth", r.depth_m, 0.0f, 1e-6f);
}

static void test_rejects_non_4x4_l5_frame(void) {
  Tof_Frame_t f = make_l5_4x4();
  f.layout = 8;
  f.zone_count = 64;
  f.zones[9].range_mm = 500u;
  f.zones[9].status = 5u;
  f.zones[10].range_mm = 400u;
  f.zones[10].status = 5u;

  RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);

  expect_class("non-4x4", r.tof_class, REV_SAFETY_TOF_INVALID);
}

/* Regression: VL53L1 status codes must NOT be treated as valid on L5.
 * VL53L1 RangeStatus 0 = RANGE_VALID, but L5 target_status 0 = "data not
 * updated". Earlier code copied the L1 whitelist {0,3,6,11} to L5, which
 * (a) rejected real status=5 frames as invalid (false TOF_BLIND brake)
 * and (b) accepted real status=0/11 frames as valid.
 */
static void test_l1_valid_codes_are_invalid_on_l5(void) {
  uint8_t l1_valid_only_codes[2] = {0u, 11u};
  for (size_t i = 0; i < sizeof(l1_valid_only_codes); ++i) {
    Tof_Frame_t f = make_l5_4x4();
    f.zones[9].range_mm = 500u;
    f.zones[9].status = l1_valid_only_codes[i];
    f.zones[10].range_mm = 500u;
    f.zones[10].status = l1_valid_only_codes[i];

    RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);
    char label[64];
    snprintf(label, sizeof(label), "L1 status %u rejected on L5",
             (unsigned)l1_valid_only_codes[i]);
    expect_class(label, r.tof_class, REV_SAFETY_TOF_INVALID);
  }
}

/* Regression: status 6 (wrap-around not performed) and status 10 (range
 * valid, no previous target) are both documented as valid range readings
 * on VL53L5CX (UM2884) and must be accepted. */
static void test_l5_marginal_valid_codes(void) {
  uint8_t l5_valid_codes[2] = {6u, 10u};
  for (size_t i = 0; i < sizeof(l5_valid_codes); ++i) {
    Tof_Frame_t f = make_l5_4x4();
    f.zones[9].range_mm = 750u;
    f.zones[9].status = l5_valid_codes[i];
    /* Other selected zone is invalid so we know depth comes from zone 9. */

    RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);
    char label[64];
    snprintf(label, sizeof(label), "L5 status %u accepted",
             (unsigned)l5_valid_codes[i]);
    expect_class(label, r.tof_class, REV_SAFETY_TOF_VALID);
    expect_near(label, r.depth_m, 0.75f, 1e-6f);
  }
}

static void test_l5_far_status2_is_clear_not_blind(void) {
  Tof_Frame_t f = make_l5_4x4();
  f.zones[9].range_mm = 0u;
  f.zones[9].status = 2u;
  f.zones[9].flags = 0u;          /* no target detected */
  f.zones[10].range_mm = 4300u;
  f.zones[10].status = 2u;        /* target phase at/out of range */
  f.zones[10].flags = 1u;

  RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);

  expect_class("far status2 clear", r.tof_class, REV_SAFETY_TOF_CLEAR);
  expect_near("far status2 depth", r.depth_m, REV_SAFETY_TOF_CLEAR_DEPTH_M,
              1e-6f);
}

static void test_l5_near_status2_with_clear_other_is_partial(void) {
  /* One selected zone observes a target it cannot phase-measure (status 2,
   * range_mm > 0, flags > 0); the other reports no target. The frame must
   * surface as PARTIAL so the supervisor holds its previous depth instead
   * of either averaging the uncertain zone toward "clear" or burning a
   * blind-frame slot on benign single-zone flicker. */
  Tof_Frame_t f = make_l5_4x4();
  f.zones[9].range_mm = 1000u;
  f.zones[9].status = 2u;
  f.zones[9].flags = 1u;
  f.zones[10].range_mm = 0u;
  f.zones[10].status = 2u;
  f.zones[10].flags = 0u;

  RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);

  expect_class("near status2 + clear -> partial",
               r.tof_class, REV_SAFETY_TOF_PARTIAL);
}

static void test_l5_both_zones_near_invalid_stays_invalid(void) {
  /* Both selected zones are near_invalid (no usable distance in either).
   * The frame is genuinely blind and must trip the blind-frame counter. */
  Tof_Frame_t f = make_l5_4x4();
  f.zones[9].range_mm = 0u;
  f.zones[9].status = 2u;
  f.zones[9].flags = 1u;
  f.zones[10].range_mm = 800u;
  f.zones[10].status = 2u;
  f.zones[10].flags = 1u;

  RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);

  expect_class("both near_invalid -> invalid",
               r.tof_class, REV_SAFETY_TOF_INVALID);
}

static void test_l5_far_status2_with_near_invalid_other_is_partial(void) {
  /* Mirror of the bench case in the screenshots: one zone solidly clear at
   * >= 4 m, the other shows status 2 with range_mm > 0 and flags > 0
   * (target present, phase unmeasurable). Must surface PARTIAL, not CLEAR
   * — the uncertain zone may be observing a real near obstacle. */
  Tof_Frame_t f = make_l5_4x4();
  f.zones[9].range_mm = 4200u;
  f.zones[9].status = 2u;
  f.zones[9].flags = 0u;
  f.zones[10].range_mm = 600u;
  f.zones[10].status = 2u;
  f.zones[10].flags = 1u;

  RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);

  expect_class("far clear + near_invalid -> partial",
               r.tof_class, REV_SAFETY_TOF_PARTIAL);
}

int main(void) {
  test_uses_min_of_row3_center_zones();
  test_uses_single_valid_selected_zone();
  test_rejects_invalid_selected_zones();
  test_rejects_non_4x4_l5_frame();
  test_l1_valid_codes_are_invalid_on_l5();
  test_l5_marginal_valid_codes();
  test_l5_far_status2_is_clear_not_blind();
  test_l5_near_status2_with_clear_other_is_partial();
  test_l5_both_zones_near_invalid_stays_invalid();
  test_l5_far_status2_with_near_invalid_other_is_partial();
  if (g_fails == 0) {
    printf("rev_safety_l5 tests: OK\n");
    return 0;
  }
  printf("rev_safety_l5 tests: %d FAIL\n", g_fails);
  return 1;
}
