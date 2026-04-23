# STM32 Reverse Safety Supervisor & iOS↔Firmware Protocol — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a firmware-side reverse collision-avoidance safety supervisor on the STM32, extend the BLE protocol to carry iOS velocity into the MCU and firmware emergency state out to iOS, and enforce a Drive/Debug mode split that locks the ToF sensor to the safety-critical configuration during normal operation.

**Architecture:** A new HAL-free C module `rev_safety` implements the supervisor (critical-distance math mirrored from iOS, state machine with latched speed, invalid-frame / frame-gap watchdogs) and is host-unit-tested via the existing `tests/host/` harness. The command path in `ble_app.c` is refactored so PWM is applied once per main-loop tick after arbitration, not directly from the BLE event handler. Two new GATT characteristics (0xFE43 safety, 0xFE44 mode) are added to service 0xFE40. The existing ToF service 0xFE60 gates config writes and frame notifications on mode. On the iOS side, `STM32BleManager` extends the command payload to 6 B, subscribes to 0xFE43, writes 0xFE44 on connect, and surfaces firmware safety events as a new model parallel to the existing iOS `SafetyBrakeRecord`.

**Tech Stack:** C11 (firmware), STM32Cube HAL, BlueNRG-MS, gcc host tests; Swift, CoreBluetooth, Combine (iOS); XCTest.

**Spec:** `docs/superpowers/specs/2026-04-23-stm32-reverse-safety-and-protocol-design.md`
**iOS forward supervisor reference:** `openotter-ios/Sources/Planner/Safety/DESIGN.md`

---

## File Map

### Firmware — new
- `firmware/stm32-mcp/Core/Inc/rev_safety.h` — public API, config struct, state/event enums
- `firmware/stm32-mcp/Core/Src/rev_safety.c` — state machine, math, EMA, watchdogs
- `firmware/stm32-mcp/tests/host/test_rev_safety.c` — host unit tests

### Firmware — modified
- `firmware/stm32-mcp/Core/Inc/tof_l1.h` — add `TOF_L1_ERR_LOCKED_IN_DRIVE = 11`
- `firmware/stm32-mcp/Core/Src/tof_l1.c` — no logic change (error code is enum-only)
- `firmware/stm32-mcp/Core/Inc/ble_app.h` — new UUIDs, new payload types, operating mode enum, extended PWM-apply API
- `firmware/stm32-mcp/Core/Src/ble_app.c` — 6 B command payload, FE43/FE44 char registration, mode state, deferred PWM apply, notify publisher
- `firmware/stm32-mcp/Core/Src/ble_tof.c` — mode-gated config writes and frame notifications
- `firmware/stm32-mcp/Core/Src/main.c` — init + tick wiring for `rev_safety`
- `firmware/stm32-mcp/tests/host/Makefile` — new test target
- `firmware/stm32-mcp/CHANGELOG.md` — release entry

### iOS — new
- `openotter-ios/Sources/Planner/Safety/FirmwareSafetyEvent.swift` — event model + 18 B parser
- `openotter-ios/Tests/Planner/FirmwareSafetyEventTests.swift` — parser tests

### iOS — modified
- `openotter-ios/Sources/Capture/STM32BleManager.swift` — 6 B sendCommand, FE43 subscribe, FE44 mode write, UUID constants
- `openotter-ios/Sources/Capture/STM32ControlViewModel.swift` — pass velocity into sendCommand
- `openotter-ios/Sources/Capture/SelfDrivingViewModel.swift` — pass velocity into sendCommand
- `openotter-ios/Sources/Capture/RaspberryPiControlViewModel.swift` — RPi path untouched; Pi bridge is a separate backend
- `openotter-ios/CHANGELOG.md` — release entry

---

## Task 1: Add `TOF_L1_ERR_LOCKED_IN_DRIVE` enum value

**Files:**
- Modify: `firmware/stm32-mcp/Core/Inc/tof_l1.h`

Rationale: `ble_tof.c` will return this code from `apply_config_write` when the MCU is in Drive mode (Task 11). Defining the enum value first keeps later diffs small.

- [ ] **Step 1: Edit the enum**

In `firmware/stm32-mcp/Core/Inc/tof_l1.h`, add after `TOF_L1_ERR_DRIVER_DEAD = 10`:

```c
  /* Config write rejected because MCU is in Drive mode and the safety
   * config is locked. Sensor is still running with the safety config. */
  TOF_L1_ERR_LOCKED_IN_DRIVE = 11,
```

- [ ] **Step 2: Verify it compiles**

Run:

```
cd firmware/stm32-mcp && ./build.sh
```

Expected: build succeeds with no warnings (enum-only change; no user yet).

- [ ] **Step 3: Commit**

```
git add firmware/stm32-mcp/Core/Inc/tof_l1.h
git commit -m "tof: add TOF_L1_ERR_LOCKED_IN_DRIVE status code"
```

---

## Task 2: Create `rev_safety.h` public API

**Files:**
- Create: `firmware/stm32-mcp/Core/Inc/rev_safety.h`

The header is the contract consumed by host tests, `main.c`, and `ble_app.c`. All state is owned by a single context struct passed by pointer; no global-singleton inside the module, so host tests can instantiate multiple contexts.

- [ ] **Step 1: Write the header**

Create `firmware/stm32-mcp/Core/Inc/rev_safety.h`:

```c
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
```

- [ ] **Step 2: Confirm the header compiles on host**

Run:

```
cd firmware/stm32-mcp/tests/host && cc -std=c11 -Wall -Wextra -Werror -I ../../Core/Inc -fsyntax-only -x c ../../Core/Inc/rev_safety.h
```

Expected: no output (success).

- [ ] **Step 3: Commit**

```
git add firmware/stm32-mcp/Core/Inc/rev_safety.h
git commit -m "rev_safety: public header (API, config, state enums)"
```

---

## Task 3: Skeleton `rev_safety.c` plus critical-distance parity test

This task gets a compilable module in place and proves the critical-distance formula agrees with the iOS table (spec §3.3).

**Files:**
- Create: `firmware/stm32-mcp/Core/Src/rev_safety.c`
- Create: `firmware/stm32-mcp/tests/host/test_rev_safety.c`
- Modify: `firmware/stm32-mcp/tests/host/Makefile`

- [ ] **Step 1: Write the failing test**

Create `firmware/stm32-mcp/tests/host/test_rev_safety.c`:

```c
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

  expect_near("cd(0.3)", RevSafety_CriticalDistance(&cfg, 0.3f), 0.32f, 0.01f);
  expect_near("cd(0.5)", RevSafety_CriticalDistance(&cfg, 0.5f), 0.45f, 0.01f);
  expect_near("cd(1.0)", RevSafety_CriticalDistance(&cfg, 1.0f), 0.87f, 0.01f);
  expect_near("cd(1.5)", RevSafety_CriticalDistance(&cfg, 1.5f), 1.37f, 0.01f);
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
```

- [ ] **Step 2: Extend the test Makefile**

Edit `firmware/stm32-mcp/tests/host/Makefile`, change the `TESTS` line to:

```
TESTS = test_tof_l1_roi test_rev_safety
```

and add the recipe below the existing `test_tof_l1_roi` recipe:

```
test_rev_safety: test_rev_safety.c ../../Core/Src/rev_safety.c ../../Core/Inc/rev_safety.h
	$(CC) $(CFLAGS) $(INCDIR) test_rev_safety.c ../../Core/Src/rev_safety.c -o $@ -lm
```

- [ ] **Step 3: Run test to verify it fails (file missing)**

Run:

```
cd firmware/stm32-mcp/tests/host && make test_rev_safety
```

Expected: link error — `rev_safety.c` does not exist yet.

- [ ] **Step 4: Write minimal implementation**

Create `firmware/stm32-mcp/Core/Src/rev_safety.c`:

```c
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
```

