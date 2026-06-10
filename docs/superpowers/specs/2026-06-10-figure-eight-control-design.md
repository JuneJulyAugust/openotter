# Figure-Eight Basement Control - Design

**Status:** Draft for review
**Date:** 2026-06-10
**Branch/worktree:** `control-figure-eight-design` at `.worktrees/control-figure-eight-design`

## 1. Goal

Make OpenOtter follow a repeatable figure-eight trajectory indoors using the
iPhone as the localization and control brain. The first target is a low-speed
basement run, not racing performance.

The design assumes a first-run envelope of roughly **3.0 m long by 1.8 m wide**
at **0.25-0.6 m/s**, with these values exposed as iOS tuning parameters. The
controller must still work if those numbers change.

## 2. Important Constraint

There is no front wheel angle or front wheel torque sensor. That means the app
cannot ask, "What steering angle did the wheels actually reach?"

The practical answer is feedback from vehicle motion:

1. iOS commands a steering PWM.
2. The car moves.
3. ARKit measures the new pose: position plus yaw.
4. The controller compares measured pose against the figure-eight path.
5. The next command corrects the error.

This is closed-loop control even without steering-angle feedback. The sensor is
the whole vehicle pose, not the steering linkage.

## 3. Existing System Fit

Current code already has the right split:

- `SelfDrivingViewModel` receives ARKit pose updates and sends actuator commands.
- `PlannerOrchestrator` owns Drive/Park mode and safety supervision.
- Planners implement `PlannerProtocol` and emit `ControlCommand`.
- Firmware receives FE41 command packets, clamps PWM, applies watchdog/Park
  behavior, and runs front/rear ToF brake safety.

The trajectory controller should therefore live in the iOS planner layer, not
in STM32 firmware. The firmware does not have the ARKit pose, map frame, path
definition, or sufficient floating-point trajectory context to own the figure
eight cleanly.

## 4. Considered Approaches

### A. Existing waypoint proportional controller

Use many waypoints around a figure eight and steer toward the next one.

Pros:
- Smallest code change.
- Easy to explain.

Cons:
- Cuts corners.
- Oscillates near waypoints.
- Does not know the curve shape, so throttle cannot slow down before tight turns.

Verdict: useful as a baseline, not good enough for the milestone.

### B. Pure pursuit path tracker with speed feedback

Generate a smooth sampled figure-eight path. Each tick, pick a target point a
short distance ahead on the path and steer along a circle that would hit that
point. Use speed feedback to slow down in tight curves.

Pros:
- Proven robot/car path tracking method.
- Only needs pose and speed feedback, which OpenOtter already has.
- Easy to test as pure Swift math.
- Good fit for missing steering-angle feedback.

Cons:
- Needs tuning of lookahead distance, max steering calibration, and speed gains.

Verdict: recommended first controller.

### C. Model predictive control or iLQR

Optimize steering/throttle over a future horizon using a vehicle model.

Pros:
- Can be excellent after calibration.
- Handles actuator limits naturally.

Cons:
- Needs a better dynamic model, steering calibration, latency estimates, and
  more implementation complexity.
- Harder to explain and debug during basement bring-up.

Verdict: later milestone after pure pursuit data exists.

## 5. Recommended Controller

Use **pure pursuit plus speed PI plus slow steering trim**.

The controller has three loops:

1. **Path loop:** "Where should the car be on the figure eight?"
2. **Steering loop:** "How sharply should I turn to reach a point ahead?"
3. **Speed loop:** "How much throttle gives the target speed for this curve?"

All three run on iOS in the planner layer.

## 6. Figure-Eight Path

Represent the figure eight as a sampled path in the ARKit ground plane.

Use a Gerono-style figure eight:

```text
local_x(t) = (length_m / 2) * sin(t)
local_z(t) = (width_m  / 2) * sin(2t)
```

where:

- `x` is forward in the OpenOtter robot frame.
- `z` is right in the OpenOtter robot frame.
- `t` goes from `0` to `2*pi`.
- `length_m` is the forward/back span.
- `width_m` is the left/right span.

The generator samples this curve into points. Each point stores:

```swift
struct TrajectoryPoint {
    let x: Float
    let z: Float
    let yaw: Float
    let curvature: Float
    let arcLength: Float
}
```

