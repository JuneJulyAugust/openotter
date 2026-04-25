/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdio.h>
#include <stdint.h>

#include "firmware_watchdog.h"

static int g_fails = 0;

static void expect_eq_u(const char *label, uint32_t got, uint32_t want) {
  if (got != want) {
    fprintf(stderr, "FAIL %s: got %u want %u\n", label,
            (unsigned)got, (unsigned)want);
    g_fails++;
  }
}

static void expect_in_range(const char *label, uint32_t got,
                            uint32_t lo, uint32_t hi) {
  if (got < lo || got > hi) {
    fprintf(stderr, "FAIL %s: got %u not in [%u, %u]\n", label,
            (unsigned)got, (unsigned)lo, (unsigned)hi);
    g_fails++;
  }
}

/* Pin the LSI default constant so a wrong override gets caught. */
static void test_default_lsi_constant(void) {
  expect_eq_u("LSI Hz", FW_WATCHDOG_LSI_HZ, 32000u);
}

static void test_compute_reload_zero_inputs_return_zero(void) {
  expect_eq_u("lsi=0",        FwWatchdog_ComputeReload(1000u, 0u, 32u), 0u);
  expect_eq_u("prescaler=0",  FwWatchdog_ComputeReload(1000u, 32000u, 0u), 0u);
  expect_eq_u("timeout=0",    FwWatchdog_ComputeReload(0u, 32000u, 32u), 0u);
}

static void test_compute_reload_typical_2s_at_div_32(void) {
  /* lsi=32 kHz, divider=32 → 1 kHz tick; 2 s → reload = 2000.
   * Must fit (max 4095) and round to 2000. */
  uint16_t r = FwWatchdog_ComputeReload(2000u, 32000u, 32u);
  expect_eq_u("2 s at /32", r, 2000u);
}

static void test_compute_reload_clamps_when_exceeds_12_bit(void) {
  /* lsi=32 kHz, divider=4 → 8 kHz; 2 s → reload would be 16000, > 4095.
   * Function must reject by returning 0 so the caller picks a larger
   * prescaler. */
  uint16_t r = FwWatchdog_ComputeReload(2000u, 32000u, 4u);
  expect_eq_u("2 s at /4 unrepresentable", r, 0u);
}

static void test_pick_prescaler_picks_smallest_that_fits(void) {
  /* For 2 s at LSI 32 kHz:
   *   /4   → 16000 (no)
   *   /8   →  8000 (no)
   *   /16  →  4000 (yes; fits in 12 bits)
   * So we want divider 16. */
  uint16_t p = FwWatchdog_PickPrescaler(2000u, 32000u);
  expect_eq_u("2 s prescaler", p, 16u);
}

static void test_pick_prescaler_handles_short_timeout(void) {
  /* 1 ms at LSI 32 kHz: reload at /4 = 8 → fits trivially. */
  uint16_t p = FwWatchdog_PickPrescaler(1u, 32000u);
  expect_eq_u("1 ms prescaler", p, 4u);
}

static void test_pick_prescaler_returns_zero_when_unrepresentable(void) {
  /* At LSI 32 kHz with /256 the max representable timeout is
   * 4095 * 256 / 32000 ≈ 32.76 s. Anything beyond should fail. */
  uint16_t p = FwWatchdog_PickPrescaler(60000u, 32000u);
  expect_eq_u("60 s unrepresentable at LSI 32 kHz", p, 0u);
}

static void test_default_timeout_is_in_safe_range(void) {
  /* The default 2 s must always be representable on the real LSI clock,
   * otherwise FwWatchdog_Init silently falls back to the longest period
   * and the watchdog meaning shifts. */
  uint16_t p = FwWatchdog_PickPrescaler(FW_WATCHDOG_DEFAULT_TIMEOUT_MS,
                                        FW_WATCHDOG_LSI_HZ);
  expect_in_range("default timeout prescaler", p, 4u, 256u);

  uint16_t r = FwWatchdog_ComputeReload(FW_WATCHDOG_DEFAULT_TIMEOUT_MS,
                                        FW_WATCHDOG_LSI_HZ, p);
  expect_in_range("default timeout reload", r, 1u, 4095u);
}

static void test_round_trip_actual_timeout_close_to_requested(void) {
  /* The round-trip computed timeout (using the picked reload + prescaler)
   * should match the requested 2 s within ±50 ms — i.e. better than 3 %
   * margin. Catches off-by-one mistakes in the divider math. */
  uint32_t want_ms = 2000u;
  uint16_t prescaler = FwWatchdog_PickPrescaler(want_ms, FW_WATCHDOG_LSI_HZ);
  uint16_t reload    = FwWatchdog_ComputeReload(want_ms, FW_WATCHDOG_LSI_HZ,
                                                prescaler);
  /* actual_ms = reload * prescaler * 1000 / lsi_hz */
  uint32_t actual_ms = (uint32_t)(((uint64_t)reload * prescaler * 1000u) /
                                  FW_WATCHDOG_LSI_HZ);
  expect_in_range("actual ms vs 2000 ± 50", actual_ms, 1950u, 2050u);
}

int main(void) {
  test_default_lsi_constant();
  test_compute_reload_zero_inputs_return_zero();
  test_compute_reload_typical_2s_at_div_32();
  test_compute_reload_clamps_when_exceeds_12_bit();
  test_pick_prescaler_picks_smallest_that_fits();
  test_pick_prescaler_handles_short_timeout();
  test_pick_prescaler_returns_zero_when_unrepresentable();
  test_default_timeout_is_in_safe_range();
  test_round_trip_actual_timeout_close_to_requested();
  if (g_fails == 0) {
    printf("firmware_watchdog tests: OK\n");
    return 0;
  }
  printf("firmware_watchdog tests: %d FAIL\n", g_fails);
  return 1;
}
