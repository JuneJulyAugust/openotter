# Safety Supervisor — Design v1.0 (Time-to-Brake)

**Status:** Implemented
**Date:** 2026-04-22
**Supersedes:** v0.4 (tri-zone state machine with latched speed)

---

## 1. Purpose

The `SafetySupervisor` sits between the planner output and the actuators. On every control tick it compares the forward obstacle distance against a speed-dependent **critical distance** derived purely from kinematics. If the obstacle is closer than that critical distance, the supervisor issues an emergency brake command. Otherwise it passes the planner's command through unchanged.

This document is the single source of truth for the policy. Tuning knobs are `tSysS`, `decelIntercept`, `decelSlope`, and `dMarginM`, all live-configurable.

---

## 2. Why Replace v0.4

v0.4 accumulated complexity to fight oscillation: three zones (`CLEAR` / `CAUTION` / `BRAKE`), two time-to-collision thresholds, two absolute-distance floors, a kinematic term, asymmetric exponential-moving-average alphas, two cooldown timers, and a latched speed. Eight tunable parameters interacted in non-obvious ways. Each added to silence a specific test symptom; none derived from first principles.

The new policy derives a single critical distance from the physics of stopping and uses one latch rule to prevent oscillation. Three physically meaningful parameters replace eight ad-hoc ones.

---

## 3. Perception Input

The supervisor consumes a single scalar per tick: `forwardDepth` from `PlannerContext`. Upstream (`ARKitPoseViewModel.extractCenterDepth`) samples a 3×3 patch around the center pixel of the ARKit scene depth map and returns the **spatial median** (robust against sparse dropouts). The supervisor itself applies one stage of **temporal smoothing** — a symmetric exponential moving average:

```
smoothedDepth_t = alpha · rawDepth_t + (1 - alpha) · smoothedDepth_{t-1}
```

One `alpha` (default `0.5`). No asymmetry between approach and recede — the spatial median already rejects single-frame spikes, and the latched-speed rule (§5) handles the "brief dropout releases brake" concern.

---

## 4. Critical Distance

For current speed `v`:

```
criticalDistance(v) = v · tSysS  +  stoppingDistance(v)  +  dMarginM
                      └─reaction┘   └───stopping──────┘   └─margin─┘
```

### Deceleration model

Deceleration is speed-dependent (back-EMF ∝ speed, plus rolling friction):

```
a(v) = decelIntercept + decelSlope · v
```

Fitted from 8 brake tests (v = 0.74–3.16 m/s) using the exact spatial stopping distance integral:
- `a(v) = 0.66 + 0.87·v`

### Stopping distance (exact integral)

With linear drag `a(v) = a₀ + k·v`, the ODE `v dv/dx = -(a₀ + k·v)` yields:

```
stoppingDistance(v₀) = v₀/k − (a₀/k²)·ln(1 + k·v₀/a₀)
```

Falls back to `v²/(2·a₀)` when `k ≈ 0` (constant deceleration).

