/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * Reverse collision-avoidance safety supervisor. See
 *   docs/superpowers/specs/2026-04-23-stm32-reverse-safety-and-protocol-design.md
 *
 * HAL-free. All timing passed in explicitly by the caller. Context struct is
 * private to this file; callers hold a RevSafetyCtx * that points to their
 * own storage of size RevSafety_ContextSize().
 */

#include "rev_safety.h"

#include <math.h>
#include <string.h>

struct RevSafetyCtx {
  RevSafetyConfig_t config;
  RevSafetyState_t  state;
  RevSafetyCause_t  cause;

  float    smoothed_depth_m;
  bool     has_smoothed;
  uint8_t  invalid_frame_count;
  uint32_t last_valid_frame_ms;

  /* Latched on transition to BRAKE */
  float    latched_speed_mps;
  float    trigger_velocity_mps;
  float    trigger_depth_m;
  uint32_t trigger_timestamp_ms;

  /* Release timer (genuine clearance debounce) */
  uint32_t release_start_ms;
  bool     release_timer_running;

  /* Notify bookkeeping */
  uint32_t seq;
  uint32_t last_notify_refresh_ms;
};

void RevSafety_GetDefaultConfig(RevSafetyConfig_t *out) {
  if (!out) return;
  out->t_sys_fw_s         = 0.34f;
  out->decel_intercept    = 0.66f;
  out->decel_slope        = 0.87f;
  out->d_margin_rear_m    = 0.17f;
  out->alpha_smoothing    = 0.5f;
  out->release_hold_s     = 0.3f;
  out->v_eps_mps          = 0.05f;
  out->throttle_eps_us    = 30;
  out->stop_speed_eps_mps = 0.05f;
  out->tof_blind_frames   = 2;
  out->frame_gap_ms       = 500u;
  out->pwm_neutral_us     = 1500u;
}

uint32_t RevSafety_ContextSize(void) {
  return (uint32_t)sizeof(struct RevSafetyCtx);
}

void RevSafety_Init(RevSafetyCtx *ctx, const RevSafetyConfig_t *config) {
  if (!ctx) return;
  memset(ctx, 0, sizeof(*ctx));
  if (config) ctx->config = *config;
  else        RevSafety_GetDefaultConfig(&ctx->config);
  ctx->state = REV_SAFETY_STATE_SAFE;
  ctx->cause = REV_SAFETY_CAUSE_NONE;
}

/* Exact integral: stopping(v) = v/k - (a0/k^2) * ln(1 + k*v/a0). Falls back
 * to v^2 / (2*a0) when k is near zero (constant deceleration). */
static float stopping_distance(const RevSafetyConfig_t *c, float v) {
  if (v <= 0.0f) return 0.0f;
  float k  = c->decel_slope;
  float a0 = c->decel_intercept;
  if (fabsf(k) < 1e-4f) return v * v / (2.0f * a0);
  return v / k - (a0 / (k * k)) * logf(1.0f + k * v / a0);
}

float RevSafety_CriticalDistance(const RevSafetyConfig_t *config, float v) {
  if (!config) return 0.0f;
  float speed = fabsf(v);
  return speed * config->t_sys_fw_s
       + stopping_distance(config, speed)
       + config->d_margin_rear_m;
}

/* Stubs filled in by later tasks. */
void RevSafety_Tick(RevSafetyCtx *ctx,
                    const RevSafetyInput_t *in,
                    RevSafetyEvent_t *out) {
  (void)ctx; (void)in;
  if (out) memset(out, 0, sizeof(*out));
}

bool RevSafety_IsBraking(const RevSafetyCtx *ctx) {
  return ctx && ctx->state == REV_SAFETY_STATE_BRAKE;
}

void RevSafety_Disarm(RevSafetyCtx *ctx) {
  if (!ctx) return;
  ctx->state = REV_SAFETY_STATE_SAFE;
  ctx->cause = REV_SAFETY_CAUSE_NONE;
  ctx->latched_speed_mps = 0.0f;
  ctx->release_timer_running = false;
}