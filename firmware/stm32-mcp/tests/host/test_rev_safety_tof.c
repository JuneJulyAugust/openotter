/* SPDX-License-Identifier: BSD-3-Clause */
#include <math.h>
#include <stdio.h>

#include "rev_safety_tof.h"

static int g_fails = 0;

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

static void test_accepts_valid_status_codes(void) {
  RevSafetyTofReading_t reading = RevSafety_ClassifyTofReading(850u, 0u);
  expect_class("status 0 valid", reading.tof_class, REV_SAFETY_TOF_VALID);
  expect_near("status 0 depth", reading.depth_m, 0.85f, 1e-6f);

  reading = RevSafety_ClassifyTofReading(120u, 3u);
  expect_class("status 3 valid", reading.tof_class, REV_SAFETY_TOF_VALID);
  expect_near("status 3 depth", reading.depth_m, 0.12f, 1e-6f);

  reading = RevSafety_ClassifyTofReading(1400u, 6u);
  expect_class("status 6 valid", reading.tof_class, REV_SAFETY_TOF_VALID);
  expect_near("status 6 depth", reading.depth_m, 1.4f, 1e-6f);

  reading = RevSafety_ClassifyTofReading(900u, 11u);
  expect_class("status 11 valid", reading.tof_class, REV_SAFETY_TOF_VALID);
  expect_near("status 11 depth", reading.depth_m, 0.9f, 1e-6f);
}

static void test_treats_no_target_as_clear_path(void) {
  RevSafetyTofReading_t reading = RevSafety_ClassifyTofReading(0u, 14u);
  expect_class("range_invalid zero means clear",
               reading.tof_class, REV_SAFETY_TOF_CLEAR);
  expect_near("range_invalid zero depth",
              reading.depth_m, REV_SAFETY_TOF_CLEAR_DEPTH_M, 1e-6f);

  reading = RevSafety_ClassifyTofReading(0u, 255u);
  expect_class("none zero means clear",
               reading.tof_class, REV_SAFETY_TOF_CLEAR);
  expect_near("none zero depth",
              reading.depth_m, REV_SAFETY_TOF_CLEAR_DEPTH_M, 1e-6f);
}

static void test_preserves_true_sensor_faults_as_invalid(void) {
  RevSafetyTofReading_t reading = RevSafety_ClassifyTofReading(0u, 2u);
  expect_class("signal fail invalid",
               reading.tof_class, REV_SAFETY_TOF_INVALID);
  expect_near("signal fail zero depth", reading.depth_m, 0.0f, 1e-6f);

  reading = RevSafety_ClassifyTofReading(400u, 4u);
  expect_class("outofbounds with range invalid",
               reading.tof_class, REV_SAFETY_TOF_INVALID);
  expect_near("outofbounds with range zero depth", reading.depth_m, 0.0f, 1e-6f);
}

int main(void) {
  test_accepts_valid_status_codes();
  test_treats_no_target_as_clear_path();
  test_preserves_true_sensor_faults_as_invalid();
  if (g_fails == 0) {
    printf("rev_safety_tof tests: OK\n");
    return 0;
  }
  printf("rev_safety_tof tests: %d FAIL\n", g_fails);
  return 1;
}
