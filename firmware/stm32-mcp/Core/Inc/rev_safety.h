/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef REV_SAFETY_H
#define REV_SAFETY_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  REV_SAFETY_STATE_SAFE  = 0,
  REV_SAFETY_STATE_BRAKE = 1,
} RevSafetyState_t;

typedef enum {
  REV_SAFETY_CAUSE_NONE        = 0,
  REV_SAFETY_CAUSE_OBSTACLE    = 1,
  REV_SAFETY_CAUSE_TOF_BLIND   = 2,
  REV_SAFETY_CAUSE_FRAME_GAP   = 3,
  REV_SAFETY_CAUSE_DRIVER_DEAD = 4,
} RevSafetyCause_t;

typedef struct {
  float    t_sys_fw_s;          /* reaction latency, s; default 0.34 */
  float    decel_intercept;     /* a0, m/s^2; default 0.66 */
  float    decel_slope;         /* k, 1/s; default 0.87 */
  float    d_margin_rear_m;     /* default 0.17 */
  float    alpha_smoothing;     /* EMA weight, default 0.5 */
  float    release_hold_s;      /* default 0.3 */
  float    v_eps_mps;           /* default 0.05 */
  int16_t  throttle_eps_us;     /* default 30 */
  float    stop_speed_eps_mps;  /* default 0.05 */
  uint8_t  tof_blind_frames;    /* default 2 */
  uint32_t frame_gap_ms;        /* default 500 */
  uint16_t pwm_neutral_us;      /* default 1500 */
} RevSafetyConfig_t;

typedef struct {
  float        velocity_mps;       /* signed; negative = reversing */
  int16_t      throttle_us;        /* commanded throttle pulse width */
  float        raw_depth_m;        /* center-zone range in meters; ignored if !zone_valid */
  bool         zone_valid;         /* true when VL53L1 status == 0 */
  bool         frame_is_new;       /* true when a new seq arrived this tick */
  bool         driver_dead;        /* TofL1_ERR_DRIVER_DEAD latched */
  uint32_t     now_ms;             /* HAL_GetTick() or test clock */
} RevSafetyInput_t;

typedef struct {
  bool             transition;       /* true on the tick where state changed */
  bool             notify_refresh;   /* true once per 1 s while BRAKE */
  RevSafetyState_t state;
  RevSafetyCause_t cause;
  float            smoothed_depth_m;
  float            critical_distance_m;
  float            latched_speed_mps;
  float            trigger_velocity_mps;
  float            trigger_depth_m;
  uint32_t         trigger_timestamp_ms;
  uint32_t         seq;              /* increments on every transition */
} RevSafetyEvent_t;

typedef struct RevSafetyCtx RevSafetyCtx;

void RevSafety_GetDefaultConfig(RevSafetyConfig_t *out);

/* Allocate-and-init is avoided; caller provides storage. */
void RevSafety_Init(RevSafetyCtx *ctx, const RevSafetyConfig_t *config);

void RevSafety_Tick(RevSafetyCtx *ctx,
                    const RevSafetyInput_t *in,
                    RevSafetyEvent_t *out);

/* True when the supervisor currently wants to veto reverse throttle. */
bool RevSafety_IsBraking(const RevSafetyCtx *ctx);

/* Force SAFE (clears latch). Called on mode transition to Debug. */
void RevSafety_Disarm(RevSafetyCtx *ctx);

/* Critical distance for a given speed magnitude. Pure function of config.
 * Exposed for parity tests against the iOS fixture. */
float RevSafety_CriticalDistance(const RevSafetyConfig_t *config, float speed_mps);

/* Opaque storage size so callers can reserve memory without seeing the
 * internals. Implementation lives in rev_safety.c. */
uint32_t RevSafety_ContextSize(void);

#ifdef __cplusplus
}
#endif

#endif /* REV_SAFETY_H */