- [ ] **Step 5: Run test to verify it passes**

Run:

```
cd firmware/stm32-mcp/tests/host && make test_rev_safety && ./test_rev_safety
```

Expected output: `rev_safety tests: OK` and process exit code 0.

- [ ] **Step 6: Verify firmware build still works**

Run:

```
cd firmware/stm32-mcp && ./build.sh
```

Expected: build succeeds. `rev_safety.c` is not yet referenced by any target source, but make sure it compiles cleanly when added later — nothing to assert here beyond build green.

- [ ] **Step 7: Commit**

```
git add firmware/stm32-mcp/Core/Inc/rev_safety.h \
        firmware/stm32-mcp/Core/Src/rev_safety.c \
        firmware/stm32-mcp/tests/host/test_rev_safety.c \
        firmware/stm32-mcp/tests/host/Makefile
git commit -m "rev_safety: skeleton module + critical-distance parity tests"
```

---

## Task 4: EMA smoothing and invalid-frame policy

Implements spec §3.4 (A): hold last valid smoothed depth; after `tof_blind_frames` consecutive invalid frames, force BRAKE with cause `TOF_BLIND`.

**Files:**
- Modify: `firmware/stm32-mcp/Core/Src/rev_safety.c`
- Modify: `firmware/stm32-mcp/tests/host/test_rev_safety.c`

- [ ] **Step 1: Write failing tests**

Append to `test_rev_safety.c` before `main()`:

```c
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
```

Register them in `main()` just before the `if (g_fails == 0)` block:

```c
  test_ema_smoothing_converges();
  test_invalid_tolerates_one_then_brakes_on_two();
```

- [ ] **Step 2: Run the tests and watch them fail**

Run:

```
cd firmware/stm32-mcp/tests/host && make test_rev_safety && ./test_rev_safety
```

Expected: at least two failures because `RevSafety_Tick` is still a stub.

- [ ] **Step 3: Implement the smoothing + invalid-frame logic**

Replace the stub `RevSafety_Tick` in `rev_safety.c` with:

```c
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
  out->critical_distance_m =
      RevSafety_CriticalDistance(&ctx->config, ctx->latched_speed_mps);
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
  RevSafetyState_t prev = ctx->state;

  /* 1. Smoothed depth update (invalid-frame handling) */
  if (in->zone_valid) {
    if (!ctx->has_smoothed) {
      ctx->smoothed_depth_m = in->raw_depth_m;
      ctx->has_smoothed     = true;
    } else {
      float a = ctx->config.alpha_smoothing;
      ctx->smoothed_depth_m =
          a * in->raw_depth_m + (1.0f - a) * ctx->smoothed_depth_m;
    }
    ctx->invalid_frame_count = 0;
    ctx->last_valid_frame_ms = in->now_ms;
  } else {
    if (ctx->invalid_frame_count < 0xFF) ctx->invalid_frame_count++;
  }

  /* 2. Invalid-frame policy while armed */
  if (supervisor_armed(ctx, in) &&
      ctx->invalid_frame_count >= ctx->config.tof_blind_frames &&
      ctx->state != REV_SAFETY_STATE_BRAKE) {
    enter_brake(ctx, in, REV_SAFETY_CAUSE_TOF_BLIND);
  }

  emit_event(ctx, out, prev != ctx->state, in->now_ms);
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run:

```
cd firmware/stm32-mcp/tests/host && make test_rev_safety && ./test_rev_safety
```

Expected: `rev_safety tests: OK`.

- [ ] **Step 5: Commit**

```
git add firmware/stm32-mcp/Core/Src/rev_safety.c \
        firmware/stm32-mcp/tests/host/test_rev_safety.c
git commit -m "rev_safety: EMA smoothing + invalid-frame brake policy"
```

---

## Task 5: Obstacle detection and symmetric release

Implements spec §3.3 release rules and the obstacle trigger. `supervisor_armed` was added in Task 4; this task adds the obstacle branch and the two release paths (genuine clearance with `release_hold_s` debounce, and operator forward command).

**Files:**
- Modify: `firmware/stm32-mcp/Core/Src/rev_safety.c`
- Modify: `firmware/stm32-mcp/tests/host/test_rev_safety.c`

- [ ] **Step 1: Write failing tests**

Append to `test_rev_safety.c` before `main()`:

```c
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
```

Register in `main()`:

```c
  test_obstacle_triggers_brake();
  test_release_requires_continuous_clearance();
  test_forward_command_releases_latch();
