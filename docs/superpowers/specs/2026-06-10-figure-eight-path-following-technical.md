# Figure-Eight Path Following Technical Note

**Status:** Companion technical document for tangent-heading PID/feedforward control
**Date:** 2026-06-10
**Feature:** Telegram/iOS `/figure8` basement trajectory following

## 1. What The Controller Is Trying To Do

The car does not know its front wheel angle. That removes a common feedback
signal, but it does not prevent feedback control. The iOS app still has an
estimated car pose from ARKit:

```text
pose.x      ground-plane x position, metres
pose.z      ground-plane z position, metres
pose.yaw    heading angle, radians
```

The controller's job is:

1. Generate a figure-eight path near the car.
2. Pick the current segment on that path.
3. Measure the path tangent heading and the car's side error from the segment.
4. Turn with PID-shaped heading feedback plus curvature feedforward.
5. Command enough throttle to keep moving, while slowing down when the car is
   steering hard away from the centerline.
6. Let the safety supervisor override the command if ToF depth says the car
   should brake.

This is feedback control because every control tick recomputes steering and
throttle from the newest pose estimate. The controller does not need to know
the actual wheel angle; it watches the car's motion and corrects the next
command.

## 2. Coordinate System

OpenOtter planner code uses a 2D ground-plane model:

```text
+x = robot forward when yaw = 0
+z = robot right when yaw = 0
```

That is enough for basement driving because the car is treated as moving on a
flat floor. Height, roll, and pitch are ignored by this controller.

For a given yaw angle, the car's local forward and right directions in world
coordinates are:

```text
forward_world = ( cos(yaw), -sin(yaw))
right_world   = ( sin(yaw),  cos(yaw))
```

These formulas are just a rotation. At `yaw = 0`, `cos(0) = 1` and
`sin(0) = 0`, so:

```text
forward_world = (1, 0)
right_world   = (0, 1)
```

That matches the planner convention.

To convert a point from car-local coordinates into ARKit world coordinates:

```text
world.x = anchor.x + local_x * forward_world.x + local_z * right_world.x
world.z = anchor.z + local_x * forward_world.z + local_z * right_world.z
```

This is why `/figure8` is now anchored inside `WaypointPlanner.plan(context:)`.
The Telegram command does not know the current pose, but the planner does.

## 3. Figure-Eight Path Shape

The path generator uses a smoother Bernoulli-style figure eight:

```text
theta = t + pi / 2
raw_x = -cos(theta) / (1 + sin(theta)^2)
raw_z = -sin(theta) * cos(theta) / (1 + sin(theta)^2)
```

where `t` moves from `0` to `2 * pi`. The `pi / 2` shift makes `t = 0`
the center crossing, and the negative signs make the first segment move
forward/right. The raw curve is normalized to the configured length and width,
then resampled by arc length so neighboring controller waypoints are nearly
evenly spaced.

Intuition:

- The curve still forms the requested sideways "8".
- The lobes are rounder than the earlier Gerono curve.
- Arc-length spacing gives the tangent-heading controller a smooth reference
  direction from segment to segment.

The current command defaults are:

```text
segmentCount      = 240
length            = 3.2 m
width             = 1.6 m
acceptanceRadius  = 0.12 m
maxThrottle       = current Telegram speed, with no hidden boost
default /figure8  = 0.4
```

`segmentCount` turns the smooth curve into a list of waypoints. With 240
segments, neighboring waypoints are close enough for smooth steering, but not
so dense that the controller spends all its time advancing tiny steps. The
`3.2 m x 1.6 m` envelope is 80% of the previous `4.0 m x 2.0 m` default, which
preserves the reference shape while adding wall margin for real tracking lag.

## 4. Horizontal Infinity Shape And Start

The requested shape is a horizontal infinity track: two side-by-side lobes
that cross in the center, like the reference image. The current generator keeps
that literal shape in the robot frame:

```text
+x = long axis of the figure eight
+z = right side of the figure eight
```

