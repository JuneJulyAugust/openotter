# LQRTrack Speed And Steering Control Design

**Status:** Initial implementation behind `/figure8_lqr`, not the default `/figure8` controller
**Date:** 2026-06-15
**Baseline controller:** `TangentTrack`
**Experimental controller:** `LQRTrack`
**References:**

- PythonRobotics LQR speed/steer example:
  `https://github.com/AtsushiSakai/PythonRobotics/tree/master/PathTracking/lqr_speed_steer_control`
- PythonRobotics technical page:
  `https://atsushisakai.github.io/PythonRobotics/modules/6_path_tracking/lqr_speed_and_steering_control/lqr_speed_and_steering_control.html`
- Source function:
  `https://raw.githubusercontent.com/AtsushiSakai/PythonRobotics/master/PathTracking/lqr_speed_steer_control/lqr_speed_steer_control.py`

## 1. Why A Second Controller

`TangentTrack` is the current field controller. It projects the car onto the
figure-eight path, computes tangent heading and cross-track error, then uses
PID-shaped steering plus curvature feedforward. That is practical and easy to
debug, so it should remain the default baseline.

`LQRTrack` is the experimental controller now available for comparison. Its
goal is not to be more complicated for its own sake. Its goal is to control
the main tracking errors together:

- lateral position error,
- lateral error rate,
- heading error,
- heading error rate,
- speed error.

That matters because the field traces show coupled behavior: when steering is
late, the blue trajectory balloons outside the lobe; when throttle slows too
much, the car can turn but crawls. LQR gives one framework for trading those
errors against steering and throttle effort.

## 2. Scope

This design keeps `TangentTrack` as `/figure8` and adds `LQRTrack` as a
separate selectable controller:

```text
/figure8      -> TangentTrack baseline
/figure8_lqr  -> LQRTrack experiment
```

Do not silently replace the known-good baseline. LQR needs field tuning because
OpenOtter does not yet measure front wheel angle, and throttle is a normalized
ESC command rather than a direct acceleration command.

## 3. Shared Path Reference

Both controllers should use the same figure-eight path and coordinate
convention:

```text
PoseMapView screen up    = local +X forward
PoseMapView screen right = local +Z right
length = 3.2 m along +Z/-Z
width  = 1.6 m along +X/-X
```

`FigureEightTrajectory` remains the path generator. Both controllers use the
same shared helper:

```text
PathReference.project(pose, waypoints, currentIndex)
  -> nearest/progress index
  -> projected path point
  -> tangent yaw
  -> signed cross-track error
  -> curvature
  -> target speed
```

That lets `TangentTrack` and `LQRTrack` compare controllers without changing
the trajectory.

## 4. LQR State And Inputs

Use the same core state as the PythonRobotics LQR speed/steer controller, with
OpenOtter sign conventions:

```text
x = [
  e,          # LQR lateral state, metres
  e_dot,      # lateral error rate, metres/second
  theta_e,    # heading error to path tangent, radians
  theta_dot,  # heading error rate, radians/second
  v_e         # measured speed - target speed, metres/second
]

u = [
  steering_feedback,
  acceleration_feedback
]
```

OpenOtter reference signs:

- `crossTrackError > 0`: car is right of the path.
- `theta_e = pose.yaw - referenceYaw`.
- Positive normalized steering means right.
- `LQRTrack` feeds `e = -crossTrackError` into the LQR state. This makes a
  right-of-path error produce left steering while keeping positive heading
  error as a right-steering correction.
- If the path reference jumps far ahead during reacquisition, derivative
  memory is reset so stale lateral-error rate does not dominate steering.

The PythonRobotics example computes steering as curvature feedforward plus LQR
feedback, and acceleration as the second LQR output. OpenOtter should keep that
shape, but convert outputs into normalized actuator commands.

## 5. Model

Use a discrete linear bicycle-like model around the current path tangent and
speed:

```text
x[k + 1] = A x[k] + B u[k]
cost = sum(x^T Q x + u^T R u)
u = -K x
```

The practical OpenOtter matrices can start from the PythonRobotics structure:

```text
A =
[1, dt, 0,  0, 0]
[0, 0,  v,  0, 0]
[0, 0,  1, dt, 0]
[0, 0,  0,  0, 0]
[0, 0,  0,  0, 1]

B =
[0,       0]
[0,       0]
[0,       0]
[v/L,     0]
[0,      dt]
```

