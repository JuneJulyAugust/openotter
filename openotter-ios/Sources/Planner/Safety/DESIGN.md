# Safety Supervisor — Design v0.4

**Status:** Implemented
**Date:** 2026-04-04

---

## 1. Purpose

The `SafetySupervisor` sits between the planner output and the actuators. If the forward path is threatened, it either scales back throttle (CAUTION) or fully stops the robot (BRAKE). The planner and UI are notified of the current safety state.

---

## 2. Root-Cause Analysis (from v0.2)

The v0.2 binary PASS/BRAKE design caused stop-go oscillation due to three interacting failure modes:

1. **Binary Brake Policy:** The system oscillated at the threshold boundary because there were only two output states — full throttle or zero throttle.
2. **Speed-Dependent Threshold + Instant Brake:** When the supervisor braked, speed dropped, which shrank the threshold, which released the brake, which raised speed, which expanded the threshold, which triggered the brake — a positive feedback loop. The hysteresis couldn't fix this because the threshold itself was moving.
3. **Unfiltered Depth:** Frame-to-frame LiDAR noise triggered the full brake/release cycle even without real obstacle motion.

---

## 3. Configuration (Actual Values)

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `ttcBrakeS` | `0.3 s` | TTC threshold for BRAKE zone |
| `ttcCautionS` | `0.8 s` | TTC threshold for CAUTION zone |
| `minBrakeDistanceM` | `0.30 m` | Hard floor on BRAKE distance — ensures overshoot stays below threshold at low speed |
| `minCautionDistanceM` | `0.50 m` | Hard floor on CAUTION distance (must exceed minBrakeDistanceM) |
| `maxDecelerationMPS2` | `2.5 m/s²` | Max assumed braking decel for kinematic formula |
| `minBrakeDurationS` | `0.5 s` | Min time in BRAKE before transitioning to CAUTION |
| `minCautionDurationS` | `0.3 s` | Min time in CAUTION before transitioning to CLEAR |
| `depthEmaAlphaApproaching` | `0.5` | EMA alpha when obstacle closing (react fast) |
| `depthEmaAlphaReceding` | `0.3` | EMA alpha when obstacle opening (slow release) |
| `fallbackSpeedMPS` | `0.3 m/s` | Conservative speed when sensors unavailable |

---

## 4. Zone Boundary Formulas

Each boundary is the **maximum** of three components:

```
brakeDistance = max( d_brake_min,       v × TTC_brake,      v² / (2 × a_max) )
              = max( 0.30 m,            v × 0.3 s,          v² / (2 × 2.5 m/s²) )

clearDistance = max( d_caution_min,     v × TTC_caution,    v² / (2 × a_max) )
              = max( 0.50 m,            v × 0.8 s,          v² / (2 × 2.5 m/s²) )
```

The three components serve different regimes:
- **Hard floor** (`minBrakeDistanceM`, `minCautionDistanceM`): Dominates below **1.0 m/s for brake** and **0.625 m/s for clear**. Sized so the robot's kinematic overshoot lands well inside the BRAKE zone even at low speed, preventing the BRAKE→CAUTION slip.
- **TTC term** (`v × ttcS`): Dominates at typical indoor speeds (1.0–1.5 m/s). Gives 0.3 s and 0.8 s of reaction time.
- **Kinematic term** (`v² / 2a`): Overtakes TTC above **1.5 m/s for brake** (crossover: `v × 0.3 = v²/5` → `v = 1.5 m/s`). Above that, braking distance grows quadratically.

### Worked Examples

