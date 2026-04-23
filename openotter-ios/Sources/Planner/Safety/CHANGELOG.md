# Safety Supervisor — Changelog

History of the forward-collision safety policy that sits between the planner and the actuators. Each version corresponds to a meaningful change in the decision rule, not just a tuning pass.

## v1.0 — Time-to-Brake policy (2026-04-22)

Complete rewrite. Single critical distance formula derived from stopping physics; binary SAFE/BRAKE state machine; one latch rule for oscillation.

```
criticalDistance(v) = v · tSysS  +  v² / (2 · aMaxMPS2)  +  dMarginM
```

Three physically meaningful tunables (`tSysS`, `aMaxMPS2`, `dMarginM`) replace the eight ad-hoc parameters of v0.4. CAUTION zone, dual time-to-collision thresholds, absolute-distance floors, asymmetric smoothing alphas, and cooldown timers all removed. Release requires either `releaseHoldS` of continuous genuine clearance against the *latched* critical distance, or operator intervention via `throttle ≤ 0`.

New diagnostics: `SafetyBrakeRecord` captures the trigger snapshot plus, once the robot actually stops, a stop snapshot. Derived fields expose `stoppingTimeS`, `stoppingDistanceM`, `actualDecelMPS2`, `brakingDistanceM` — empirical counterparts that let field testing calibrate `aMaxMPS2` and `dMarginM`.

## v0.4.1 — Trigger snapshots (2026-04-04, commit 35d8ddf)

Captured a `SafetyTriggerSnapshot` (filtered depth, motor speed, ARKit speed) at the exact frame CAUTION or BRAKE was first entered. Displayed in the SAFETY HUD card and the emergency-brake overlay so operators could read the conditions that triggered each intervention. Frozen for the duration of the threat event.

## v0.4 — Tuning pass (commit 62b7596)

Tightened reaction windows and raised geometric floors after field testing showed low-speed brake-to-caution slip when kinematic overshoot landed too close to the threshold.

- `ttcBrakeS`: 0.8 → **0.3 s**
- `ttcCautionS`: 1.5 → **0.8 s**
- `maxDecelerationMPS2`: 1.5 → **2.5 m/s²** (matches measured tire grip)
- `minBrakeDistanceM`: 0.15 → **0.30 m**
- `minCautionDistanceM`: 0.25 → **0.50 m**

`DESIGN.md` rewritten with worked examples at each speed tier. Still the tri-zone machine from v0.3.

## v0.3 — Tri-Zone state machine (commit 59b12c5)

Fundamental policy redesign to kill the stop-go oscillation that plagued v0.2 at the time-to-collision boundary. Three failure modes were addressed together:

1. **Binary policy** → added a **CAUTION** zone between CLEAR and BRAKE, with linearly scaled throttle. The system now rolls off instead of snapping to zero.
2. **Speed-dependent threshold feedback loop** (braking drops speed → threshold shrinks → brake releases → accelerates → triggers again) → introduced **latched speed**: when entering CAUTION/BRAKE the current speed is frozen and used for all threshold calculations until CLEAR returns.
3. **Unfiltered depth** → added an **asymmetric exponential-moving-average** filter (fast alpha when approaching, slow when receding) to reject frame-to-frame LiDAR noise.

Added cooldown timers (`minBrakeDurationS`, `minCautionDurationS`) and forced BRAKE → CAUTION → CLEAR transitions so the robot eases back in rather than snapping to full throttle.

## v0.2 — Real speed for Time-to-Collision (commit 9d2e6a2)

Replaced the fixed `assumedSpeedMPS = 2.0` constant with `resolveSpeed()`, which prefers motor RPM from ESC telemetry, falls back to ARKit-derived speed from pose differentiation, and finally to a conservative 0.5 m/s estimate when neither is available. Brake reason strings now include the velocity so field logs are easier to read. Policy shape otherwise unchanged from v0.1.

## v0.1 — Initial Time-to-Collision supervisor (commit 781e6fc, shipped in app v0.7.0)

First forward-safety policy. Single scalar rule:

```
Time-to-Collision = forwardDepth / assumedSpeedMPS    (assumed = 2.0 m/s)
if Time-to-Collision < 1.0 s  →  full brake
else                          →  pass planner command through
```

No filtering, no hysteresis, no state memory. Depth taken straight from the center pixel of the ARKit scene-depth map. Served as the scaffold for the API surface (`supervise(command:context:)`, `SafetySupervisorEvent`) that every later version kept.
