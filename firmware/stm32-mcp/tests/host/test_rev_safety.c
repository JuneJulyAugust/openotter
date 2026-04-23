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

static void test_obstacle_triggers_brake(void) {
  RevSafetyConfig_t cfg;  RevSafety_GetDefaultConfig(&cfg);
  RevSafetyCtx *ctx = (RevSafetyCtx *)malloc(RevSafety_ContextSize());
  RevSafety_Init(ctx, &cfg);
  RevSafetyEvent_t ev;

  /* Clear depth, reversing at 1 m/s */
  RevSafetyInput_t in = make_input(-1.0f, 1400, 2.0f, true, 100);
  RevSafety_Tick(ctx, &in, &ev);
  expect_state("clear SAFE", ev.state, REV_SAFETY_STATE_SAFE);

  /* Wall appears at 0.30 m; criticalDistance(1.0) ~ 0.87 m -> BRAKE */
  in = make_input(-1.0f, 1400, 0.30f, true, 200);
  RevSafety_Tick(ctx, &in, &ev);
  /* Need one more tick so EMA pulls smoothed below threshold.
   * alpha=0.5, prev=2.0, raw=0.30 -> smoothed=1.15 (> 0.87, still SAFE) */
  expect_state("one tick still SAFE", ev.state, REV_SAFETY_STATE_SAFE);

  in = make_input(-1.0f, 1400, 0.30f, true, 300);
  RevSafety_Tick(ctx, &in, &ev);
  /* smoothed = 0.5*0.30 + 0.5*1.15 = 0.725 < 0.87 -> BRAKE obstacle */
  expect_state("sustained obstacle BRAKE", ev.state, REV_SAFETY_STATE_BRAKE);
  expect_cause("obstacle cause", ev.cause, REV_SAFETY_CAUSE_OBSTACLE);
  expect_near("latched speed", ev.latched_speed_mps, 1.0f, 1e-3f);
}

static void test_release_requires_continuous_clearance(void) {
  RevSafetyConfig_t cfg;  RevSafety_GetDefaultConfig(&cfg);
  RevSafetyCtx *ctx = (RevSafetyCtx *)malloc(RevSafety_ContextSize());
  RevSafety_Init(ctx, &cfg);
  RevSafetyEvent_t ev;

  /* Drive it straight into BRAKE via obstacle (seed smoothed low). */
  RevSafetyInput_t in = make_input(-0.5f, 1400, 0.20f, true, 0);
  for (uint32_t t = 0; t <= 200; t += 50) {
    in.now_ms = t;
    RevSafety_Tick(ctx, &in, &ev);
  }
  expect_state("setup BRAKE", ev.state, REV_SAFETY_STATE_BRAKE);

  /* Clearance appears but only for 150 ms -> still BRAKE */
  in = make_input(0.0f, 1400, 2.0f, true, 300);
  RevSafety_Tick(ctx, &in, &ev);
  in.now_ms = 450;
  RevSafety_Tick(ctx, &in, &ev);
  expect_state("150ms clear still BRAKE", ev.state, REV_SAFETY_STATE_BRAKE);

  /* 300 ms continuous clearance -> SAFE */
  in.now_ms = 600;
  RevSafety_Tick(ctx, &in, &ev);
  expect_state("300ms clear SAFE", ev.state, REV_SAFETY_STATE_SAFE);
}

static void test_forward_command_releases_latch(void) {
  RevSafetyConfig_t cfg;  RevSafety_GetDefaultConfig(&cfg);
  RevSafetyCtx *ctx = (RevSafetyCtx *)malloc(RevSafety_ContextSize());
  RevSafety_Init(ctx, &cfg);
  RevSafetyEvent_t ev;

  RevSafetyInput_t in = make_input(-0.5f, 1400, 0.20f, true, 0);
  for (uint32_t t = 0; t <= 200; t += 50) {
    in.now_ms = t;
    RevSafety_Tick(ctx, &in, &ev);
  }
  expect_state("setup BRAKE", ev.state, REV_SAFETY_STATE_BRAKE);

  /* Operator commands forward (throttle > neutral + throttle_eps). Depth
   * still close but vehicle is no longer reversing. */
  in = make_input(0.0f, 1600, 0.20f, true, 300);
  RevSafety_Tick(ctx, &in, &ev);
  expect_state("forward cmd SAFE", ev.state, REV_SAFETY_STATE_SAFE);
}

int main(void) {
  test_critical_distance_reverse_table();
  test_critical_distance_zero_speed();
  test_ema_smoothing_converges();
  test_invalid_tolerates_one_then_brakes_on_two();
  test_obstacle_triggers_brake();
  test_release_requires_continuous_clearance();
  test_forward_command_releases_latch();
  if (g_fails == 0) {
    printf("rev_safety tests: OK\n");
    return 0;
  }
  printf("rev_safety tests: %d FAIL\n", g_fails);
  return 1;
}