| Term | Physical meaning |
|------|------------------|
| `v · tSysS` | Distance traveled during system reaction latency (sense → decide → actuator effect). |
| `stoppingDistance(v)` | Exact stopping distance under speed-dependent deceleration. |
| `dMarginM` | Fixed post-stop standoff. Includes the sensor-to-bumper offset (~0.13 m — the phone LiDAR is mounted behind the car's front bumper) plus desired clearance (0.07 m). |

With defaults `tSysS = 0.1 s`, `decelIntercept = 0.66`, `decelSlope = 0.87`, `dMarginM = 0.20 m`:

| Speed    | a(v)  | Reaction | Stopping | Margin | **criticalDistance** |
|----------|-------|----------|----------|--------|----------------------|
| 0.5 m/s  | 1.09  | 0.050 m  | 0.133 m  | 0.20 m | **0.38 m**           |
| 1.0 m/s  | 1.53  | 0.100 m  | 0.416 m  | 0.20 m | **0.72 m**           |
| 1.5 m/s  | 1.96  | 0.150 m  | 0.773 m  | 0.20 m | **1.12 m**           |
| 2.0 m/s  | 2.40  | 0.200 m  | 1.173 m  | 0.20 m | **1.57 m**           |
| 2.5 m/s  | 2.83  | 0.250 m  | 1.603 m  | 0.20 m | **2.05 m**           |
| 3.0 m/s  | 3.27  | 0.300 m  | 2.053 m  | 0.20 m | **2.55 m**           |
| 3.16 m/s | 3.41  | 0.316 m  | 2.200 m  | 0.20 m | **2.72 m**           |

---

## 5. State Machine

Two states. One latch.

```
                    smoothedDepth > criticalDistance(latchedSpeed)
                            held for releaseHoldS
                                      OR
                         plannerThrottle <= 0
          ┌─────────────────────────────────────────────────────────┐
          │                                                         │
 ┌────────▼─────────┐                                     ┌─────────┴────────┐
 │       SAFE       │   smoothedDepth <= criticalDistance │      BRAKE       │
 │  passthrough     │────────────────────────────────────▶│  neutral throttle│
 │  planner command │   latch: speed, depth, pose, time   │  (throttle = 0)  │
 └──────────────────┘                                     └──────────────────┘
```

### 5.1 Trigger (SAFE → BRAKE)

When `smoothedDepth ≤ criticalDistance(v_now)`:

1. Record `trigger = { t, pose, speed: v_now, depth: smoothedDepth, criticalDistance }`.
2. **Latch** `latchedSpeed = v_now`. This value is frozen until we leave BRAKE.
3. Emit `ControlCommand(steering: 0, throttle: 0, source: .safetySupervisor)`.

### 5.1.1 Why neutral throttle, not reverse

The brake command sets `throttle = 0` (neutral), not a negative (reverse) value. Reasoning:

- **A car's brake pedal is not reverse gear.** Friction brakes dissipate kinetic energy into heat at the pad/rotor interface; the engine is decoupled. Our analogous primitive is "stop commanding torque" — neutral throttle. The motor's own back-EMF and drivetrain friction decelerate the wheels.
- **Reverse torque while moving forward invites slip.** If ground grip is low, driven wheels spinning backward relative to chassis motion break traction and skid — exactly the scenario a safety system must not create.
- **Overshoot into backward motion is a new hazard.** Any reverse torque that does not stop exactly at v=0 pushes the robot backward, which the forward-only depth sensor cannot see. Coasting to stop keeps all motion monotonic forward until standstill.

The empirical `actualDecelMPS2` (§7) measures how well neutral alone decelerates the platform. If the measured deceleration is consistently below `estimatedDeceleration(at: triggerSpeed)`, the model parameters need adjusting. This is the feedback loop that makes the design tunable from field testing.

### 5.2 Hold (BRAKE)

While in BRAKE, `criticalDistance` is computed with `latchedSpeed`, **not the current speed**. This is the invariant that prevents the "brake → v drops → criticalDistance shrinks → release" feedback loop.

Each tick while in BRAKE:
- Keep emitting the brake command.
- If `|v_now| < stopSpeedEpsilonMPS` and no stop snapshot yet, capture `stop = { t, pose, depth: smoothedDepth }`. Used to compute actual deceleration (§7).

### 5.3 Release (BRAKE → SAFE)

Two independent release paths:

**(a) Genuine clearance.** `smoothedDepth > criticalDistance(latchedSpeed)` must hold continuously for `releaseHoldS` (default 0.3 s). The debounce only guards against single-frame depth noise; it does **not** force a minimum brake duration. Physical interpretation: obstacle (or robot) must have actually moved away by the full safety margin computed at trigger speed.

**(b) Operator intervention.** Planner issues `throttle ≤ 0` (stop, neutral, or reverse). Supervisor drops latch and passes the command through. This is the escape hatch: a human operator can always override by commanding reverse.

On release: clear `latchedSpeed`, clear stop snapshot (kept on the event record one more tick for the UI), transition to SAFE.

### 5.4 Why the latch cannot deadlock

If the robot is stopped at 0.3 m from a stationary wall with `latchedSpeed = 1.0 m/s`:
- `criticalDistance(1.0) = 0.45 m > 0.30 m` → BRAKE holds.
- Operator sees stuck state, commands reverse → latch drops → robot backs away → SAFE.

The system never silently self-releases into a hazard. Either depth grows (real clearance) or operator acts.

---

## 6. Worked Examples

### Example 1 — nominal brake-and-release

Defaults. Operator commands throttle = 0.5 continuously. Wall at 0.30 m, robot at 1.0 m/s approaches.

| t (s) | v_now | smoothedDepth | latchedSpeed | criticalDistance | state | output throttle |
|-------|-------|---------------|--------------|------------------|-------|-----------------|
| 0.00  | 1.00  | 0.60          | —            | 0.45 (@v_now)    | SAFE  | 0.50            |
| 0.05  | 1.00  | 0.40          | —            | 0.45 (@v_now)    | BRAKE | 0.00 (trigger, latch=1.0) |
| 0.10  | 0.70  | 0.35          | 1.00         | 0.45 (@latched)  | BRAKE | 0.00            |
| 0.30  | 0.00  | 0.32          | 1.00         | 0.45 (@latched)  | BRAKE | 0.00 (stop captured) |
| 1.00  | 0.00  | 0.32          | 1.00         | 0.45 (@latched)  | BRAKE | 0.00 (stuck, waiting) |

Operator commands reverse:

| t (s) | v_now | plannerThrottle | latchedSpeed | state | output throttle |
|-------|-------|-----------------|--------------|-------|-----------------|
| 1.10  | 0.00  | -0.30           | —            | SAFE  | -0.30 (passthrough, latch dropped) |

### Example 2 — obstacle steps out of the way

Defaults. Robot at 1.0 m/s, pedestrian at 0.40 m, then pedestrian steps aside so depth jumps to 2.0 m.

| t (s) | v_now | smoothedDepth | latchedSpeed | criticalDistance | state | notes |
|-------|-------|---------------|--------------|------------------|-------|-------|
| 0.00  | 1.00  | 0.40          | —            | 0.45             | BRAKE | trigger |
| 0.05  | 0.80  | 1.20          | 1.00         | 0.45             | BRAKE | depth above, start release timer |
| 0.35  | 0.60  | 2.00          | 1.00         | 0.45             | SAFE  | held 0.3 s above threshold → release |

### Example 3 — depth noise spike does not release

Defaults. Robot stopped at wall 0.32 m away, `latchedSpeed = 1.0 m/s` (`criticalDistance = 0.45`). One frame of noise reports 0.60 m then back to 0.32 m.

| t (s) | smoothedDepth | release timer | state |
|-------|---------------|---------------|-------|
| 0.00  | 0.32          | —             | BRAKE |
| 0.03  | 0.46          | started       | BRAKE |
| 0.06  | 0.32          | reset         | BRAKE |

Timer resets the moment `smoothedDepth` drops back under threshold. No oscillation.

---

## 7. Stop Measurement and Actual Deceleration

At BRAKE trigger the supervisor captures `trigger`. It then watches for the first frame with `|v_now| < stopSpeedEpsilonMPS` and captures `stop`. From the pair it derives:

```
stoppingTimeS     = stop.t - trigger.t
stoppingDistanceM = ||stop.pose.xy - trigger.pose.xy||          (planar distance)
actualDecelMPS2   = trigger.speed / stoppingTimeS               (mean deceleration)
brakingDistanceM  = trigger.depth - stop.depth                  (how much closer we got)
```

`actualDecelMPS2` is the empirical counterpart of the deceleration model `a(v) = decelIntercept + decelSlope * v`. If `actualDecelMPS2 < estimatedDeceleration(at: triggerSpeed)` consistently, the model is optimistic — increase the safety factor or adjust `decelIntercept`/`decelSlope`. This is the feedback loop that makes the design tunable from field testing.

Both snapshots are exposed to the view model and rendered in the emergency overlay and HUD so the operator sees, in one glance: "decided to stop at X m traveling Y m/s — actually stopped Z m later with actual deceleration W m/s²".

---

## 8. Configuration

```swift
struct SafetySupervisorConfig {
    var tSysS: Float = 0.1              // reaction latency (seconds)

    // Speed-dependent deceleration: a(v) = decelIntercept + decelSlope * v
    // Fitted from 8 brake tests using the exact spatial integral to minimize
    // prediction error. No artificial safety reduction is applied here.
    var decelIntercept: Float = 0.66    // rolling friction (m/s²)
    var decelSlope: Float = 0.87        // back-EMF coefficient (1/s)

    var dMarginM: Float = 0.20          // post-stop standoff (meters)
                                        // ~0.13 m sensor-to-bumper offset + 0.07 m clearance

    var alphaSmoothing: Float = 0.5     // exponential moving average weight (0..1, higher = faster)
    var releaseHoldS: TimeInterval = 0.3  // continuous-clearance debounce before release
    var fallbackSpeedMPS: Float = 0.3   // used when neither motor nor ARKit report speed
    var stopSpeedEpsilonMPS: Float = 0.05  // below this the robot is "stopped"
}
```

The deceleration model parameters (`decelIntercept`, `decelSlope`) are physical—they map directly to rolling friction and motor back-EMF drag. The feedback loop is: run brake tests, compare `actualDecelMPS2` vs `estimatedDeceleration(at: triggerSpeed)`, adjust parameters.

---

## 9. API Surface

```swift
final class SafetySupervisor {
    init(config: SafetySupervisorConfig)

    func supervise(command: ControlCommand, context: PlannerContext) -> ControlCommand
    func reset()

    var state: SafetySupervisorState { get }          // .safe | .brake
    var lastEvent: SafetySupervisorEvent? { get }     // per-tick diagnostic
    var currentBrake: SafetyBrakeRecord? { get }      // trigger + optional stop while BRAKE
}

enum SafetySupervisorState: Equatable {
    case safe
    case brake(since: TimeInterval)
}

struct SafetySupervisorEvent: Equatable {
    let timestamp: TimeInterval
    let rawDepth: Float
    let smoothedDepth: Float
    let speed: Float
    let criticalDistance: Float
    let isBraking: Bool
    let reason: String?
}

struct SafetyBrakeRecord: Equatable {
    let trigger: SafetyBrakeTrigger
    let stop: SafetyBrakeStop?           // nil until robot actually stops
    let actualDecelMPS2: Float?          // derived once stop is captured
    let stoppingTimeS: TimeInterval?
    let stoppingDistanceM: Float?
    let brakingDistanceM: Float?
}
```

Exact field lists live in `SafetySupervisor.swift` and `SafetySupervisorEvent.swift`.

---

## 10. What Went Away From v0.4

| Removed                                  | Why                                                    |
|------------------------------------------|--------------------------------------------------------|
| CAUTION state and throttle scaling       | Binary SAFE/BRAKE is enough; ramping adds state with no safety benefit. |
| `ttcBrakeS`, `ttcCautionS`               | Subsumed by the reaction-latency term of `criticalDistance`. |
| `minBrakeDistanceM`, `minCautionDistanceM` | Subsumed by `dMarginM`; no artificial floor needed once the latch prevents oscillation. |
| Asymmetric approach/recede alphas        | Spatial median already rejects spikes; one alpha is enough. |
| `minBrakeDurationS`                      | Latched-speed invariant makes early release impossible without genuine depth growth. |
| `minCautionDurationS`                    | Replaced by `releaseHoldS` on the single SAFE transition. |
| `cautionSnapshot`                        | No CAUTION state exists. |

---

## 11. Extensibility

The current scalar depth input can be replaced by a forward-cone summary without changing the policy: as long as the upstream produces one "minimum obstacle distance along the forward path," the supervisor is unchanged. Steering-aware safety (widen the cone when turning) belongs upstream, in the perception layer, not here.