| Speed | v × 0.3 s | v² / 5.0 | **brakeDistance** | v × 0.8 s | **clearDistance** | CAUTION band | Dominant (brake) |
|-------|-----------|----------|-------------------|-----------|-------------------|--------------|------------------|
| **0.1 m/s** | 0.03 m | 0.002 m | **0.30 m** | 0.08 m | **0.50 m** | 0.20 m | hard floor |
| **0.2 m/s** | 0.06 m | 0.008 m | **0.30 m** | 0.16 m | **0.50 m** | 0.20 m | hard floor |
| **0.3 m/s** | 0.09 m | 0.018 m | **0.30 m** | 0.24 m | **0.50 m** | 0.20 m | hard floor |
| **0.5 m/s** | 0.15 m | 0.050 m | **0.30 m** | 0.40 m | **0.50 m** | 0.20 m | hard floor |
| **1.0 m/s** | 0.30 m | 0.200 m | **0.30 m** | 0.80 m | **0.80 m** | 0.50 m | floor = TTC (tie) |
| **1.5 m/s** | 0.45 m | 0.450 m | **0.45 m** | 1.20 m | **1.20 m** | 0.75 m | TTC = kinematic (tie) |
| **2.0 m/s** | 0.60 m | 0.800 m | **0.80 m** | 1.60 m | **1.60 m** | 0.80 m | kinematic |

**Low-speed overshoot vs brake floor (why the slip is now fixed):**

| Speed | Kinematic overshoot (a=2.5) | Robot stops at | Margin below brakeDistance |
|-------|----------------------------|----------------|---------------------------|
| 0.2 m/s | 0.008 m | **0.29 m** | 1 cm — marginal under old 0.15 m floor |
| 0.2 m/s | 0.008 m | **0.29 m** | **1 cm below new 0.30 m floor** — EMA drift possible → **fixed by wider band** |
| 0.5 m/s | 0.050 m | **0.25 m** | **5 cm below 0.30 m floor** — CAUTION scale at 0.25 m = 0% ✓ |
| 1.0 m/s | 0.200 m | **0.10 m** | **20 cm below 0.30 m floor** — safely locked in BRAKE ✓ |

**At 0.5 m/s:** BRAKE at 0.30 m, CLEAR above 0.50 m — 20 cm CAUTION ramp.
**At 1.0 m/s:** BRAKE at 0.30 m, CLEAR above 0.80 m — 50 cm CAUTION ramp.
**At 2.0 m/s:** BRAKE at 0.80 m (kinematic dominates), CLEAR above 1.60 m — 80 cm CAUTION ramp.

---

## 5. Safety Policy: Tri-Zone State Machine

| Zone        | Condition                                  | Action                          |
|-------------|--------------------------------------------|---------------------------------|
| **CLEAR**   | `filteredDepth > 0.50 m` (at 0.5 m/s)      | Pass command unchanged          |
| **CAUTION** | `0.30 m ≤ filteredDepth ≤ 0.50 m`          | Scale throttle linearly to 0    |
| **BRAKE**   | `filteredDepth < 0.30 m`                   | Full stop                       |

### Latched Speed

When the supervisor detects a threat (CLEAR → CAUTION or BRAKE), it **latches the current speed**. All subsequent threshold calculations use `max(latchedSpeed, currentSpeed)` until the state returns to CLEAR.

**Why this matters:** Without latching, braking reduces speed, which shrinks `brakeDistance`, which releases the brake, which re-accelerates — a positive feedback loop. With latching, the thresholds stay at the values that triggered the alert, so the robot must actually drive away from the obstacle (depth genuinely increases) before receiving any forward motion.

*Example:* Robot is at 1.0 m/s and sees an obstacle at 0.28 m → BRAKE. Speed falls to 0 m/s. Without latching: brakeDistance drops to 0.30 m (floor), which would immediately release brake at 0.28 m. With latching: brakeDistance stays at 0.30 m and clearDistance stays at 0.80 m, so the robot remains braked until depth genuinely exceeds 0.80 m.

### Cooldown Timers

- BRAKE persists for at least **0.5 s** before transitioning to CAUTION.
- CAUTION persists for at least **0.3 s** before transitioning to CLEAR.
- BRAKE always goes through CAUTION — never directly to CLEAR.

**Why mandatory CAUTION exit:** Even after depth crosses 0.75 m, the robot eases back in at reduced throttle for 0.3 s rather than snapping to full speed.

### State Transition Diagram