```

- [ ] **Step 2: Watch the tests fail**

Run:

```
cd firmware/stm32-mcp/tests/host && make test_rev_safety && ./test_rev_safety
```

Expected: the three new tests fail.

- [ ] **Step 3: Implement obstacle trigger and release logic**

In `rev_safety.c`, replace the body of `RevSafety_Tick` (the part after step 1's invalid-frame policy block) with the fuller version below. Use this entire function body in place of the previous one:

```c
void RevSafety_Tick(struct RevSafetyCtx *ctx,
                    const RevSafetyInput_t *in,
                    RevSafetyEvent_t *out) {
  if (!ctx || !in) {
    if (out) memset(out, 0, sizeof(*out));
    return;
  }
  RevSafetyState_t prev = ctx->state;

  /* 1. Update smoothed depth and invalid counter */
  if (in->zone_valid) {
    if (!ctx->has_smoothed) {
      ctx->smoothed_depth_m = in->raw_depth_m;
      ctx->has_smoothed     = true;
    } else {
      float a = ctx->config.alpha_smoothing;
      ctx->smoothed_depth_m =
          a * in->raw_depth_m + (1.0f - a) * ctx->smoothed_depth_m;
    }
    ctx->invalid_frame_count = 0;
    ctx->last_valid_frame_ms = in->now_ms;
  } else if (ctx->invalid_frame_count < 0xFF) {
    ctx->invalid_frame_count++;
  }

  int16_t neutral     = (int16_t)ctx->config.pwm_neutral_us;
  int16_t t_eps       = ctx->config.throttle_eps_us;
  bool    armed       = supervisor_armed(ctx, in);
  bool    forward_cmd = in->throttle_us > (neutral + t_eps);

  /* 2. SAFE -> BRAKE transitions (invalid, driver_dead, obstacle) */
  if (ctx->state == REV_SAFETY_STATE_SAFE) {
    if (armed && in->driver_dead) {
      enter_brake(ctx, in, REV_SAFETY_CAUSE_DRIVER_DEAD);
    } else if (armed &&
               ctx->invalid_frame_count >= ctx->config.tof_blind_frames) {
      enter_brake(ctx, in, REV_SAFETY_CAUSE_TOF_BLIND);
    } else if (armed && ctx->has_smoothed) {
      float critical = RevSafety_CriticalDistance(&ctx->config,
                                                  in->velocity_mps);
      if (ctx->smoothed_depth_m <= critical) {
        enter_brake(ctx, in, REV_SAFETY_CAUSE_OBSTACLE);
      }
    }
  } else {
    /* BRAKE: evaluate release paths */

    /* (b) Operator forward command drops the latch immediately. */
    if (forward_cmd) {
      ctx->state = REV_SAFETY_STATE_SAFE;
      ctx->cause = REV_SAFETY_CAUSE_NONE;
      ctx->latched_speed_mps    = 0.0f;
      ctx->release_timer_running = false;
    } else {
      /* (a) Genuine clearance with debounce against latched-speed critical. */
      float critical = RevSafety_CriticalDistance(&ctx->config,
                                                  ctx->latched_speed_mps);
      bool clear = ctx->has_smoothed && ctx->smoothed_depth_m > critical &&
                   ctx->invalid_frame_count == 0;
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
            ctx->latched_speed_mps    = 0.0f;
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
```

- [ ] **Step 4: Watch the tests pass**

Run:

```
cd firmware/stm32-mcp/tests/host && make test_rev_safety && ./test_rev_safety
```

Expected: `rev_safety tests: OK`.

- [ ] **Step 5: Commit**

```
git add firmware/stm32-mcp/Core/Src/rev_safety.c \
        firmware/stm32-mcp/tests/host/test_rev_safety.c
git commit -m "rev_safety: obstacle trigger + symmetric release rules"
```

---

## Task 6: Frame-gap watchdog + `driver_dead` brake

Implements spec §3.4 (B). Frame-gap watchdog braces the supervisor against ToF driver hangs (no new seq for > `frame_gap_ms`) and surfaces `TofL1_ERR_DRIVER_DEAD` as a permanent BRAKE cause.

**Files:**
- Modify: `firmware/stm32-mcp/Core/Src/rev_safety.c`
- Modify: `firmware/stm32-mcp/tests/host/test_rev_safety.c`

- [ ] **Step 1: Write failing tests**

Append to `test_rev_safety.c`:

```c
static void test_frame_gap_watchdog(void) {
  RevSafetyConfig_t cfg;  RevSafety_GetDefaultConfig(&cfg);
  RevSafetyCtx *ctx = (RevSafetyCtx *)malloc(RevSafety_ContextSize());
  RevSafety_Init(ctx, &cfg);
  RevSafetyEvent_t ev;

  /* Prime a valid frame at t=0, reversing. */
  RevSafetyInput_t in = make_input(-0.5f, 1400, 2.0f, true, 0);
  RevSafety_Tick(ctx, &in, &ev);
  expect_state("primed SAFE", ev.state, REV_SAFETY_STATE_SAFE);

  /* Now simulate frame-gap: caller marks frame_is_new = false and keeps
   * tickling the supervisor with the same inputs (raw_depth/zone_valid
   * are effectively stale — supervisor must not consume them). */
  in.frame_is_new = false;
  in.now_ms       = 400; /* 400 ms gap, still under threshold */
  RevSafety_Tick(ctx, &in, &ev);
  expect_state("400ms gap SAFE", ev.state, REV_SAFETY_STATE_SAFE);

  in.now_ms = 600;  /* 600 ms gap > 500 ms threshold */
  RevSafety_Tick(ctx, &in, &ev);
  expect_state("600ms gap BRAKE", ev.state, REV_SAFETY_STATE_BRAKE);
  expect_cause("frame gap cause", ev.cause, REV_SAFETY_CAUSE_FRAME_GAP);

  /* New valid frame clears smoothed invalid counter but not instantly the
   * state — release still needs debounce. Confirm recovery path: clear
   * depth for 300 ms. */
  in = make_input(-0.5f, 1400, 2.0f, true, 700);
  RevSafety_Tick(ctx, &in, &ev);
  in.now_ms = 1100;
  RevSafety_Tick(ctx, &in, &ev);
  expect_state("post-gap SAFE", ev.state, REV_SAFETY_STATE_SAFE);
}

static void test_driver_dead_brakes(void) {
  RevSafetyConfig_t cfg;  RevSafety_GetDefaultConfig(&cfg);
  RevSafetyCtx *ctx = (RevSafetyCtx *)malloc(RevSafety_ContextSize());
  RevSafety_Init(ctx, &cfg);
  RevSafetyEvent_t ev;

  RevSafetyInput_t in = make_input(-0.3f, 1400, 2.0f, true, 0);
  in.driver_dead = true;
  RevSafety_Tick(ctx, &in, &ev);
  expect_state("driver_dead BRAKE", ev.state, REV_SAFETY_STATE_BRAKE);
  expect_cause("driver_dead cause", ev.cause, REV_SAFETY_CAUSE_DRIVER_DEAD);
}
```

Register in `main()`:

```c
  test_frame_gap_watchdog();
  test_driver_dead_brakes();
```

- [ ] **Step 2: Watch them fail**

Run: `make test_rev_safety && ./test_rev_safety`
Expected: `test_frame_gap_watchdog` fails because frame-gap logic doesn't exist yet.

- [ ] **Step 3: Add frame-gap check to `RevSafety_Tick`**

In `rev_safety.c`, in step 1 of `RevSafety_Tick` (where `zone_valid` is handled), track the last time a new frame arrived. Change the smoothed-depth update block to:

```c
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
    ctx->last_valid_frame_ms = in->now_ms;
  } else if (in->frame_is_new && !in->zone_valid) {
    if (ctx->invalid_frame_count < 0xFF) ctx->invalid_frame_count++;
    ctx->last_valid_frame_ms = in->now_ms; /* frame arrived, just invalid */
  }
```

Then insert, after the `armed`/`forward_cmd` computation but before the SAFE→BRAKE decision tree:

```c
  bool frame_stale = (in->now_ms - ctx->last_valid_frame_ms) >
                     ctx->config.frame_gap_ms;
```

Update the SAFE→BRAKE block to respect the frame-gap cause. Replace that block with:

```c
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
  }
```

Note: the `last_valid_frame_ms` initializer is zero, which would falsely trip the frame-gap watchdog at boot before any frame arrives. Ensure `RevSafety_Init` seeds it to a non-zero sentinel by adding one line:

```c
  ctx->last_valid_frame_ms = 0; /* will be set on first tick call */
```

Change the first-call behavior in `RevSafety_Tick` by adding at the top (before step 1):

```c
  if (ctx->last_valid_frame_ms == 0) ctx->last_valid_frame_ms = in->now_ms;
```

- [ ] **Step 4: Watch the tests pass**

Run: `make test_rev_safety && ./test_rev_safety`
Expected: `rev_safety tests: OK`.

- [ ] **Step 5: Commit**

```
git add firmware/stm32-mcp/Core/Src/rev_safety.c \
        firmware/stm32-mcp/tests/host/test_rev_safety.c
git commit -m "rev_safety: frame-gap watchdog and driver_dead brake cause"
```

---

## Task 7: BLE wire types, UUIDs, and operating mode enum

Wire the firmware-side protocol surface. No behavior change yet — this task only adds types so the next few tasks can compile in isolation.

**Files:**
- Modify: `firmware/stm32-mcp/Core/Inc/ble_app.h`

- [ ] **Step 1: Extend the header**

Edit `firmware/stm32-mcp/Core/Inc/ble_app.h`. Add after the existing UUID defines:

```c
/* Added in v0.4.0 — see
 * docs/superpowers/specs/2026-04-23-stm32-reverse-safety-and-protocol-design.md */
#define OPENOTTER_SAFETY_CHAR_UUID 0xFE43 /* Notify: safety state + snapshot */
#define OPENOTTER_MODE_CHAR_UUID   0xFE44 /* Write+read: 0=Drive, 1=Debug */

typedef enum {
  OPENOTTER_MODE_DRIVE = 0,
  OPENOTTER_MODE_DEBUG = 1,
} OpenOtterMode_t;

typedef struct __attribute__((packed)) {
  int16_t steering_us;
  int16_t throttle_us;
  int16_t velocity_mm_per_s;   /* signed; negative = reversing */
} BLE_CommandPayload_t;

_Static_assert(sizeof(BLE_CommandPayload_t) == 6,
               "BLE_CommandPayload_t must be 6 B on wire");

typedef struct __attribute__((packed)) {
  uint32_t seq;
  uint32_t timestamp_ms;
  uint8_t  state;                  /* 0=SAFE, 1=BRAKE */
  uint8_t  cause;                  /* RevSafetyCause_t */
  uint8_t  _pad[2];
  int16_t  trigger_velocity_mm_s;
  uint16_t trigger_depth_mm;
  uint16_t critical_distance_mm;
  uint16_t latched_speed_mm_s;
} BLE_SafetyEventPayload_t;

_Static_assert(sizeof(BLE_SafetyEventPayload_t) == 20,
               "BLE_SafetyEventPayload_t must be 20 B on wire");

/* Query current mode (used by ble_tof.c to gate writes/notifications). */
OpenOtterMode_t BLE_App_GetMode(void);
```

Remove the previous, now-out-of-date inline definition of `BLE_CommandPayload_t` from `ble_app.c` (see Task 8).

- [ ] **Step 2: Build the firmware**

Run: `cd firmware/stm32-mcp && ./build.sh`
Expected: success (the new symbols aren't referenced yet, only declared).

- [ ] **Step 3: Commit**

```
git add firmware/stm32-mcp/Core/Inc/ble_app.h
git commit -m "ble_app: declare FE43/FE44 UUIDs, 6B command, 18B safety payload"
```

---

## Task 8: Extend 0xFE41 command payload to 6 bytes

Refactor the command handler to parse the new 6 B payload and stash the last-seen velocity for later supervisor use. PWM apply stays where it is for now; Task 10 moves it to the main loop.

**Files:**
- Modify: `firmware/stm32-mcp/Core/Src/ble_app.c`

- [ ] **Step 1: Replace the inline struct and context fields**

Delete the local `BLE_CommandPayload_t` definition near the top of `ble_app.c` (it now lives in the header). Update `BLE_AppContext_t` to include the latest velocity:

```c
typedef struct {
  TIM_HandleTypeDef *htim;
  uint16_t svcHandle;
  uint16_t cmdCharHandle;
  uint16_t statusCharHandle;
  uint16_t safetyCharHandle;
  uint16_t modeCharHandle;
  uint16_t connectionHandle;
  volatile uint32_t lastCommandTick;
  volatile uint8_t  isConnected;
  volatile uint8_t  safetyTriggered;
  int16_t currentSteering;
  int16_t currentThrottle;

  /* From the most recent 0xFE41 write. */
  int16_t desiredSteeringUs;
  int16_t desiredThrottleUs;
  int16_t reportedVelocityMmPerS;

  OpenOtterMode_t mode;
} BLE_AppContext_t;
```

(The `safetyCharHandle` and `modeCharHandle` are used in later tasks; declaring them now keeps diffs focused.)

- [ ] **Step 2: Update the command handler parser**

In `BLE_EventHandler`, change the `attr_mod->data_length >= 4` branch to require 6 bytes and copy the new payload fields:

```c
        if (attr_mod->data_length >= (uint16_t)sizeof(BLE_CommandPayload_t)) {
          BLE_CommandPayload_t cmd;
          memcpy(&cmd, attr_mod->att_data, sizeof(cmd));
          bleCtx.desiredSteeringUs      = cmd.steering_us;
          bleCtx.desiredThrottleUs      = cmd.throttle_us;
          bleCtx.reportedVelocityMmPerS = cmd.velocity_mm_per_s;

          BLE_ApplyPWM(cmd.steering_us, cmd.throttle_us);

          bleCtx.lastCommandTick = HAL_GetTick();
          bleCtx.safetyTriggered = 0;
        }
```

Update the `aci_gatt_add_char` call for the command characteristic so its max length is 6:

```c
  ret = aci_gatt_add_char(bleCtx.svcHandle, UUID_TYPE_16,
                          (const uint8_t *)&uuid,
                          sizeof(BLE_CommandPayload_t), /* 6 bytes */
                          CHAR_PROP_WRITE_WITHOUT_RESP | CHAR_PROP_WRITE,
                          ATTR_PERMISSION_NONE, GATT_NOTIFY_ATTRIBUTE_WRITE,
                          10,
                          0,
                          &bleCtx.cmdCharHandle);
```

Also initialize `bleCtx.mode = OPENOTTER_MODE_DRIVE;` in `BLE_App_Init`, and add the getter:

```c
OpenOtterMode_t BLE_App_GetMode(void) { return bleCtx.mode; }
```

- [ ] **Step 3: Build**

Run: `cd firmware/stm32-mcp && ./build.sh`
Expected: success.

- [ ] **Step 4: Commit**

```
git add firmware/stm32-mcp/Core/Src/ble_app.c
git commit -m "ble_app: 6B command payload with velocity; mode/handles stubs"
```

---

## Task 9: Register 0xFE43 safety and 0xFE44 mode characteristics

**Files:**
- Modify: `firmware/stm32-mcp/Core/Src/ble_app.c`

- [ ] **Step 1: Add the two characteristic registrations**

Inside `BLE_InitGATTService`, increase the service's Max_Attribute_Records from 6 to 10 (adds 2 records for each new char × 2 chars):

```c
  ret = aci_gatt_add_serv(UUID_TYPE_16, (const uint8_t *)&uuid, PRIMARY_SERVICE,
                          10, &bleCtx.svcHandle);
```

After the existing command and status registrations, add:

```c
  /*
   * Add Safety Characteristic (Notify + Read) — see
   * docs/.../2026-04-23-stm32-reverse-safety-and-protocol-design.md §3.6.
   */
  uuid = OPENOTTER_SAFETY_CHAR_UUID;
  ret = aci_gatt_add_char(bleCtx.svcHandle, UUID_TYPE_16,
                          (const uint8_t *)&uuid,
                          sizeof(BLE_SafetyEventPayload_t),
                          CHAR_PROP_NOTIFY | CHAR_PROP_READ,
                          ATTR_PERMISSION_NONE,
                          GATT_DONT_NOTIFY_EVENTS,
                          10,
                          0,
                          &bleCtx.safetyCharHandle);
  (void)ret;

  /* Seed a SAFE payload so a post-connect read returns sane bytes. */
  BLE_SafetyEventPayload_t init = {0};
  aci_gatt_update_char_value(bleCtx.svcHandle, bleCtx.safetyCharHandle,
                             0, sizeof(init), (uint8_t *)&init);

  /*
   * Add Mode Characteristic (Write / Write-w/o-Resp / Read). 1-byte enum.
   */
  uuid = OPENOTTER_MODE_CHAR_UUID;
  uint8_t drive = (uint8_t)OPENOTTER_MODE_DRIVE;
  ret = aci_gatt_add_char(bleCtx.svcHandle, UUID_TYPE_16,
                          (const uint8_t *)&uuid,
                          1,
                          CHAR_PROP_WRITE | CHAR_PROP_WRITE_WITHOUT_RESP |
                              CHAR_PROP_READ,
                          ATTR_PERMISSION_NONE,
                          GATT_NOTIFY_ATTRIBUTE_WRITE,
                          10,
                          0,
                          &bleCtx.modeCharHandle);
  (void)ret;
  aci_gatt_update_char_value(bleCtx.svcHandle, bleCtx.modeCharHandle, 0, 1,
                             &drive);
```

- [ ] **Step 2: Handle mode writes in `BLE_EventHandler`**

In the attribute-modified switch, after the command handler branch, add a mode-write branch:

```c
      if (attr_mod->attr_handle == (bleCtx.modeCharHandle + 1)) {
        return_value = SVCCTL_EvtAck;
        if (attr_mod->data_length >= 1) {
          uint8_t v = attr_mod->att_data[0];
          if (v == OPENOTTER_MODE_DRIVE || v == OPENOTTER_MODE_DEBUG) {
            bleCtx.mode = (OpenOtterMode_t)v;
          }
        }
      }
```

On disconnect (in `SVCCTL_App_Notification`, inside `EVT_DISCONN_COMPLETE`), force mode back to Drive:

```c
    bleCtx.mode = OPENOTTER_MODE_DRIVE;
    uint8_t drive = (uint8_t)OPENOTTER_MODE_DRIVE;
    aci_gatt_update_char_value(bleCtx.svcHandle, bleCtx.modeCharHandle, 0, 1,
                               &drive);
```

- [ ] **Step 3: Build**

Run: `cd firmware/stm32-mcp && ./build.sh`
Expected: success.

- [ ] **Step 4: Commit**

```
git add firmware/stm32-mcp/Core/Src/ble_app.c
git commit -m "ble_app: register FE43 safety and FE44 mode characteristics"
```

---

## Task 10: Defer PWM apply to main-loop tick; wire `rev_safety`

This is the structural refactor: the BLE event handler no longer calls `BLE_ApplyPWM`. Instead `BLE_App_Process` (called once per main loop) drives the supervisor and then applies PWM with arbitration.

**Files:**
- Modify: `firmware/stm32-mcp/Core/Src/ble_app.c`
- Modify: `firmware/stm32-mcp/Core/Src/main.c`

- [ ] **Step 1: Remove direct PWM from the command handler**

In `BLE_EventHandler`'s command branch, delete the line `BLE_ApplyPWM(cmd.steering_us, cmd.throttle_us);`. The handler only updates `desiredSteeringUs` / `desiredThrottleUs` / `reportedVelocityMmPerS` / `lastCommandTick` now.

- [ ] **Step 2: Add a supervisor-backed tick to `BLE_App_Process`**

Replace `BLE_App_Process` in `ble_app.c` with:

```c
#include "rev_safety.h"
#include "tof_l1.h"

/* Storage for the reverse supervisor. Opaque size queried at boot. */
static uint8_t s_rev_safety_storage[128]; /* generous; asserted at runtime */
static RevSafetyCtx *s_rev_ctx = (RevSafetyCtx *)s_rev_safety_storage;

static uint32_t s_last_tof_seq   = 0;
static uint32_t s_last_event_seq = 0;

static void publish_safety_event(const RevSafetyEvent_t *ev) {
  BLE_SafetyEventPayload_t p = {0};
  p.seq           = ev->seq;
  p.timestamp_ms  = ev->trigger_timestamp_ms;
  p.state         = (uint8_t)ev->state;
  p.cause         = (uint8_t)ev->cause;
  p.trigger_velocity_mm_s = (int16_t)(ev->trigger_velocity_mps * 1000.0f);
  p.trigger_depth_mm      = (uint16_t)(ev->trigger_depth_m * 1000.0f);
  p.critical_distance_mm  = (uint16_t)(ev->critical_distance_m * 1000.0f);
  p.latched_speed_mm_s    = (uint16_t)(ev->latched_speed_mps * 1000.0f);
  aci_gatt_update_char_value(bleCtx.svcHandle, bleCtx.safetyCharHandle, 0,
                             sizeof(p), (uint8_t *)&p);
}

void BLE_App_Process(void) {
  SCH_Run();

  uint32_t now = HAL_GetTick();
  bool watchdog_trip =
      bleCtx.isConnected &&
      (now - bleCtx.lastCommandTick) > BLE_SAFETY_TIMEOUT_MS;

  /* 1. Run the reverse supervisor (Drive mode only). */
  RevSafetyEvent_t ev = {0};
  if (bleCtx.mode == OPENOTTER_MODE_DRIVE) {
    const TofL1_Frame_t *f = TofL1_GetLatestFrame();
    bool new_frame = (f && f->seq != s_last_tof_seq);
    s_last_tof_seq = f ? f->seq : s_last_tof_seq;

    RevSafetyInput_t in = {0};
    in.velocity_mps  = (float)bleCtx.reportedVelocityMmPerS / 1000.0f;
    in.throttle_us   = bleCtx.desiredThrottleUs;
    in.frame_is_new  = new_frame;
    if (f && f->num_zones >= 5) {
      /* Center zone in 3x3 is index 4 (top-to-bottom, left-to-right). */
      const TofL1_Zone_t *z = &f->zones[4];
      in.zone_valid = (z->status == 0);
      in.raw_depth_m = (float)z->range_mm / 1000.0f;
    }
    in.driver_dead = false; /* TofL1 driver surface TBD; wire in a follow-up */
    in.now_ms      = now;
    RevSafety_Tick(s_rev_ctx, &in, &ev);
  } else {
    /* Debug mode: supervisor is disarmed and transparent. */
    RevSafety_Disarm(s_rev_ctx);
  }

  /* 2. Compute final throttle (arbitration per spec §3.5). */
  int16_t steering_us = bleCtx.desiredSteeringUs;
  int16_t throttle_us = bleCtx.desiredThrottleUs;

  if (bleCtx.mode == OPENOTTER_MODE_DRIVE && RevSafety_IsBraking(s_rev_ctx)) {
    /* Per-direction clamp: block reverse, let forward through. */
    int16_t neutral = (int16_t)PWM_NEUTRAL_US;
    if (throttle_us < neutral) throttle_us = neutral;
  }

  if (watchdog_trip) {
    steering_us = (int16_t)PWM_NEUTRAL_US;
    throttle_us = (int16_t)PWM_NEUTRAL_US;
    bleCtx.safetyTriggered = 1;
  }

  BLE_ApplyPWM(steering_us, throttle_us);

  /* 3. Publish safety notifications. */
  if (ev.transition && ev.seq != s_last_event_seq) {
    publish_safety_event(&ev);
    s_last_event_seq = ev.seq;
  } else if (ev.notify_refresh) {
    publish_safety_event(&ev);
  }
}
```

At the top of `BLE_App_Init`, after `memset(&bleCtx, 0, sizeof(bleCtx))`:

```c
  bleCtx.desiredSteeringUs = PWM_NEUTRAL_US;
  bleCtx.desiredThrottleUs = PWM_NEUTRAL_US;
  bleCtx.reportedVelocityMmPerS = 0;
  bleCtx.mode = OPENOTTER_MODE_DRIVE;

  if (RevSafety_ContextSize() > sizeof(s_rev_safety_storage)) {
    /* Should never hit; compile-time assert would be preferable but the
     * size comes from an opaque accessor, so fail at init. */
    for (;;) { /* halt */ }
  }
  RevSafetyConfig_t rscfg;
  RevSafety_GetDefaultConfig(&rscfg);
  RevSafety_Init(s_rev_ctx, &rscfg);
```

- [ ] **Step 3: Ensure main.c still calls `BLE_App_Process` each loop**

Open `firmware/stm32-mcp/Core/Src/main.c` and confirm the main loop already calls `BLE_App_Process()` every iteration. If it doesn't, add the call inside the existing `while (1)` block. (No TofL1 call changes are needed; the supervisor consumes `TofL1_GetLatestFrame()` directly.)

- [ ] **Step 4: Update the CMake target list**

Edit `firmware/stm32-mcp/cmake/stm32cubemx/CMakeLists.txt`. Around lines 36-37 the list currently contains `tof_l1.c` and `tof_l1_roi.c`. Insert a line for the new module:

```cmake
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Core/Src/rev_safety.c
```

in the same block, alphabetically next to the `tof_l1*` entries.

- [ ] **Step 5: Build**

Run: `cd firmware/stm32-mcp && ./build.sh`
Expected: success.

- [ ] **Step 6: Commit**

```
git add firmware/stm32-mcp/Core/Src/ble_app.c \
        firmware/stm32-mcp/Core/Src/main.c \
        firmware/stm32-mcp/cmake
git commit -m "ble_app: defer PWM apply and run rev_safety supervisor each tick"
```

---

## Task 11: Mode-gate ToF config and frame publishing

Implements spec §3.7. In Drive mode: 0xFE61 writes return `TOF_L1_ERR_LOCKED_IN_DRIVE`, firmware re-applies the safety config if something ever wandered off it, 0xFE62 notifications stay suppressed. In Debug mode: config writes accepted, frame notifications stream.

**Files:**
- Modify: `firmware/stm32-mcp/Core/Src/ble_tof.c`

- [ ] **Step 1: Include mode accessor and enforce in `apply_config_write`**

Add near the top of `ble_tof.c`:

```c
#include "ble_app.h"
```

Replace `apply_config_write` with:

```c
static void apply_config_write(const uint8_t *data, uint16_t len)
{
  if (BLE_App_GetMode() == OPENOTTER_MODE_DRIVE) {
    s_tof.last_error = TOF_L1_ERR_LOCKED_IN_DRIVE;
    s_tof.state      = 1;
    publish_status();
    return;
  }

  if (len < sizeof(BLE_TofConfigPayload_t)) {
    s_tof.last_error = TOF_L1_ERR_BAD_LAYOUT;
    s_tof.state      = 2;
    publish_status();
    return;
  }

  BLE_TofConfigPayload_t cfg;
  memcpy(&cfg, data, sizeof(cfg));

  int rc = TofL1_Configure((TofL1_Layout_t)cfg.layout,
                           (TofL1_DistMode_t)cfg.dist_mode,
                           cfg.budget_us);

  if (rc == TOF_L1_OK || rc == TOF_L1_ERR_RECOVERED) {
    s_tof.last_error            = (rc == TOF_L1_ERR_RECOVERED)
                                      ? (uint8_t)rc : 0;
    s_tof.state                 = 1;
    s_tof.last_published_seq    = 0;
    s_tof.last_rate_window_seq  = 0;
    s_tof.last_rate_window_tick = HAL_GetTick();
    s_tof.pending_chunk         = 0;
  } else if (rc == TOF_L1_ERR_DRIVER_DEAD) {
    s_tof.last_error = (uint8_t)rc;
    s_tof.state      = 2;
  } else {
    s_tof.last_error = (uint8_t)rc;
    s_tof.state      = 1;
  }
  publish_status();
}
```

- [ ] **Step 2: Gate frame notifications on mode**

Remove the hard `return;` at the top of `BLE_Tof_Process` so frames can flow, and replace it with a mode guard:

```c
void BLE_Tof_Process(void)
{
  if (!BLE_App_IsConnected()) return;
  if (BLE_App_GetMode() != OPENOTTER_MODE_DEBUG) return;

  uint32_t now = HAL_GetTick();
  /* ... existing chunking + status publish code unchanged ... */
```

- [ ] **Step 3: Re-apply safety config on Debug→Drive transition**

In `ble_tof.c`, add a small entry point that `ble_app.c` will call on the Debug→Drive edge. Declare in `ble_tof.h`:

```c
/* Force the ToF back to the safety-critical config (3x3 LONG 30 ms).
 * Call when the MCU transitions from Debug back to Drive mode. */
void BLE_Tof_EnforceSafetyConfig(void);
```

Implement in `ble_tof.c`:

```c
void BLE_Tof_EnforceSafetyConfig(void)
{
  int rc = TofL1_Configure(TOF_LAYOUT_3x3, TOF_DIST_LONG, 30000u);
  s_tof.last_error = (rc == TOF_L1_OK) ? 0 : (uint8_t)rc;
  s_tof.state      = (rc == TOF_L1_ERR_DRIVER_DEAD) ? 2 : 1;
  s_tof.last_published_seq    = 0;
  s_tof.last_rate_window_seq  = 0;
  s_tof.last_rate_window_tick = HAL_GetTick();
  s_tof.pending_chunk         = 0;
  publish_status();
}
```

And invoke it from `ble_app.c` inside the mode-write branch of `BLE_EventHandler` where the new mode is parsed — after setting `bleCtx.mode = ...`:

```c
            if (bleCtx.mode == OPENOTTER_MODE_DRIVE) {
              BLE_Tof_EnforceSafetyConfig();
              RevSafety_Disarm(s_rev_ctx);  /* clear any stale latch */
            }
```

- [ ] **Step 4: Build**

Run: `cd firmware/stm32-mcp && ./build.sh`
Expected: success.

- [ ] **Step 5: Commit**

```
git add firmware/stm32-mcp/Core/Inc/ble_tof.h \
        firmware/stm32-mcp/Core/Src/ble_tof.c \
        firmware/stm32-mcp/Core/Src/ble_app.c
git commit -m "ble_tof: mode-gate FE61 writes and FE62 notifications"
```

---

## Task 12: On-target smoke checklist

No code change — a written HIL verification checklist. Corresponds to spec §3.8 items 8-12.

**Files:**
- Create: `firmware/stm32-mcp/docs/dev/06-reverse-safety-bringup.md`

- [ ] **Step 1: Write the checklist**

Create `firmware/stm32-mcp/docs/dev/06-reverse-safety-bringup.md`:

```
# Reverse Safety Supervisor — Bringup Checklist

Follow after flashing firmware ≥ v0.4.0 and pairing with an iOS build that
speaks the 6 B command and 0xFE43/0xFE44 protocol. All checks run with the
vehicle on blocks (wheels off the ground) except items that explicitly say
otherwise.

1. **Default mode on connect.** After BLE connect, read 0xFE44. Expect `0x00`
   (Drive). Disconnect and reconnect; expect `0x00` again.
2. **Drive rejects ToF config writes.** Write an arbitrary valid config
   (e.g. layout=1, dist_mode=2, budget=50000) to 0xFE61. Read 0xFE63.
   Expect `last_error = 11` (`TOF_L1_ERR_LOCKED_IN_DRIVE`).
3. **Drive suppresses ToF frames.** Subscribe to 0xFE62. Expect zero
   notifications during a 10 s observation.
4. **Switch to Debug.** Write `0x01` to 0xFE44. Write a legal config to
   0xFE61 (e.g. 3x3 LONG 30 ms). Expect 0xFE62 notifications to start and
   arrive at ≈4 Hz.
5. **Switch back to Drive.** Write `0x00` to 0xFE44. 0xFE62 must stop
   within 1 s. Read 0xFE63; `state = 1` and `last_error = 0`.
6. **Reverse-into-wall (vehicle on the floor, spotter present).** Command
   throttle 1350 µs (mild reverse) with the rear aimed at a wall 1 m away.
   Expect:
   - BRAKE notification on 0xFE43 with `state=1`, `cause=1` (obstacle)
     within one 270 ms scan.
   - Throttle is clamped to 1500 µs (neutral) within the same main-loop
     tick.
   - Driving forward (throttle > 1530 µs) clears the BRAKE — 0xFE43 notifies
     `state=0`.
7. **Cover the lens.** While reversing at 1350 µs with 2 m clear, block the
   ToF lens with a hand. Expect BRAKE with `cause=2` (tof_blind) within 2
   scan periods (≈540 ms). Uncover; expect release after 0.3 s of continuous
   clearance.
8. **BLE watchdog.** Disconnect the iPhone while reversing. PWM must go to
   neutral within `BLE_SAFETY_TIMEOUT_MS` (1.5 s). Reconnect; supervisor
   should resume from SAFE.
```

- [ ] **Step 2: Commit**

```
git add firmware/stm32-mcp/docs/dev/06-reverse-safety-bringup.md
git commit -m "docs: reverse-safety bringup checklist"
```

---

## Task 13: iOS — extend `sendCommand` signature and payload

**Files:**
- Modify: `openotter-ios/Sources/Capture/STM32BleManager.swift`

- [ ] **Step 1: Update `sendCommand`**

Replace the existing `sendCommand` with:

```swift
    /// Send steering, throttle (pulse widths in µs) and measured velocity
    /// (mm/s, negative = reversing) to the STM32.
    public func sendCommand(steeringMicros: Int16,
                            throttleMicros: Int16,
                            velocityMmPerSec: Int16) {
        guard let commandChar, let peripheral else { return }

        var payload = Data(count: 6)
        payload.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: steeringMicros.littleEndian,
                           toByteOffset: 0, as: Int16.self)
            ptr.storeBytes(of: throttleMicros.littleEndian,
                           toByteOffset: 2, as: Int16.self)
            ptr.storeBytes(of: velocityMmPerSec.littleEndian,
                           toByteOffset: 4, as: Int16.self)
        }

        let writeType: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse)
                ? .withoutResponse : .withResponse
        peripheral.writeValue(payload, for: commandChar, type: writeType)

        DispatchQueue.main.async { self.commandsSent += 1 }
    }