Waypoint `0` is the center crossing at the car's pose when `/figure8` starts.
The first few waypoints move forward and right into the first lobe. Halfway
through the waypoint list, the path returns to the center crossing and enters
the other lobe.

The initial tangent is diagonal:

```text
tangent points forward and right
```

With full normalized steering authority, firmware-side PWM clamping/slew,
smoother curve, smaller path, and arc-length spacing, that diagonal start is
practical. It also preserves the requested visual shape.
The earlier implementation
rotated the curve to make this tangent point forward; that made the math tidy
but made the plotted path less like the requested horizontal track.

The whole local path is still transformed through the car's yaw, so the
horizontal infinity is horizontal relative to the car's starting heading, not
hard-coded to an arbitrary ARKit world axis.

## 5. Waypoint Advancement

The controller stores:

```text
waypoints
currentWaypointIndex
isClosedLoop
```

On each tick, it checks whether the car is close enough to the current
waypoint:

```text
distance = sqrt((target.x - pose.x)^2 + (target.z - pose.z)^2)
reached = distance < target.acceptanceRadius
```

If reached, the controller advances to the next waypoint.

For a closed-loop figure eight, the controller also searches a short window of
future waypoints and advances to the closest one. This matters in real driving:
if the car misses a waypoint by more than the acceptance radius, a naive
controller keeps turning back toward that stale waypoint. On a tight lobe that
looks exactly like the map screenshot: the car circles one loop and never
commits to the crossing.

For normal finite waypoint missions:

```text
after final waypoint -> output neutral
```

For figure-eight missions:

```text
after final waypoint -> wrap back to waypoint 0
if a future waypoint in the progress window is closer -> skip ahead to it
```

That makes `/figure8` continue until the operator sends Stop/Park.

## 6. Steering Control

Finite waypoint missions still use the original bearing-to-waypoint rule. The
closed-loop figure-eight mission uses a path-reference controller instead,
because the field trace showed that chasing a point can orbit outside a lobe
when the car's yaw response is slow.

For the active path segment:

```text
P0 = waypoint[currentWaypointIndex]
P1 = waypoint[currentWaypointIndex + 1]
segment = P1 - P0
```

The controller projects the car position onto this segment:

```text
alpha = clamp(dot(pose - P0, segment) / dot(segment, segment), 0, 1)
referencePoint = P0 + alpha * segment
```

Then it derives the reference heading from the segment tangent:

```text
referenceYaw = atan2(-(P1.z - P0.z), P1.x - P0.x)
```

This is the key upgrade. `referenceYaw` is the direction of the path, not the
bearing from the car to a future dot. If the path is turning through the lobe,
the controller knows the heading it should be trying to achieve.

The signed side error is measured in the path's local right direction:

```text
pathRight = (sin(referenceYaw), cos(referenceYaw))
crossTrackError = dot(pose - referencePoint, pathRight)
```

Positive `crossTrackError` means the car is right of the path. Positive yaw is
left in OpenOtter's ground frame, so a positive cross-track error should bias
the desired yaw left:

```text
crossTrackCorrection = atan2(crossTrackHeadingGain * crossTrackError,
                             crossTrackSofteningDistance)
desiredYaw = wrapToPi(referenceYaw + crossTrackCorrection)
steeringYawError = wrapToPi(desiredYaw - pose.yaw)
pathHeadingError = wrapToPi(referenceYaw - pose.yaw)
```

The `atan2` correction has a useful property: small side errors behave almost
linearly, but large side errors saturate smoothly instead of demanding an
impossible instant turn.

The controller intentionally keeps both heading errors:

- `steeringYawError` includes the cross-track correction and drives steering.
- `pathHeadingError` is just the tangent direction and drives throttle.

The screenshot/video failure showed why this matters. The car could be pointed
mostly along the red path while sitting 20 cm off the centerline. In that case
the steering controller should ask for a strong recovery turn, but the throttle
controller should not interpret that recovery turn as "the path is behind me;
almost stop."

## 7. PID Feedback And Feedforward

