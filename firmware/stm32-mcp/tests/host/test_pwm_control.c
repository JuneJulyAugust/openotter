/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdio.h>
#include <stdint.h>

#include "pwm_control.h"

static int g_fails = 0;

static void expect_eq(const char *label, int got, int want) {
  if (got != want) {
    fprintf(stderr, "FAIL %s: got %d want %d\n", label, got, want);
    g_fails++;
  }
}

static void test_in_range_unchanged(void) {
  expect_eq("neutral",     PwmControl_ClampPulse(1500), 1500);
  expect_eq("mid-forward", PwmControl_ClampPulse(1750), 1750);
  expect_eq("mid-reverse", PwmControl_ClampPulse(1250), 1250);
}

static void test_clamp_bounds(void) {
  expect_eq("min exact",   PwmControl_ClampPulse(PWM_MIN_US), PWM_MIN_US);
  expect_eq("max exact",   PwmControl_ClampPulse(PWM_MAX_US), PWM_MAX_US);
  expect_eq("below min",   PwmControl_ClampPulse(900),        PWM_MIN_US);
  expect_eq("above max",   PwmControl_ClampPulse(2100),       PWM_MAX_US);
}

static void test_clamp_extremes(void) {
  /* int16_t bounds: -32768 .. 32767. Clamper must absorb both. */
  expect_eq("int16 min",   PwmControl_ClampPulse(INT16_MIN), PWM_MIN_US);
  expect_eq("int16 max",   PwmControl_ClampPulse(INT16_MAX), PWM_MAX_US);
  expect_eq("zero",        PwmControl_ClampPulse(0),         PWM_MIN_US);
  expect_eq("negative",    PwmControl_ClampPulse(-500),      PWM_MIN_US);
}

static void test_slew_toward_target_without_overshoot(void) {
  expect_eq("slew up", PwmControl_SlewToward(1500, 2000, 80), 1580);
  expect_eq("slew down", PwmControl_SlewToward(1500, 1000, 80), 1420);
  expect_eq("slew reaches close target", PwmControl_SlewToward(1500, 1530, 80), 1530);
  expect_eq("slew zero holds", PwmControl_SlewToward(1500, 2000, 0), 1500);
}

static void test_slew_clamps_target_and_current(void) {
  expect_eq("target above max", PwmControl_SlewToward(1500, 2500, 600), 2000);
  expect_eq("target below min", PwmControl_SlewToward(1500, 500, 600), 1000);
  expect_eq("current above max", PwmControl_SlewToward(2500, 1000, 50), 1950);
  expect_eq("current below min", PwmControl_SlewToward(500, 2000, 50), 1050);
}

static void test_timed_slew_caps_stalled_loop_catchup(void) {
  expect_eq("normal 20ms frame",
            PwmControl_TimedSlewToward(1500, 2000, 20, 5, 20),
            1600);
  expect_eq("stalled loop still one capped step",
            PwmControl_TimedSlewToward(1500, 2000, 200, 5, 20),
            1600);
  expect_eq("zero elapsed holds",
            PwmControl_TimedSlewToward(1500, 2000, 0, 5, 20),
            1500);
}

int main(void) {
  test_in_range_unchanged();
  test_clamp_bounds();
  test_clamp_extremes();
  test_slew_toward_target_without_overshoot();
  test_slew_clamps_target_and_current();
  test_timed_slew_caps_stalled_loop_catchup();
  if (g_fails == 0) {
    printf("pwm_control tests: OK\n");
    return 0;
  }
  printf("pwm_control tests: %d FAIL\n", g_fails);
  return 1;
}
