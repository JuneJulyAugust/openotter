/* SPDX-License-Identifier: BSD-3-Clause */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "rev_safety.h"

static int g_fails = 0;

static void expect_near(const char *label, float got, float want, float tol) {
  if (fabsf(got - want) > tol) {
    fprintf(stderr, "FAIL %s: got %.4f want %.4f (tol %.4f)\n",
            label, got, want, tol);
    g_fails++;
  }
}

static void test_critical_distance_reverse_table(void) {
  /* Values from spec §3.9 reverse table, tSysFW=0.34 s, dMarginRear=0.17 m,
   * decelIntercept=0.66, decelSlope=0.87. Exact integral stopping distance. */
  RevSafetyConfig_t cfg;
  RevSafety_GetDefaultConfig(&cfg);

  expect_near("cd(0.3)", RevSafety_CriticalDistance(&cfg, 0.3f), 0.326f, 0.01f);
  expect_near("cd(0.5)", RevSafety_CriticalDistance(&cfg, 0.5f), 0.473f, 0.01f);
  expect_near("cd(1.0)", RevSafety_CriticalDistance(&cfg, 1.0f), 0.926f, 0.01f);
  expect_near("cd(1.5)", RevSafety_CriticalDistance(&cfg, 1.5f), 1.453f, 0.01f);
}

static void test_critical_distance_zero_speed(void) {
  RevSafetyConfig_t cfg;
  RevSafety_GetDefaultConfig(&cfg);
  /* At v=0 reaction and stopping terms vanish, only margin remains. */
  expect_near("cd(0.0)", RevSafety_CriticalDistance(&cfg, 0.0f),
              cfg.d_margin_rear_m, 0.001f);
}

int main(void) {
  test_critical_distance_reverse_table();
  test_critical_distance_zero_speed();
  if (g_fails == 0) {
    printf("rev_safety tests: OK\n");
    return 0;
  }
  printf("rev_safety tests: %d FAIL\n", g_fails);
  return 1;
}