```

Temporarily add an overload that keeps existing callers compiling — Task 14 will remove it:

```swift
    /// Transitional — delete once all callers pass velocity explicitly.
    public func sendCommand(steeringMicros: Int16, throttleMicros: Int16) {
        sendCommand(steeringMicros: steeringMicros,
                    throttleMicros: throttleMicros,
                    velocityMmPerSec: 0)
    }
```

- [ ] **Step 2: Build**

Run:

```
cd openotter-ios && xcodebuild -scheme openotter -destination 'platform=iOS Simulator,name=iPhone 15' build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```
git add openotter-ios/Sources/Capture/STM32BleManager.swift
git commit -m "ble: sendCommand takes velocityMmPerSec (6B payload)"
```

---

## Task 14: iOS — thread velocity through callers

The callers that own speed are the self-driving and manual-control view models. The RPi control view model talks to the Raspberry Pi backend, not the STM32 — leave it alone.

**Files:**
- Modify: `openotter-ios/Sources/Capture/STM32ControlViewModel.swift`
- Modify: `openotter-ios/Sources/Capture/SelfDrivingViewModel.swift`

- [ ] **Step 1: SelfDrivingViewModel — pass velocity from the planner**

Open `SelfDrivingViewModel.swift`. Around lines 180-186 the view model already has access to the planner's measured speed (the same source used by the iOS `SafetySupervisor`). Wrap it:

```swift
        let v_mm_s = Int16((self.currentSpeedMPS * 1000.0)
                             .clamped(to: -32000.0...32000.0))
        stm32Manager.sendCommand(steeringMicros: sPWM,
                                 throttleMicros: tPWM,
                                 velocityMmPerSec: v_mm_s)
```

and:

```swift
        stm32Manager.sendCommand(steeringMicros: 1500,
                                 throttleMicros: 1500,
                                 velocityMmPerSec: 0)
```

If `Float.clamped(to:)` does not exist in the project, inline a `max(min(...))` expression instead. Verify with a grep: `grep -n "clamped(to:" openotter-ios/Sources | head`.

Property `self.currentSpeedMPS` is the same scalar the view model already reads; if the exact name differs (`currentSpeed`, `speedEstimate`, `velocityFromPose`, etc.), pick the one already exposed — do not introduce a new computed property.

- [ ] **Step 2: STM32ControlViewModel — pass 0 when no measured speed**

`STM32ControlViewModel.swift` is the manual-drive bridge; it has no velocity estimate of its own. Passing 0 is correct — the firmware supervisor's velocity-sign gate stays disarmed and the throttle-sign gate does the work.

Replace the two `sendCommand` calls (around lines 165 and 180) with explicit zero velocity:

```swift
        bleManager.sendCommand(steeringMicros: steeringUs,
                               throttleMicros: throttleUs,
                               velocityMmPerSec: 0)
```