The steering output uses a PID-shaped heading controller plus a curvature
feedforward term:

```text
pidCorrection =
    steeringGain * steeringYawError
  + headingIntegralGain * integral(steeringYawError)
  + headingDerivativeGain * derivative(steeringYawError)

steering = clamp(curvatureFeedforward - pidCorrection,
                 -maxSteeringFraction,
                 +maxSteeringFraction)
```

The sign is deliberate:

```text
positive steeringYawError -> path heading is left of car -> negative steering
negative steeringYawError -> path heading is right of car -> positive steering
positive path curvature -> path turns left          -> negative feedforward
```

Current constants:

```text
steeringFractionAt90Deg = 0.7
steeringGain = steeringFractionAt90Deg / (pi / 2)
maxSteeringFraction = 1.0
steeringThrottleFullLoadFraction = 0.45
crossTrackHeadingGain = 2.2
crossTrackSofteningDistance = 0.18 m
headingIntegralGain = 0.0
headingDerivativeGain = 0.02
headingIntegralLimit = 0.5 rad*s
curvatureFeedforwardGain = 0.10 m
curvatureSampleSpan = 3 waypoints each side
```

That means:

```text
90 degree heading error -> raw feedback about 0.7
larger errors plus feedforward -> steering capped to +/-1.0
```

This is a practical choice:

- small errors give small steering corrections,
- moderate errors give visible turning authority,
- very large errors can use the available normalized command range,
- the firmware clamps the servo PWM to `1000...2000 us` even if ARKit pose jumps,
- firmware steering slew limiting turns rapid full-range sweeps into a short
  ramp, which should reduce reset/brownout risk and audible end-stop chatter
  unless the mechanical linkage itself is binding.

The integral term is intentionally configured to zero for the first fieldable
version. Integral is useful for steady steering bias, but it can also wind up
against the steering cap and fight the next lobe. The state and clamp are in
place so a small integral gain can be enabled later from logs.

Curvature feedforward is the control engineer's suggestion in simple form. The
controller estimates path curvature from heading change over a short arc:

```text
curvature = wrapToPi(headingAfter - headingBefore) / arcLength
curvatureFeedforward = -curvatureFeedforwardGain * curvature
```

This tells the car to start turning before pose error grows. It is not a
vehicle model; it is a practical "we know the path bends here" steering bias.

The controller is not trying to model tire slip, steering linkage geometry, or
Ackermann dynamics. It is using pose feedback to correct the car's observed
motion. That is simpler than a full vehicle model and appropriate for the
current missing-front-wheel-angle hardware state.

## 8. Speed Control

The current implementation is not a full velocity PID loop yet. It still starts
from the operator's requested Telegram throttle, but it now uses measured speed
as low-speed anti-stall feedback. That is the practical middle ground for the
field symptom: if the car is already moving, tight turns may slow down; if the
car is stuck at 0.00-0.01 m/s while steering is loaded, the controller commands
enough throttle to break static friction.

The throttle law is:

```text
absError = abs(pathHeadingError)

if absError > maxPoweredHeadingError:
    throttle = 0
else:
    fade = 1 - absError / pi
    baseThrottle = maxThrottle * max(minimumThrottleFraction, fade)

    steeringLoad = abs(steering) / steeringThrottleFullLoadFraction
    lateralLoad = abs(crossTrackError) / lateralThrottleSlowdownDistance
    slowdown = steeringLoad * lateralLoad
    scale = 1 - (1 - steeringThrottleScaleAtLimit) * clamp(slowdown, 0, 1)

    throttle = baseThrottle * scale

    if throttle > 0
       and abs(pathHeadingError) < pi / 2
       and measuredSpeed < antiStallSpeedThresholdMps:

        breakawayThrottle = maxThrottle * antiStallThrottleFraction
        blend = 1 - measuredSpeed / antiStallSpeedThresholdMps
        throttle = throttle + (breakawayThrottle - throttle) * blend
```

Current constants:

