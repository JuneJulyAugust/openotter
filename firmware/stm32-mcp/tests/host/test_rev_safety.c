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

static void expect_state(const char *label,
                         RevSafetyState_t got,
                         RevSafetyState_t want) {
  if (got != want) {
    fprintf(stderr, "FAIL %s: state got %d want %d\n", label, got, want);
    g_fails++;
  }
}

static void expect_cause(const char *label,
                         RevSafetyCause_t got,
                         RevSafetyCause_t want) {
  if (got != want) {
    fprintf(stderr, "FAIL %s: cause got %d want %d\n", label, got, want);
    g_fails++;
  }
}

static RevSafetyInput_t make_input(float v, int16_t throttle, float depth,
                                   bool valid, uint32_t now_ms) {
  RevSafetyInput_t in = {0};
  in.velocity_mps  = v;
  in.throttle_us   = throttle;
  in.raw_depth_m   = depth;
  in.zone_valid    = valid;
  in.frame_is_new  = true;
  in.driver_dead   = false;
  in.now_ms        = now_ms;
  return in;
}

static void test_ema_smoothing_converges(void) {
  RevSafetyConfig_t cfg;  RevSafety_GetDefaultConfig(&cfg);
  RevSafetyCtx *ctx = (RevSafetyCtx *)malloc(RevSafety_ContextSize());
  RevSafety_Init(ctx, &cfg);

  RevSafetyEvent_t ev;
  /* disarmed (forward motion): supervisor still updates smoothed depth */
  RevSafetyInput_t in = make_input(0.0f, 1500, 1.0f, true, 100);
  RevSafety_Tick(ctx, &in, &ev);
  /* First sample: smoothed = raw */
  expect_near("ema first sample", ev.smoothed_depth_m, 1.0f, 1e-3f);

  in.raw_depth_m = 2.0f;
  in.now_ms      = 200;
  RevSafety_Tick(ctx, &in, &ev);
  /* alpha=0.5: smoothed = 0.5*2.0 + 0.5*1.0 = 1.5 */
  expect_near("ema second sample", ev.smoothed_depth_m, 1.5f, 1e-3f);
}

static void test_invalid_tolerates_one_then_brakes_on_two(void) {
  RevSafetyConfig_t cfg;  RevSafety_GetDefaultConfig(&cfg);
  RevSafetyCtx *ctx = (RevSafetyCtx *)malloc(RevSafety_ContextSize());
  RevSafety_Init(ctx, &cfg);

  RevSafetyEvent_t ev;
  /* Arm the supervisor: reverse at 0.5 m/s with clear depth */
  RevSafetyInput_t in = make_input(-0.5f, 1400, 2.0f, true, 100);
  RevSafety_Tick(ctx, &in, &ev);
  expect_state("clear depth SAFE", ev.state, REV_SAFETY_STATE_SAFE);

  /* One invalid frame — still SAFE */
  in = make_input(-0.5f, 1400, 0.0f, false, 300);
  RevSafety_Tick(ctx, &in, &ev);
  expect_state("one invalid SAFE", ev.state, REV_SAFETY_STATE_SAFE);

  /* Second invalid in a row — BRAKE with TOF_BLIND */
  in = make_input(-0.5f, 1400, 0.0f, false, 600);
  RevSafety_Tick(ctx, &in, &ev);
  expect_state("two invalid BRAKE", ev.state, REV_SAFETY_STATE_BRAKE);
  expect_cause("two invalid cause", ev.cause, REV_SAFETY_CAUSE_TOF_BLIND);
}

int main(void) {
  test_critical_distance_reverse_table();
  test_critical_distance_zero_speed();
  test_ema_smoothing_converges();
  test_invalid_tolerates_one_then_brakes_on_two();
  if (g_fails == 0) {
    printf("rev_safety tests: OK\n");
    return 0;
  }
  printf("rev_safety tests: %d FAIL\n", g_fails);
  return 1;
}