- [ ] **Step 3: Delete the transitional overload**

In `STM32BleManager.swift`, remove the 4-argument overload added in Task 13. Run a grep to confirm no other call sites use the two-argument signature:

```
grep -rn "sendCommand(steeringMicros:" openotter-ios/Sources
```

Expected: only the three-argument form remains.

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme openotter ... build` as in Task 13.
Expected: success.

- [ ] **Step 5: Commit**

```
git add openotter-ios/Sources/Capture/SelfDrivingViewModel.swift \
        openotter-ios/Sources/Capture/STM32ControlViewModel.swift \
        openotter-ios/Sources/Capture/STM32BleManager.swift
git commit -m "ble: thread measured velocity into STM32 command writes"
```

---

## Task 15: iOS — `FirmwareSafetyEvent` model and parser test

**Files:**
- Create: `openotter-ios/Sources/Planner/Safety/FirmwareSafetyEvent.swift`
- Create: `openotter-ios/Tests/Planner/FirmwareSafetyEventTests.swift`

- [ ] **Step 1: Write the failing test**

Create `openotter-ios/Tests/Planner/FirmwareSafetyEventTests.swift`. Spec §3.6 payload is 20 B; layout is:

```
0..3   seq                     (u32 LE)
4..7   timestamp_ms            (u32 LE)
8      state                   (u8)
9      cause                   (u8)
10..11 pad                     (must be 0)
12..13 trigger_velocity_mm_s   (i16 LE)
14..15 trigger_depth_mm        (u16 LE)
16..17 critical_distance_mm    (u16 LE)
18..19 latched_speed_mm_s      (u16 LE)
```

```swift
import XCTest
@testable import openotter