```text
minimumThrottleFraction = 0.35
maxPoweredHeadingError  = 5 * pi / 6   # 150 degrees
steeringThrottleScaleAtLimit = 0.45
lateralThrottleSlowdownDistance = 0.20 m
antiStallThrottleFraction = 0.75
antiStallSpeedThresholdMps = 0.12
```

What this does:

- If the waypoint is mostly ahead, drive near `maxThrottle`.
- If the waypoint requires a turn, reduce throttle as the turn sharpens.
- If the waypoint is nearly behind the car, do not push forward into a bad
  U-turn.
- If the car is on the centerline, do not slow just because the planned path is
  curved.
- If the car is off the centerline and steering is near the cap, slow down so
  yaw can catch up before the car balloons outside the lobe.
- If the car is almost stopped, blend back toward useful breakaway throttle so
  static friction and loaded steering do not make it sit in place.

With the default Telegram speed:

```text
maxThrottle = 0.4
minimum moving throttle = 0.4 * 0.35 = 0.14
anti-stall breakaway throttle = 0.4 * 0.75 = 0.30
```

There is no hidden `/figure8` throttle multiplier. If the operator wants to
test faster, they should explicitly send `speed 0.5`, `speed 0.6`, or another
chosen value before `/figure8`. The safety supervisor still has final
authority over forward and reverse braking.

## 9. Safety Supervisor Interaction

The planner emits a desired command:

```text
ControlCommand(steering, throttle, source)
```

Then `PlannerOrchestrator` passes it through `SafetySupervisor`. The supervisor
may return:

```text
same command       if safe
brake/neutral      if obstacle or sensor condition requires braking
```

This separation matters:

- The planner owns path-following intent.
- The supervisor owns collision/sensor safety.
- Firmware owns PWM clamping, Park/Drive arbitration, and watchdog neutral
  behavior.

The figure-eight controller therefore does not need special obstacle logic.
It should make a good path-following command; safety layers decide whether the
command is allowed.

## 10. Pseudocode

### Command Dispatch

```text
onTelegramMessage(text):
    action = KeywordInterpreter.interpret(text)

    if action == figureEight:
        config = FigureEightConfig(
            segmentCount = 240,
            length = 3.2,
            width = 1.6,
            acceptanceRadius = 0.12
        )

        goal = FollowFigureEight(
            config = config,
            maxThrottle = interpreter.currentThrottle
        )

        PlannerOrchestrator.setGoal(goal)
```

### Path Generation

```text
generateFigureEight(config, anchorPose):
    dense = []

    for i in 0 ... denseCount:
        t = 2 * pi * i / denseCount
        theta = t + pi / 2
        denominator = 1 + sin(theta)^2

        rawX = -cos(theta) / denominator
        rawZ = -sin(theta) * cos(theta) / denominator

        dense.append(normalizeToConfiguredEnvelope(rawX, rawZ, config))

    cumulativeLength = cumulativeGroundDistance(dense)
    totalLength = cumulativeLength.last

    waypoints = []
    for i in 0 ..< config.segmentCount:
        targetDistance = totalLength * i / config.segmentCount
        localX, localZ = interpolateDensePointAtDistance(dense, cumulativeLength, targetDistance)

        world = localToWorld(localX, localZ, anchorPose)

        waypoints.append(Waypoint(
            x = world.x,
            z = world.z,
            acceptanceRadius = config.acceptanceRadius
        ))

    return waypoints
```

### Local-To-World Transform

```text
localToWorld(localX, localZ, anchorPose):
    forward = ( cos(anchorPose.yaw), -sin(anchorPose.yaw))
    right   = ( sin(anchorPose.yaw),  cos(anchorPose.yaw))

    worldX = anchorPose.x + localX * forward.x + localZ * right.x
    worldZ = anchorPose.z + localX * forward.z + localZ * right.z

    return (worldX, worldZ)
```

### Planner Tick