Runtime does not need symbolic calculus. It can estimate yaw and curvature from
neighboring samples. That keeps the implementation easy to verify.

When the operator presses "Figure 8", iOS anchors the path to the current ARKit
pose. The generated path is translated to the current position and rotated so
the path's initial tangent matches the car's current yaw.

## 7. Steering Math

The high-school version:

- A car following a turn is roughly following a circle.
- A tight turn has a small radius.
- A gentle turn has a large radius.
- Curvature is "how bendy the path is":

```text
curvature = 1 / radius
```

Each control tick:

1. Find the closest point on the sampled path.
2. Move forward along the path by `lookahead_m`.
3. Transform that lookahead point into the car's local coordinates:

```text
x_forward = how far ahead the target is
y_right   = how far right the target is
Ld        = distance to target
```

4. Pick the circle that starts at the car and reaches the target:

```text
curvature_cmd = 2 * y_right / (Ld * Ld)
```

If the target is to the right, `y_right` is positive and the car steers right.
If the target is to the left, `y_right` is negative and the car steers left.

5. Convert curvature into steering command using the bicycle model:

```text
steering_angle = atan(wheelbase_m * curvature_cmd)
steering_norm  = steering_angle / max_steering_angle_estimate
```

`steering_norm` is then clamped to `[-1, +1]` and sent through
`PwmMapping.toPulseWidth`.

The important point: `max_steering_angle_estimate` is only a calibration. If it
is a little wrong, the pose feedback still corrects the path error on later
ticks.

## 8. Missing Steering Sensor Compensation

Without a steering sensor, the command may be biased:

- servo horn not centered,
- steering linkage asymmetry,
- tire slip,
- carpet friction,
- battery voltage effects.

Add a slow trim term:

```text
steering_trim += trim_gain * cross_track_error * dt
steering_trim = clamp(steering_trim, -0.15, +0.15)
steering_cmd  = pure_pursuit_cmd + steering_trim
```

Plain English: if the car stays consistently to the right of the path, the app
slowly adds left steering until that steady error goes away. Because the trim is
small and slow, it corrects bias without fighting every frame of ARKit noise.

Reset trim when:

- the operator starts a new figure-eight run,
- ARKit tracking is limited/interrupted,
- Drive transitions to Park,
- the safety supervisor brakes.

## 9. Speed Control

Speed should be lower in tighter turns.

Sideways acceleration grows with speed squared:

```text
side_accel = speed * speed * abs(curvature)
```

So choose target speed:

```text
curve_speed = sqrt(max_side_accel / max(abs(curvature), min_curvature))
target_speed = min(cruise_speed, curve_speed)
```

Then use a PI throttle controller:

```text
speed_error = target_speed - measured_speed
integral += speed_error * dt
throttle = base_throttle + kp * speed_error + ki * integral
```

Rules:

- Prefer ESC speed from `PlannerContext.motorSpeedMps`.
- Fall back to ARKit speed from `PlannerContext.arkitSpeedMps`.
- If neither is reliable, use conservative open-loop throttle and cap speed.
- Rate-limit throttle changes, like `ConstantSpeedPlanner` already does.
- Freeze or decay the integral while safety is braking or depth is unavailable.

## 10. iOS Components

Add these components under `openotter-ios/Sources/Planner/`:

- `Trajectory/TrajectoryPoint.swift`
  - value types for sampled paths and tracking debug state.
- `Trajectory/FigureEightTrajectory.swift`
  - pure generator for sampled figure-eight paths.
- `Trajectory/PathProjection.swift`
  - closest-point search and lookahead target selection.
- `Planners/PathTrackingPlanner.swift`
  - implements `PlannerProtocol`.
  - owns pure-pursuit steering, trim, speed target, and throttle PI.
- `Planners/PathTrackingConfig.swift`
  - basement-safe defaults and tuning bounds.

Modify existing files:

- `PlannerProtocol.swift`
  - add `PlannerGoal.followTrajectory(...)` or `PlannerGoal.figureEight(...)`.
- `PlannerOrchestrator.swift`
  - expose last path-tracking debug state for HUD/map display.