final class FirmwareSafetyEventTests: XCTestCase {

    func testParsesBrakeObstaclePayload() throws {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 7                                       // seq = 7
        bytes[4] = 0x78; bytes[5] = 0x56                   // timestamp low
        bytes[6] = 0x34; bytes[7] = 0x12                   // timestamp high
        bytes[8] = 1                                       // state = BRAKE
        bytes[9] = 1                                       // cause = obstacle
        bytes[12] = 0x18; bytes[13] = 0xFC                 // velocity = -1000 mm/s
        bytes[14] = 0x2C; bytes[15] = 0x01                 // depth = 300 mm
        bytes[16] = 0x66; bytes[17] = 0x03                 // critical = 870 mm
        bytes[18] = 0xE8; bytes[19] = 0x03                 // latched = 1000 mm/s

        let event = try FirmwareSafetyEvent(data: Data(bytes))
        XCTAssertEqual(event.seq, 7)
        XCTAssertEqual(event.timestampMs, 0x12345678)
        XCTAssertEqual(event.state, .brake)
        XCTAssertEqual(event.cause, .obstacle)
        XCTAssertEqual(event.triggerVelocityMPS, -1.0, accuracy: 1e-3)
        XCTAssertEqual(event.triggerDepthM,       0.300, accuracy: 1e-3)
        XCTAssertEqual(event.criticalDistanceM,   0.870, accuracy: 1e-3)
        XCTAssertEqual(event.latchedSpeedMPS,     1.0,   accuracy: 1e-3)
    }

    func testRejectsShortPayload() {
        let data = Data(repeating: 0, count: 19)
        XCTAssertThrowsError(try FirmwareSafetyEvent(data: data))
    }

    func testMapsUnknownCauseToNone() throws {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[8] = 0
        bytes[9] = 42  // unknown cause -> defaults to .none
        let event = try FirmwareSafetyEvent(data: Data(bytes))
        XCTAssertEqual(event.cause, .none)
    }
}
```

- [ ] **Step 2: Watch the tests fail**

Run:

```
cd openotter-ios && xcodebuild test -scheme openotter \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:openotterTests/FirmwareSafetyEventTests
```

Expected: compile error (`FirmwareSafetyEvent` does not exist).

- [ ] **Step 3: Write the model**

Create `openotter-ios/Sources/Planner/Safety/FirmwareSafetyEvent.swift`:

```swift
import Foundation

/// Parsed payload of the STM32 firmware safety characteristic (0xFE43).
/// Wire layout is defined in
/// docs/superpowers/specs/2026-04-23-stm32-reverse-safety-and-protocol-design.md §3.6.
public struct FirmwareSafetyEvent: Equatable {

    public enum State: UInt8 {
        case safe = 0
        case brake = 1
    }

    public enum Cause: UInt8 {
        case none        = 0
        case obstacle    = 1
        case tofBlind    = 2
        case frameGap    = 3
        case driverDead  = 4
    }

    public let seq: UInt32
    public let timestampMs: UInt32
    public let state: State
    public let cause: Cause
    public let triggerVelocityMPS: Float
    public let triggerDepthM: Float
    public let criticalDistanceM: Float
    public let latchedSpeedMPS: Float

    public enum ParseError: Error { case shortPayload }