```text
plan(context):
    if pendingFigureEightConfig exists:
        waypoints = generateFigureEight(
            config = pendingFigureEightConfig,
            anchorPose = context.pose
        )
        currentWaypointIndex = 0
        pendingFigureEightConfig = none

    if waypoints is empty:
        return neutral

    advanceReachedWaypoints(context.pose)

    if currentWaypointIndex is past final waypoint:
        return neutral

    if isClosedLoop:
        reference = closedLoopPathReference(context.pose)
        steeringYawError = reference.steeringYawError
        throttleYawError = reference.throttleYawError
        feedforward = reference.steeringFeedforward
        lateralError = abs(reference.crossTrackError)
    else:
        target = waypoints[currentWaypointIndex]
        steeringYawError = headingErrorToWaypoint(target, context.pose)
        throttleYawError = steeringYawError
        feedforward = 0
        lateralError = none

    steering = steeringFromPIDAndFeedforward(
        steeringYawError,
        feedforward,
        context.timestamp
    )

    throttle = throttleForGuidance(
        throttleYawError,
        steering,
        lateralError,
        measuredSpeed(context)
    )

    return ControlCommand(
        steering = steering,
        throttle = throttle,
        source = "WaypointPlanner"
    )
```

### Closed-Loop Path Reference

```text
closedLoopPathReference(pose):
    P0 = waypoints[currentWaypointIndex]
    P1 = waypoints[(currentWaypointIndex + 1) mod waypoints.count]

    segment = P1 - P0
    alpha = clamp(dot(pose - P0, segment) / dot(segment, segment), 0, 1)
    referencePoint = P0 + alpha * segment

    referenceYaw = atan2(-(P1.z - P0.z), P1.x - P0.x)
    pathRight = (sin(referenceYaw), cos(referenceYaw))
    crossTrackError = dot(pose - referencePoint, pathRight)

    correction = atan2(crossTrackHeadingGain * crossTrackError,
                       crossTrackSofteningDistance)
    desiredYaw = wrapToPi(referenceYaw + correction)
    steeringYawError = wrapToPi(desiredYaw - pose.yaw)
    throttleYawError = wrapToPi(referenceYaw - pose.yaw)

    curvature = signedCurvature(currentWaypointIndex)
    feedforward = clamp(-curvatureFeedforwardGain * curvature,
                        -maxSteeringFraction,
                        +maxSteeringFraction)

    return steeringYawError, throttleYawError, crossTrackError, feedforward
```

### Steering PID And Feedforward

```text
steeringFromPIDAndFeedforward(steeringYawError, feedforward, timestamp):
    dt = clamp(timestamp - previousTimestamp, 0, 0.25)

    if dt > 0:
        integral = clamp(integral + steeringYawError * dt,
                         -headingIntegralLimit,
                         +headingIntegralLimit)
        derivative = wrapToPi(steeringYawError - previousYawError) / dt
    else:
        derivative = 0

    previousYawError = steeringYawError
    previousTimestamp = timestamp

    pid = steeringGain * steeringYawError
        + headingIntegralGain * integral
        + headingDerivativeGain * derivative

    return clamp(feedforward - pid,
                 -maxSteeringFraction,
                 +maxSteeringFraction)
```

### Waypoint Advancement

```text
advanceReachedWaypoints(pose):
    checkedCount = 0

    while checkedCount < waypoints.count:
        target = waypoints[currentWaypointIndex]

        if distance(pose, target) >= target.acceptanceRadius:
            break

        currentWaypointIndex += 1

        if isClosedLoop and currentWaypointIndex >= waypoints.count:
            currentWaypointIndex = 0

        checkedCount += 1

    if not isClosedLoop and all waypoints were reached:
        currentWaypointIndex = waypoints.count

    if isClosedLoop:
        advanceToClosestForwardWaypoint(pose)
```

### Closed-Loop Progress Recovery