For OpenOtter, `L` is an effective wheelbase/tuning length, not a precise
calibrated model. Start with the physical wheelbase if known; otherwise use a
config value such as `0.30...0.50 m` and tune from logs.

## 6. Feedforward And Actuator Mapping

LQR should not do all steering work from feedback. Keep curvature feedforward:

```text
steering_ff = -curvatureFeedforwardGain * curvature
```

Then add LQR feedback:

```text
steering = clamp(steering_ff + steeringScale * steering_feedback, -1, 1)
```

Speed control is harder because OpenOtter does not command acceleration
directly. Use the LQR acceleration output as a throttle trim around a base
throttle:

```text
baseThrottle = throttleForTargetSpeed(targetSpeedMps)
throttle = clamp(baseThrottle + throttleAccelScale * acceleration_feedback,
                 0,
                 maxThrottle)
```

Initial target speed should stay conservative:

```text
targetSpeedMps = 0.18...0.25 m/s
maxThrottle = current Telegram speed, default 0.4
```

`targetSpeedMps` and `baseThrottle` should be logged. Without calibration, the
controller must be robust if the same throttle produces different speed on
tile, concrete, or carpet.

## 7. Q/R Tuning

Start with diagonal weights. Larger `Q` means "care more about this error";
larger `R` means "use less actuator effort."

Recommended initial intent:

```text
Q lateral error       high
Q heading error       high
Q speed error         medium
Q error rates         low to medium
R steering effort     medium
R throttle effort     medium to high
```

Conservative first values:

```text
Q = diag([3.0, 0.2, 2.5, 0.2, 0.8])
R = diag([1.0, 2.0])
```

If the car balloons outside the lobe, raise lateral/heading `Q` or lower
steering `R`. If steering chatters or the servo ticks, raise steering `R`,
increase derivative filtering, or reduce `steeringScale`. If the car crawls,
raise target speed or lower throttle `R`, but keep the safety supervisor as the
final arbiter.

## 8. Implementation

Implemented code structure:

```text
openotter-ios/Sources/Planner/PathReference.swift
  Shared path projection, tangent, curvature, and progress helper.

openotter-ios/Sources/Planner/Controllers/LQRMath.swift
  Small fixed-size matrix utilities and DARE solver.

openotter-ios/Sources/Planner/Planners/LQRTrackPlanner.swift
  PlannerProtocol implementation for figure-eight LQR speed/steer.

openotter-ios/Sources/Planner/PlannerProtocol.swift
  Add controller selection to followFigureEight goals.

openotter-ios/Sources/Agent/KeywordInterpreter.swift
openotter-ios/Sources/Agent/ActionDispatcher.swift
  Adds /figure8_lqr command and keeps /figure8 on TangentTrack.

tools/trajectory-sim/
  Local Python package for controller prototyping, deterministic simulation,
  and SVG comparison plots.
```

Do not add a heavy math dependency. The state is only 5 values and the input is
2 values, so a deterministic small-matrix implementation is enough for iOS.

## 9. Tests

Initial implementation coverage:

- `LQRMathTests`: DARE converges for a known small system, output gain is
  finite, matrix inverse rejects singular inputs.
- `LQRTrackPlannerTests`: right-of-path error commands left steering, left
  error commands right steering, reference reacquire resets derivative memory,
  below target speed increases throttle, above target speed reduces throttle,
  and the deterministic slow-yaw model makes progress inside the envelope.
- `ActionDispatcherTests` and `AgentRuntimeTests`: `/figure8_lqr` routes to the
  LQR controller without changing `/figure8`.
- `tools/trajectory-sim/tests`: Python path shape, arc-length sampling,
  TangentTrack/LQRTrack progress, speed feedback, and lateral sign behavior.

## 10. Rollout Criteria

`LQRTrack` is safe to field-test as an explicit experiment after these remain
true:

- simulator tests pass,
- output steering is always finite and clamped to `[-1, 1]`,
- throttle is always finite and clamped to `[0, maxThrottle]`,
- DARE fallback is deterministic,
- map overlay still shows the same reference trajectory and arrows,
- `/figure8` still runs `TangentTrack`.

If the LQR gain solve fails or produces non-finite output, the planner should
emit neutral for that tick and log the failure. Do not silently send stale
steering or throttle.