- `SelfDrivingViewModel.swift`
  - add `startFigureEight(config:)`, create the anchored trajectory from the
    current pose, swap to `PathTrackingPlanner`, and call `setGoal`.
- `PoseMapView.swift`
  - draw the sampled trajectory as a path, not only waypoint markers.
- `SelfDrivingView.swift`
  - add a compact Figure 8 control surface: length, width, cruise speed, laps,
    start/park, and live path error.
- `KeywordInterpreter.swift` / `ActionDispatcher.swift` (optional)
  - add a "figure eight" agent command after manual UI works.

## 11. Firmware Components

Do **not** put trajectory tracking on STM32 for this milestone.

Keep firmware responsibilities narrow:

- accept iOS commands,
- clamp PWM,
- enforce Park/Drive behavior,
- neutralize stale commands,
- run ToF safety supervisors,
- expose enough status for tuning.

Recommended firmware work:

1. Add an FE42 control-side drive status payload.
2. Include desired and applied steering/throttle after arbitration.
3. Include watchdog and safety clamp flags.
4. Parse that status in iOS for HUD/logging.

This is not required for the first path-tracking unit tests, but it is valuable
for real basement tuning because it distinguishes "planner sent X" from
"firmware actually applied Y after safety arbitration."

Possible payload:

```c
typedef struct __attribute__((packed)) {
  uint32_t seq;
  uint32_t timestamp_ms;
  int16_t desired_steering_us;
  int16_t desired_throttle_us;
  int16_t applied_steering_us;
  int16_t applied_throttle_us;
  uint8_t mode;
  uint8_t flags; /* bit0 watchdog, bit1 front_brake, bit2 rear_brake */
} BLE_DriveStatusPayload_t;
```

## 12. Control Loop Ownership

The controller code belongs in:

```text
openotter-ios/Sources/Planner/
```

not in:

```text
firmware/stm32-mcp/Core/
```

Reason: the controller is high-level policy. It depends on ARKit pose, path
geometry, map state, speed estimates, and operator intent. Firmware is low-level
actuation and safety. Keeping that split preserves the current architecture:

```text
ARKit pose + planner + safety policy (iOS)
        -> FE41 command
        -> PWM clamp/watchdog/safety arbitration (STM32)
        -> steering servo + ESC
```

## 13. Tuning Defaults

Initial safe defaults:

```text
length_m = 3.0
width_m = 1.8
laps = 1
sample_count = 240
lookahead_min_m = 0.35
lookahead_time_s = 0.7
cruise_speed_mps = 0.35
max_speed_mps = 0.6
max_side_accel_mps2 = 0.6
wheelbase_m = use RobotGeometry constant after measurement
max_steering_angle_deg_est = 28
steering_trim_limit = 0.15
throttle_rate_limit_per_s = 0.5
```

Lookahead should grow with speed:

```text
lookahead_m = clamp(speed_mps * lookahead_time_s,
                   lookahead_min_m,
                   lookahead_max_m)
```

## 14. Test Strategy

Pure iOS tests first:

- figure-eight generator fits requested bounds,
- generated path is closed,
- anchor rotation aligns start tangent with pose yaw,
- closest-point projection advances monotonically,
- pure pursuit steering sign is correct,
- straight-ahead target gives near-zero steering,
- target to right gives positive steering,
- curvature speed cap slows sharp turns,
- throttle PI increases command when measured speed is low,
- trim slowly compensates persistent cross-track bias,
- ARKit coordinate invariant matches `RobotGeometry`.

Firmware host tests if FE42 status is added:

- payload size and little-endian fields,
- desired/applied PWM fields reflect arbitration,
- watchdog flag set when stale command neutralizes throttle,
- Park mode reports neutral applied throttle.

Field tests:

- start with wheels off ground and verify PWM signs,
- run a 1.5 m x 1.0 m low-speed figure eight,
- increase to 3.0 m x 1.8 m only after steering sign and safety behavior are
  verified,
- record cross-track error, heading error, steering command, throttle, speed,
  and safety state for every tick.

## 15. Open Decisions

1. Exact basement envelope.
2. Measured wheelbase.
3. Approximate max steering angle at full PWM.
4. Whether FE42 drive status should be in the first implementation PR or a
   follow-up after iOS-only path tracking is proven in simulation/tests.