```text
advanceToClosestForwardWaypoint(pose):
    bestIndex = currentWaypointIndex
    bestDistance = distance(pose, waypoints[currentWaypointIndex])

    for offset in 1 ... closedLoopProgressSearchCount:
        candidateIndex = (currentWaypointIndex + offset) mod waypoints.count
        candidateDistance = distance(pose, waypoints[candidateIndex])

        if candidateDistance < bestDistance:
            bestDistance = candidateDistance
            bestIndex = candidateIndex

    currentWaypointIndex = bestIndex
```

### Throttle Shaping

```text
throttleForGuidance(throttleYawError, steering, lateralError, measuredSpeed):
    absError = abs(throttleYawError)

    if absError > maxPoweredHeadingError:
        return 0

    fade = 1 - absError / pi
    base = maxThrottle * max(minimumThrottleFraction, fade)

    if lateralError is none:
        return antiStallAdjustedThrottle(base, throttleYawError, measuredSpeed)

    steeringLoad = clamp(abs(steering) / steeringThrottleFullLoadFraction, 0, 1)
    lateralLoad = clamp(lateralError / lateralThrottleSlowdownDistance, 0, 1)
    scale = 1 - (1 - steeringThrottleScaleAtLimit) * steeringLoad * lateralLoad

    return antiStallAdjustedThrottle(
        base * scale,
        throttleYawError,
        measuredSpeed
    )
```

### Low-Speed Anti-Stall

```text
antiStallAdjustedThrottle(throttle, throttleYawError, measuredSpeed):
    if throttle <= 0:
        return throttle

    if abs(throttleYawError) >= pi / 2:
        return throttle

    speed = measuredSpeed or 0
    if speed >= antiStallSpeedThresholdMps:
        return throttle

    breakaway = maxThrottle * antiStallThrottleFraction
    if breakaway <= throttle:
        return throttle

    blend = 1 - speed / antiStallSpeedThresholdMps
    return throttle + (breakaway - throttle) * blend
```

### Orchestrator Safety Pass

```text
tick(context):
    desired = activePlanner.plan(context)
    supervised = safetySupervisor.apply(desired, context)

    sendToFirmware(supervised)
    publishDebugWaypoints(activePlanner.activeWaypoints)

    return supervised
```

## 11. Why This Is Practical For The Current Car

This controller is intentionally simple, but it has the right control shape:

- It is closed-loop on pose, so it can correct real motion.
- It avoids needing a front wheel angle sensor.
- It has bounded steering and throttle outputs.
- It starts the path from the car's actual pose.
- It keeps moving through reasonable turns.
- It aligns heading to the path tangent instead of only pointing at a waypoint.
- It uses curvature feedforward so turning begins before pose error grows.
- It delegates obstacle safety to the existing supervisor.
- It has direct tests for steering sign, lateral-error correction, and a
  slow-yaw simulation that reproduces the outside-lobe failure.

The main limitation is that the speed command is not yet true speed feedback.
If the floor is slippery, carpet is high-friction, or battery voltage changes,
the same throttle value may produce different vehicle speeds. A future upgrade
should add speed PI control and pure pursuit curvature tracking.

## 12. Future Pure Pursuit Upgrade

The current figure-eight controller follows the tangent of the current path
segment and adds cross-track correction. Pure pursuit would improve this by
choosing a lookahead point along the path, then turning according to the
curvature needed to reach that lookahead point.

The usual pure pursuit steering concept is:

```text
curvature = 2 * localLookaheadY / lookaheadDistance^2
```

In OpenOtter's ground frame, `localLookaheadY` would correspond to the
left/right offset of the lookahead point in robot-local coordinates. The
controller could then map curvature to steering after calibration.

That upgrade should wait until the tangent-heading baseline has real basement data:

- Does ARKit yaw drift too much?
- Is 0.12 m acceptance radius too loose or too tight?
- Does default 0.4 figure-eight throttle plus steering-load slowdown move
  reliably?
- Does the car understeer or oversteer on carpet?
- Does the full normalized steering range, with firmware PWM slew limiting,
  complete both lobes without servo chatter or board resets?
- Does servo center need a trim offset?

Those answers should tune the next controller instead of guessing.
