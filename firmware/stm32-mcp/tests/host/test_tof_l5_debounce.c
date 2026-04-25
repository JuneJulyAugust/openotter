/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdio.h>

#include "tof_l5_debounce.h"

static int g_fails = 0;

static void expect_eq_bool(const char *label, bool got, bool want) {
  if (got != want) {
    fprintf(stderr, "FAIL %s: got %d want %d\n",
            label, (int)got, (int)want);
    g_fails++;
  }
}

/* Sentinel: no prior configure → no debounce. This is the regression for
 * the unfixed secondary bug where TofL5_Init's internal Configure stamps
 * the tick, causing the next external Configure (e.g. safety mode raise)
 * to be silently dropped. The fix is for the init flow to clear the tick
 * back to 0 — this test pins the predicate's behavior so the fix is safe. */
static void test_zero_sentinel_never_skips(void) {
  expect_eq_bool("now=0, last=0",
                 TofL5Debounce_ShouldSkip(0u, 0u, 500u), false);
  expect_eq_bool("now=10000, last=0",
                 TofL5Debounce_ShouldSkip(10000u, 0u, 500u), false);
  expect_eq_bool("now=UINT32_MAX, last=0",
                 TofL5Debounce_ShouldSkip(0xFFFFFFFFu, 0u, 500u), false);
}

static void test_within_window_skips(void) {
  expect_eq_bool("1ms after, 500ms window",
                 TofL5Debounce_ShouldSkip(101u, 100u, 500u), true);
  expect_eq_bool("499ms after, 500ms window",
                 TofL5Debounce_ShouldSkip(599u, 100u, 500u), true);
  expect_eq_bool("0ms after",
                 TofL5Debounce_ShouldSkip(100u, 100u, 500u), true);
}

static void test_at_or_after_window_does_not_skip(void) {
  expect_eq_bool("exactly 500ms after",
                 TofL5Debounce_ShouldSkip(600u, 100u, 500u), false);
  expect_eq_bool("501ms after",
                 TofL5Debounce_ShouldSkip(601u, 100u, 500u), false);
  expect_eq_bool("10s after",
                 TofL5Debounce_ShouldSkip(10100u, 100u, 500u), false);
}

static void test_default_debounce_constant(void) {
  /* The fixed default is 500 ms; pin it so tof_l5.c can't drift apart
   * silently. */
  if (TOF_L5_RECONFIGURE_DEBOUNCE_MS != 500u) {
    fprintf(stderr, "FAIL default debounce: got %u want 500\n",
            (unsigned)TOF_L5_RECONFIGURE_DEBOUNCE_MS);
    g_fails++;
  }
}

int main(void) {
  test_zero_sentinel_never_skips();
  test_within_window_skips();
  test_at_or_after_window_does_not_skip();
  test_default_debounce_constant();
  if (g_fails == 0) {
    printf("tof_l5_debounce tests: OK\n");
    return 0;
  }
  printf("tof_l5_debounce tests: %d FAIL\n", g_fails);
  return 1;
}
