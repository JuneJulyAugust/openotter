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
  /* Counts consecutive valid+new frames since the last invalid. Used by the
   * TOF_BLIND release path so release confidence equals trigger confidence:
   * we require the same number of clean frames to leave BRAKE as we needed
   * to enter it, preventing single-frame release-then-rearm thrash. */
  uint8_t  valid_streak;
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

/* Compile-time guard: callers allocate REV_SAFETY_CTX_STORAGE_BYTES of
 * max-aligned storage; make sure the real struct still fits. Bump the
 * constant in rev_safety.h if this ever fires. */
_Static_assert(sizeof(struct RevSafetyCtx) <= REV_SAFETY_CTX_STORAGE_BYTES,
               "Grow REV_SAFETY_CTX_STORAGE_BYTES to fit RevSafetyCtx");

void RevSafety_GetDefaultConfig(RevSafetyConfig_t *out) {
  if (!out) return;
  out->t_sys_fw_s         = 0.40f;
  out->decel_intercept    = 0.66f;
  out->decel_slope        = 0.87f;
  out->d_margin_rear_m    = 0.30f;
  out->alpha_smoothing    = 0.5f;
  out->release_hold_s     = 0.3f;
  out->v_eps_mps          = 0.05f;
  out->throttle_eps_us    = 30;
  out->stop_speed_eps_mps = 0.05f;
  /* 4 frames at the default 33 ms ranging budget = ~130 ms of sustained
   * sensor failure before declaring the rear blind. Two frames was too
   * sensitive at high reverse speed: brief WRP/SIG/SIGMA bursts on smooth
   * surfaces produced spurious TOF_BLIND brakes well before any obstacle. */
  out->tof_blind_frames   = 4;
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
  ctx->last_valid_frame_ms = 0; /* will be set on first tick call */
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

static bool supervisor_armed(const struct RevSafetyCtx *ctx,
                             const RevSafetyInput_t *in) {
  float v_eps       = ctx->config.v_eps_mps;
  int16_t t_eps     = ctx->config.throttle_eps_us;
  int16_t neutral   = (int16_t)ctx->config.pwm_neutral_us;
  bool moving_back  = in->velocity_mps < -v_eps;
  bool cmd_reverse  = in->throttle_us < (neutral - t_eps);
  return moving_back || cmd_reverse;
}

static void emit_event(struct RevSafetyCtx *ctx,
                       RevSafetyEvent_t *out,
                       bool transition,
                       uint32_t now_ms) {
  if (!out) return;
  memset(out, 0, sizeof(*out));
  out->transition          = transition;
  out->state               = ctx->state;
  out->cause               = ctx->cause;
  out->smoothed_depth_m    = ctx->smoothed_depth_m;
  if (ctx->state == REV_SAFETY_STATE_BRAKE) {
    out->critical_distance_m =
        RevSafety_CriticalDistance(&ctx->config, ctx->latched_speed_mps);
  }
  out->latched_speed_mps    = ctx->latched_speed_mps;
  out->trigger_velocity_mps = ctx->trigger_velocity_mps;
  out->trigger_depth_m      = ctx->trigger_depth_m;
  out->trigger_timestamp_ms = ctx->trigger_timestamp_ms;
  out->seq                  = ctx->seq;

  if (transition) {
    ctx->seq++;
    out->seq = ctx->seq;
    ctx->last_notify_refresh_ms = now_ms;
  } else if (ctx->state == REV_SAFETY_STATE_BRAKE &&
             (now_ms - ctx->last_notify_refresh_ms) >= 1000u) {
    out->notify_refresh = true;
    ctx->last_notify_refresh_ms = now_ms;
  }
}

static void clear_snapshot(struct RevSafetyCtx *ctx) {
  ctx->latched_speed_mps = 0.0f;
  ctx->trigger_velocity_mps = 0.0f;
  ctx->trigger_depth_m = 0.0f;
  ctx->trigger_timestamp_ms = 0u;
}

static void enter_brake(struct RevSafetyCtx *ctx,
                        const RevSafetyInput_t *in,
                        RevSafetyCause_t cause) {
  ctx->state = REV_SAFETY_STATE_BRAKE;
  ctx->cause = cause;
  ctx->latched_speed_mps    = fabsf(in->velocity_mps);
  ctx->trigger_velocity_mps = in->velocity_mps;
  ctx->trigger_depth_m      = ctx->smoothed_depth_m;
  ctx->trigger_timestamp_ms = in->now_ms;
  ctx->release_timer_running = false;
}

void RevSafety_Tick(struct RevSafetyCtx *ctx,
                    const RevSafetyInput_t *in,
                    RevSafetyEvent_t *out) {
  if (!ctx || !in) {
    if (out) memset(out, 0, sizeof(*out));
    return;
  }
  if (ctx->last_valid_frame_ms == 0) ctx->last_valid_frame_ms = in->now_ms;
  RevSafetyState_t prev = ctx->state;

  /* 1. Update smoothed depth and invalid/valid counters */
  if (in->frame_is_new && in->zone_valid) {
    if (!ctx->has_smoothed) {
      ctx->smoothed_depth_m = in->raw_depth_m;
      ctx->has_smoothed     = true;
    } else {
      float a = ctx->config.alpha_smoothing;
      ctx->smoothed_depth_m =
          a * in->raw_depth_m + (1.0f - a) * ctx->smoothed_depth_m;
    }
    ctx->invalid_frame_count = 0;
    if (ctx->valid_streak < 0xFF) ctx->valid_streak++;
    ctx->last_valid_frame_ms = in->now_ms;
  } else if (in->frame_is_new && !in->zone_valid) {
    if (ctx->invalid_frame_count < 0xFF) ctx->invalid_frame_count++;
    ctx->valid_streak = 0;
    ctx->last_valid_frame_ms = in->now_ms; /* frame arrived, just invalid */
  }

  int16_t neutral     = (int16_t)ctx->config.pwm_neutral_us;
  int16_t t_eps       = ctx->config.throttle_eps_us;
  bool    armed       = supervisor_armed(ctx, in);
  bool    forward_cmd = in->throttle_us > (neutral + t_eps);
  bool    frame_stale = (in->now_ms - ctx->last_valid_frame_ms) >
                     ctx->config.frame_gap_ms;

  /* 2. SAFE -> BRAKE transitions (invalid, driver_dead, obstacle) */
  if (ctx->state == REV_SAFETY_STATE_SAFE && armed) {
    if (in->driver_dead) {
      enter_brake(ctx, in, REV_SAFETY_CAUSE_DRIVER_DEAD);
    } else if (frame_stale) {
      enter_brake(ctx, in, REV_SAFETY_CAUSE_FRAME_GAP);
    } else if (ctx->invalid_frame_count >= ctx->config.tof_blind_frames) {
      enter_brake(ctx, in, REV_SAFETY_CAUSE_TOF_BLIND);
    } else if (ctx->has_smoothed) {
      float critical = RevSafety_CriticalDistance(&ctx->config,
                                                  in->velocity_mps);
      if (ctx->smoothed_depth_m <= critical) {
        enter_brake(ctx, in, REV_SAFETY_CAUSE_OBSTACLE);
      }
    }
  } else if (ctx->state != REV_SAFETY_STATE_SAFE) {
    /* BRAKE: evaluate release paths */
    if (in->driver_dead) {
      ctx->cause = REV_SAFETY_CAUSE_DRIVER_DEAD;
      ctx->release_timer_running = false;
    }

    /* (b) Operator forward command drops the latch immediately. */
    if (ctx->cause == REV_SAFETY_CAUSE_DRIVER_DEAD) {
      /* Driver-dead is latched until reboot. */
    } else if (forward_cmd) {
      ctx->state = REV_SAFETY_STATE_SAFE;
      ctx->cause = REV_SAFETY_CAUSE_NONE;
      clear_snapshot(ctx);
      ctx->release_timer_running = false;
    } else {
      /* (a) Genuine clearance with debounce against latched-speed critical.
       * For TOF_BLIND, also require that as many consecutive valid frames
       * have arrived as it took to declare blind in the first place — a
       * single recovered frame is not enough to release. */
      float critical = RevSafety_CriticalDistance(&ctx->config,
                                                  ctx->latched_speed_mps);
      bool clear = ctx->has_smoothed && ctx->smoothed_depth_m > critical &&
                   ctx->invalid_frame_count == 0;
      if (ctx->cause == REV_SAFETY_CAUSE_TOF_BLIND &&
          ctx->valid_streak < ctx->config.tof_blind_frames) {
        clear = false;
      }
      if (clear) {
        if (!ctx->release_timer_running) {
          ctx->release_timer_running = true;
          ctx->release_start_ms      = in->now_ms;
        } else {
          uint32_t held = in->now_ms - ctx->release_start_ms;
          uint32_t need_ms =
              (uint32_t)(ctx->config.release_hold_s * 1000.0f);
          if (held >= need_ms) {
            ctx->state = REV_SAFETY_STATE_SAFE;
            ctx->cause = REV_SAFETY_CAUSE_NONE;
            clear_snapshot(ctx);
            ctx->release_timer_running = false;
          }
        }
      } else {
        ctx->release_timer_running = false;
      }
    }
  }

  emit_event(ctx, out, prev != ctx->state, in->now_ms);
}

bool RevSafety_IsBraking(const RevSafetyCtx *ctx) {
  return ctx && ctx->state == REV_SAFETY_STATE_BRAKE;
}

void RevSafety_Disarm(RevSafetyCtx *ctx) {
  if (!ctx) return;
  ctx->state = REV_SAFETY_STATE_SAFE;
  ctx->cause = REV_SAFETY_CAUSE_NONE;
  clear_snapshot(ctx);
  ctx->release_timer_running = false;
}
