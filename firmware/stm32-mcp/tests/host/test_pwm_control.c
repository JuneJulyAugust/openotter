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

int main(void) {
  test_in_range_unchanged();
  test_clamp_bounds();
  test_clamp_extremes();
  if (g_fails == 0) {
    printf("pwm_control tests: OK\n");
    return 0;
  }
  printf("pwm_control tests: %d FAIL\n", g_fails);
  return 1;
}
