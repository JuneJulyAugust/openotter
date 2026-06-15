# LQRTrack Technical Note

**Status:** Technical note for initial `LQRTrack` implementation
**Date:** 2026-06-15
**Companion design:** `docs/superpowers/specs/2026-06-15-lqr-track-design.md`

## 1. Plain-English Idea

`TangentTrack` controls steering with a PID-like heading loop and shapes
throttle with practical rules. `LQRTrack` controls steering and speed from one
shared math problem.

The controller keeps a short list of errors:

```text
1. How far sideways am I from the path?
2. Is that sideways error growing or shrinking?
3. How far is my heading from the path direction?
4. Is that heading error growing or shrinking?
5. Am I faster or slower than the target speed?
```

LQR chooses steering and speed corrections that make those errors small while
also avoiding excessive actuator effort. In high-school-math terms: it tries
to minimize a weighted score where large errors and large commands cost more.

## 2. Cost Function

The score LQR minimizes is:

```text
cost = sum(x^T Q x + u^T R u)
```

Read it as:

- `x` is the error list.
- `u` is the command correction list.
- `Q` says which errors are most important.
- `R` says how much we dislike strong steering or throttle changes.

If lateral error matters more, raise its `Q`. If steering is too aggressive,
raise steering `R`. The result is a gain matrix `K`:

```text
u = -K x
```

This means the controller multiplies the current errors by a precomputed gain
and sends the opposite correction.

## 3. State Vector

Use this state:

```text
x = [
  e,
  e_dot,
  theta_e,
  theta_dot,
  v_e
]
```

Definitions:

```text
e          LQR lateral state, metres
e_dot      (e - previous_e) / dt
theta_e    wrapToPi(pose.yaw - referenceYaw)
theta_dot  wrapToPi(theta_e - previous_theta_e) / dt
v_e        measuredSpeedMps - targetSpeedMps
```

OpenOtter sign convention:

```text
crossTrackError > 0 means the car is right of the path.
LQR state e = -crossTrackError.
positive steering means steer right.
theta_e > 0 means the car yaw is left of the path tangent.
```

That sign conversion is deliberate. A car right of the path should usually
steer left, while a positive heading error at the center crossing should steer
right to align with the first forward/right branch. The sign tests verify this
directly, because sign mistakes are easy and field-visible.

## 4. Path Reference

For each control tick:

```text
P0 = waypoint[currentIndex]
P1 = waypoint[currentIndex + 1]
segment = P1 - P0
projection = clamp(dot(pose - P0, segment) / dot(segment, segment), 0, 1)
referencePoint = P0 + projection * segment
referenceYaw = atan2(-(P1.z - P0.z), P1.x - P0.x)
pathRight = (sin(referenceYaw), cos(referenceYaw))
crossTrackError = dot(pose - referencePoint, pathRight)
e = -crossTrackError
curvature = smoothed heading change / arc length
```

This uses the same app-map convention as `TangentTrack`:

```text
screen up    = +x forward
screen right = +z right
figure-eight length = 3.2 m along +Z/-Z
figure-eight width  = 1.6 m along +X/-X
```

## 5. Linear Model

LQR needs a simple prediction model:

```text
x[k + 1] = A x[k] + B u[k]
```

The initial model should follow the PythonRobotics LQR speed/steer structure:

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

Where:

```text
dt = control time step, seconds
v  = measured speed, metres/second
L  = effective wheelbase/tuning length, metres
u[0] = steering feedback term
u[1] = acceleration feedback term
```

This is a simplified model. It does not know the actual front wheel angle. The
controller corrects using ARKit pose feedback, so the model only needs to be
good enough to choose useful corrections.

## 6. Solving For K

At each tick, or for each speed bucket, solve the discrete algebraic Riccati
equation:

```text
P_next = A^T P A
       - A^T P B (R + B^T P B)^-1 B^T P A
       + Q
```

Iterate until `P_next` changes very little or a fixed iteration cap is reached.
Then compute:

```text
K = (R + B^T P B)^-1 B^T P A
```

Because the matrix sizes are fixed and small, the Swift implementation can use
small deterministic matrix helpers instead of adding a math package.

Safety rule:

```text
if any matrix value is NaN, infinite, or singular:
    output neutral for this tick
    log LQR solve failure
```

## 7. Feedforward Plus Feedback

The path curvature already tells us that the car should start turning before
the error grows. Keep feedforward:

```text
steering_ff = -curvatureFeedforwardGain * curvature
```

Then add LQR feedback. The discrete LQR solve returns `K`, and the conventional
control law is `u = -Kx`. Because OpenOtter steering command sign is opposite
the bicycle steering angle sign used in the model, the normalized steering
command uses the converted feedback sign:

```text
feedback = K * x
steering_fb = steeringScale * feedback[0]
steering = clamp(steering_ff + steering_fb, -1, 1)
```

Speed control uses the acceleration output as a throttle trim:

```text
u = -K x
baseThrottle = throttleForTargetSpeed(targetSpeedMps)
throttleTrim = throttleAccelScale * u[1]
throttle = clamp(baseThrottle + throttleTrim, 0, maxThrottle)
```

OpenOtter does not command acceleration directly, so `throttleAccelScale` is a
tuning constant. Start small and tune from logs.

## 8. Target Speed

Start with a simple speed profile:

```text
targetSpeedMps = 0.20 m/s
```

Later, the speed profile can slow slightly at high curvature:

```text
curvatureLoad = clamp(abs(curvature) / curvatureSlowdownAt, 0, 1)
targetSpeed = maxSpeed - (maxSpeed - minSpeed) * curvatureLoad
```

Do not start with aggressive speed scheduling. First prove that LQR can follow
the same 3.2 m by 1.6 m figure eight at a stable speed.

## 9. Pseudocode

### Planner Tick

```text
plan(context):
    if pendingFigureEightConfig exists:
        waypoints = FigureEightTrajectory.waypoints(
            config = pendingFigureEightConfig,
            anchor = context.pose
        )
        currentIndex = 0
        clear previous errors

    if waypoints is empty:
        return neutral

    reference = PathReference.project(
        pose = context.pose,
        waypoints = waypoints,
        currentIndex = currentIndex,
        progressWindow = 32
    )

    currentIndex = reference.index
    dt = clamp(context.timestamp - previousTimestamp, 0.02, 0.25)
    measuredSpeed = bestFinite(context.motorSpeedMps, context.arkitSpeedMps) or 0
    targetSpeed = targetSpeedFor(reference.curvature)

    e = -reference.crossTrackError
    thetaE = wrapToPi(context.pose.yaw - reference.tangentYaw)
    if reference.index jumps more than 8 samples from previousReferenceIndex:
        previousE = e
        previousThetaE = thetaE

    eDot = (e - previousE) / dt
    thetaDot = wrapToPi(thetaE - previousThetaE) / dt
    vError = measuredSpeed - targetSpeed

    state = [e, eDot, thetaE, thetaDot, vError]

    A, B = modelMatrices(dt, measuredSpeed, effectiveWheelbase)
    K = solveLQR(A, B, Q, R)

    if K is invalid:
        return neutral with source "LQRTrack"

    feedback = K * state
    u = -feedback
    steeringFF = -curvatureFeedforwardGain * reference.curvature
    steering = clamp(steeringFF + steeringScale * feedback[0], -1, 1)

    baseThrottle = baseThrottleForTargetSpeed(targetSpeed, maxThrottle)
    throttle = clamp(baseThrottle + throttleAccelScale * u[1], 0, maxThrottle)

    previousE = e
    previousThetaE = thetaE
    previousTimestamp = context.timestamp
    previousReferenceIndex = reference.index

    return ControlCommand(
        steering = steering,
        throttle = throttle,
        source = "LQRTrack"
    )
```

### Base Throttle

```text
baseThrottleForTargetSpeed(targetSpeed, maxThrottle):
    lowSpeed = 0.05
    nominalSpeed = 0.20
    minimumMovingThrottle = maxThrottle * 0.35

    if targetSpeed <= lowSpeed:
        return 0

    fraction = clamp(targetSpeed / nominalSpeed, 0, 1)
    return max(minimumMovingThrottle, maxThrottle * fraction)
```

### DARE Solver

```text
solveLQR(A, B, Q, R):
    P = Q

    repeat up to 150 iterations:
        S = R + transpose(B) * P * B
        if S cannot be inverted:
            return invalid

        Pnext = transpose(A) * P * A
              - transpose(A) * P * B * inverse(S) * transpose(B) * P * A
              + Q

        if maxAbs(Pnext - P) < 0.01:
            break

        P = Pnext

    K = inverse(R + transpose(B) * P * B) * transpose(B) * P * A
    return K
```

## 10. Initial Tuning Values

```text
dt clamp                  = 0.02...0.25 s
effectiveWheelbase        = 0.35 m
targetSpeedMps            = 0.20 m/s
maxThrottle               = Telegram speed, default 0.4
steeringScale             = 1.0
throttleAccelScale        = 0.15
curvatureFeedforwardGain  = 0.10 m

Q = diag([3.0, 0.2, 2.5, 0.2, 0.8])
R = diag([1.0, 2.0])
```

If the simulation understeers and the blue trace grows outside the reference,
increase lateral/heading `Q` or reduce steering `R`. If the steering servo
ticks, reduce `steeringScale` or increase steering `R`. If the car crawls while
tracking is stable, increase `targetSpeedMps` gradually.

## 11. Field Debug Values To Log

Log these per tick for comparison with `TangentTrack`:

```text
controllerName
pathIndex
crossTrackError
headingError
speedError
targetSpeedMps
measuredSpeedMps
curvature
steeringFeedforward
steeringFeedback
throttleBase
throttleFeedback
finalSteering
finalThrottle
lqrSolveStatus
```

The most useful comparison metrics are 95th-percentile cross-track error,
maximum envelope overshoot, average speed, and steering saturation time.