    public init(data: Data) throws {
        guard data.count >= 20 else { throw ParseError.shortPayload }
        func u32(_ offset: Int) -> UInt32 {
            return data.subdata(in: offset..<(offset+4))
                .withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        }
        func u16(_ offset: Int) -> UInt16 {
            return data.subdata(in: offset..<(offset+2))
                .withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
        }
        func i16(_ offset: Int) -> Int16 {
            return Int16(bitPattern: u16(offset))
        }
        self.seq           = u32(0)
        self.timestampMs   = u32(4)
        self.state         = State(rawValue: data[8]) ?? .safe
        self.cause         = Cause(rawValue: data[9]) ?? .none
        self.triggerVelocityMPS = Float(i16(12)) / 1000.0
        self.triggerDepthM      = Float(u16(14)) / 1000.0
        self.criticalDistanceM  = Float(u16(16)) / 1000.0
        self.latchedSpeedMPS    = Float(u16(18)) / 1000.0
    }
}
```

- [ ] **Step 4: Watch the tests pass**

Re-run the xcodebuild command from Step 2. Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```
git add openotter-ios/Sources/Planner/Safety/FirmwareSafetyEvent.swift \
        openotter-ios/Tests/Planner/FirmwareSafetyEventTests.swift
git commit -m "safety: FirmwareSafetyEvent parser for 0xFE43 notifications"
```

---

## Task 16: iOS — subscribe to 0xFE43 and write 0xFE44 on connect

**Files:**
- Modify: `openotter-ios/Sources/Capture/STM32BleManager.swift`

- [ ] **Step 1: Add UUIDs and publisher**

In `STM32BleManager.swift`, add near the existing UUID block:

```swift
    private let safetyCharUUID = CBUUID(string: "FE43")
    private let modeCharUUID   = CBUUID(string: "FE44")

    private var safetyChar: CBCharacteristic?
    private var modeChar: CBCharacteristic?

    @Published public private(set) var lastSafetyEvent: FirmwareSafetyEvent?
```

- [ ] **Step 2: Discover and subscribe**

In the characteristic-discovery callback, extend the discovery request to include the two new UUIDs:

```swift
                peripheral.discoverCharacteristics(
                    [commandCharUUID, statusCharUUID,
                     safetyCharUUID, modeCharUUID],
                    for: service)
```

In the `didDiscoverCharacteristicsFor` case block, route the new UUIDs to their fields:

```swift
                case safetyCharUUID:
                    self.safetyChar = ch
                    peripheral.setNotifyValue(true, for: ch)
                case modeCharUUID:
                    self.modeChar = ch
                    // Ensure we start in Drive mode even if the peer was
                    // left in Debug by a previous session.
                    let drive: [UInt8] = [0x00]
                    let writeType: CBCharacteristicWriteType =
                        ch.properties.contains(.writeWithoutResponse)
                            ? .withoutResponse : .withResponse
                    peripheral.writeValue(Data(drive), for: ch, type: writeType)
```

- [ ] **Step 3: Parse notifications**

In the `didUpdateValueFor` delegate method (or the existing `case statusCharUUID:` switch), add a case for the safety characteristic:

```swift
        case safetyCharUUID:
            guard let data = characteristic.value else { return }
            do {
                let ev = try FirmwareSafetyEvent(data: data)
                DispatchQueue.main.async { self.lastSafetyEvent = ev }
            } catch {
                // Ignore malformed payloads; firmware should never send them.
            }
```

- [ ] **Step 4: Build**

Run the iOS build again. Expected: success.

- [ ] **Step 5: Commit**

```
git add openotter-ios/Sources/Capture/STM32BleManager.swift
git commit -m "ble: subscribe to FE43 safety; force FE44 Drive on connect"
```

---

## Task 17: Release notes

**Files:**
- Modify: `firmware/stm32-mcp/CHANGELOG.md`
- Modify: `openotter-ios/CHANGELOG.md`

- [ ] **Step 1: Add firmware changelog entry**

Prepend under the existing `<!-- markdownlint-disable MD024 -->` line:

```
## [0.4.0] - 2026-04-23

### Added
- **Reverse Safety Supervisor**: New HAL-free `rev_safety` module. Critical-distance policy mirrors the iOS forward supervisor (see `openotter-ios/Sources/Planner/Safety/DESIGN.md` §4). Center-zone 3×3 LONG 30 ms ToF feeds the supervisor; invalid-frame (2 consecutive) and frame-gap (500 ms) watchdogs fail-safe to BRAKE.
- **BLE Protocol**:
  - 0xFE41 command extended to 6 B (added `int16_t velocity_mm_per_s`).
  - 0xFE43 safety notify characteristic, 20 B payload with state, cause and trigger snapshot.
  - 0xFE44 mode characteristic (0 = Drive, 1 = Debug).
- **Operating Modes**: Drive (default, supervisor armed, ToF config locked, 0xFE62 suppressed) and Debug (supervisor disarmed, ToF config writable, 0xFE62 streamed).

### Changed
- `BLE_App_Process` now drives PWM after running the supervisor and applying the per-direction reverse clamp (§3.5 of the reverse-safety design doc).
- `ble_tof.c` rejects 0xFE61 writes in Drive mode with `TOF_L1_ERR_LOCKED_IN_DRIVE`.
```

- [ ] **Step 2: Add iOS changelog entry**

Prepend a new release heading in `openotter-ios/CHANGELOG.md`:

```
## [0.12.0] - 2026-04-23

### Added
- `FirmwareSafetyEvent` model and decoder for the STM32 0xFE43 characteristic.
- Subscribe to firmware safety notifications; `STM32BleManager.lastSafetyEvent` published for HUD consumers.
- Write operating mode 0xFE44 on connect to ensure Drive mode.

### Changed
- `STM32BleManager.sendCommand` signature now includes `velocityMmPerSec`. `SelfDrivingViewModel` and `STM32ControlViewModel` updated.
```

- [ ] **Step 3: Commit**

```
git add firmware/stm32-mcp/CHANGELOG.md openotter-ios/CHANGELOG.md
git commit -m "Docs: changelogs for reverse-safety + protocol extension"
```

(No version-bump / tag step here; follow `CLAUDE.md` §6 release protocol when cutting the actual release.)

---

## Self-Review

- [ ] Spec coverage:
  - §2 sensor config locked — Task 11 (mode gate) + Task 11's `BLE_Tof_EnforceSafetyConfig`.
  - §3.1 velocity transport — Tasks 7, 8, 13, 14.
  - §3.2 direction inference — Tasks 4/5 (`supervisor_armed`).
  - §3.3 supervisor math — Tasks 3, 5 (all three iOS-parity adjustments).
  - §3.4 invalid/stale — Task 4 (A), Task 6 (B). Item (C) is unchanged firmware watchdog behavior, exercised by Task 10.
  - §3.5 arbitration — Task 10 arbitration block + Task 10 watchdog override.
  - §3.6 FE43 protocol — Tasks 7, 9, 10 (publish), 15, 16.
  - §3.7 operating modes — Tasks 7, 9 (register), 10 (effect on supervisor), 11 (ToF gate).
  - §3.8 tests — Host: Tasks 3-6. On-target: Task 12.
  - §3.9 latency constants — Task 2 (defaults), Task 3 (parity table test).
- [ ] Placeholder scan: no "TBD", no "implement later", no "add appropriate handling". One explicit note in Task 10 that `driver_dead` plumbing from the TofL1 driver is left as a follow-up — marked in code, not in the plan.
- [ ] Type consistency: `RevSafetyCtx *` opaque pointer, `RevSafety_ContextSize()`, `s_rev_safety_storage[128]` runtime check, consistent between Tasks 2 / 3 / 10. `BLE_SafetyEventPayload_t` size is 20 B throughout (corrected in Task 15 step 2).

---

Plan saved. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
