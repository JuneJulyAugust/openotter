/* SPDX-License-Identifier: BSD-3-Clause */
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "rev_safety_l5.h"

static int g_fails = 0;

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
  f.zones[9].status = 0u;
  f.zones[10].range_mm = 700u;
  f.zones[10].status = 0u;

  RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);

  expect_class("min class", r.tof_class, REV_SAFETY_TOF_VALID);
  expect_near("min depth", r.depth_m, 0.7f, 1e-6f);
}

static void test_uses_single_valid_selected_zone(void) {
  Tof_Frame_t f = make_l5_4x4();
  f.zones[9].range_mm = 1000u;
  f.zones[9].status = 2u;
  f.zones[10].range_mm = 850u;
  f.zones[10].status = 0u;

  RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);

  expect_class("single class", r.tof_class, REV_SAFETY_TOF_VALID);
  expect_near("single depth", r.depth_m, 0.85f, 1e-6f);
}

static void test_rejects_invalid_selected_zones(void) {
  Tof_Frame_t f = make_l5_4x4();
  f.zones[9].range_mm = 0u;
  f.zones[9].status = 14u;
  f.zones[10].range_mm = 600u;
  f.zones[10].status = 4u;

  RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);

  expect_class("invalid selected", r.tof_class, REV_SAFETY_TOF_INVALID);
  expect_near("invalid depth", r.depth_m, 0.0f, 1e-6f);
}

static void test_rejects_non_4x4_l5_frame(void) {
  Tof_Frame_t f = make_l5_4x4();
  f.layout = 8;
  f.zone_count = 64;
  f.zones[9].range_mm = 500u;
  f.zones[9].status = 0u;
  f.zones[10].range_mm = 400u;
  f.zones[10].status = 0u;

  RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);

  expect_class("non-4x4", r.tof_class, REV_SAFETY_TOF_INVALID);
}

int main(void) {
  test_uses_min_of_row3_center_zones();
  test_uses_single_valid_selected_zone();
  test_rejects_invalid_selected_zones();
  test_rejects_non_4x4_l5_frame();
  if (g_fails == 0) {
    printf("rev_safety_l5 tests: OK\n");
    return 0;
  }
  printf("rev_safety_l5 tests: %d FAIL\n", g_fails);
  return 1;
}