```
                     depth ≥ 0.80m AND cooldown ≥ 0.3s
               ┌──────────────────────────────────────────┐
               │                                          │
    ┌──────────▼──────────┐    depth < 0.80m        ┌─────▼───────────┐
    │       CLEAR         │───────────────────────-▶│    CAUTION      │
    │  (pass unchanged)   │                         │ (scale throttle)│
    └─────────────────────┘                         └───────┬─────────┘
                                                            │
                                                    depth < 0.30m
                                                            │
                                                   ┌────────▼────────┐
                                                   │     BRAKE       │
                                                   │  (full stop)    │
                                                   └─────────────────┘
                                                    exit: hold ≥ 0.5s
                                                    → CAUTION (0.3s)
                                                    → CLEAR
```

*(Distances shown at 1.0 m/s. They scale with speed as per Section 4.)*

---

## 6. Depth Filtering (Asymmetric EMA)

Raw LiDAR depth is smoothed with an Exponential Moving Average:

```
filteredDepth = α × rawDepth + (1 - α) × filteredDepth_prev
```

**Asymmetric alphas:**
- **Approaching** (`rawDepth < filtered`): `α = 0.5` — 50% weight on new reading.
- **Receding** (`rawDepth > filtered`): `α = 0.3` — 30% weight on new reading.

### Settling Time in Practice (at 30 fps LiDAR)

| Direction | α | Frames to reach 90% of step | Wall-clock time |
|-----------|---|------------------------------|-----------------|
| Approaching (obstacle appears) | 0.5 | ~3 frames | ~100 ms |
| Receding (obstacle clears) | 0.3 | ~6 frames | ~200 ms |

*Example:* A wall appears 0.50 m away while filtered depth is 2.0 m. After 1 frame: `0.5×0.50 + 0.5×2.0 = 1.25 m`. After 2 frames: `0.875 m`. After 3 frames: `0.69 m` — now inside the CAUTION zone at 0.5 m/s.

The asymmetry is intentional: the system snaps toward danger quickly (3 frames / ~100 ms) but releases slowly (6 frames / ~200 ms). A brief LiDAR dropout or single corrupt reading will not release a brake — the receding filter smooths it out.

---

## 7. CAUTION Zone Throttle Scaling

In the CAUTION zone, throttle is linearly interpolated:

```
scale = (filteredDepth - brakeDistance) / (clearDistance - brakeDistance)
outputThrottle = plannerThrottle × clamp(scale, 0, 1)
```

**At 0.5 m/s, with brakeDistance=0.30 m and clearDistance=0.50 m (range=0.20 m):**

| filteredDepth | scale = (d − 0.30) / 0.20 | outputThrottle (if planner=100%) |
|---------------|---------------------------|----------------------------------|
| 0.50 m | 1.00 | 100% |
| 0.45 m | 0.75 | 75% |
| 0.40 m | 0.50 | 50% |
| 0.35 m | 0.25 | 25% |
| 0.30 m | 0.00 | 0% → enters BRAKE |

**At 1.0 m/s, with brakeDistance=0.30 m and clearDistance=0.80 m (range=0.50 m):**

| filteredDepth | scale = (d − 0.30) / 0.50 | outputThrottle (if planner=100%) |
|---------------|---------------------------|----------------------------------|
| 0.80 m | 1.00 | 100% |
| 0.675 m | 0.75 | 75% |
| 0.55 m | 0.50 | 50% |
| 0.425 m | 0.25 | 25% |
| 0.30 m | 0.00 | 0% → enters BRAKE |

---

## 8. `SafetySupervisorEvent`

```swift
struct SafetySupervisorEvent: Equatable {
    let timestamp: TimeInterval
    let ttc: Float
    let forwardDepth: Float     // raw depth
    let filteredDepth: Float    // EMA-smoothed depth

    enum Action: Equatable {
        case clear
        case caution(throttleScale: Float, reason: String)
        case brakeApplied(String)
    }

    let action: Action
}
```

---

## 9. Extensibility

Future versions can:
- Sample a forward cone instead of one pixel
- Add lateral obstacle detection for steering constraints
- Add speed-adaptive EMA alpha (faster filtering at higher speeds)
- Log full state machine trace for offline analysis
