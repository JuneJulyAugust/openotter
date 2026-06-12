# Figure-Eight Path Following Technical Note

**Status:** Companion technical document for the waypoint-controller baseline
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
2. Pick the next waypoint on that path.
3. Measure the heading error between the car and that waypoint.
4. Turn the steering servo proportionally to that heading error.
5. Command enough throttle to keep moving, while slowing down for sharp turns.
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
- Arc-length spacing makes fixed waypoint lookahead closer to fixed-distance
  lookahead, which is easier for the steering controller.

The current command defaults are:

```text
segmentCount      = 240
length            = 4.0 m
width             = 2.0 m
acceptanceRadius  = 0.12 m
maxThrottle       = current Telegram speed, with no hidden boost
default /figure8  = 0.4
```

`segmentCount` turns the smooth curve into a list of waypoints. With 240
segments, neighboring waypoints are close enough for smooth steering, but not
so dense that the controller spends all its time advancing tiny steps.

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

With the steering cap, smoother curve, larger path, and arc-length spacing,
that diagonal start is practical. It also preserves the requested visual shape.
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

The steering controller is proportional heading control.

First compute the vector from car to waypoint:

```text
dx = target.x - pose.x
dz = target.z - pose.z
```

The desired yaw angle is:

```text
desiredYaw = atan2(-dz, dx)
```

The negative sign is important. In this coordinate system, positive `z` means
"to the robot's right", while positive yaw turns toward negative `z`.

Then compute heading error:

```text
yawError = wrapToPi(desiredYaw - pose.yaw)
```

`wrapToPi` keeps the angle in this range:

```text
-pi <= yawError <= pi
```

This prevents a small left error from being represented as a huge right error.
For example, `-179 degrees` and `181 degrees` are almost the same heading, not
opposite commands.

The steering command is:

```text
rawSteering = -steeringGain * yawError
steering = clamp(rawSteering, -maxSteeringFraction, +maxSteeringFraction)
```

The minus sign is deliberate. The firmware and iOS PWM mapping define:

```text
steering -1.0 -> 1000 us -> full left
steering  0.0 -> 1500 us -> centered
steering +1.0 -> 2000 us -> full right
```

With the planner's coordinate convention, a waypoint to the robot's right
produces a negative `yawError`. Multiplying by `-steeringGain` makes that a
positive steering command, which maps to right steering PWM.

## 7. Steering Gain

The gain is configured as:

```text
steeringFractionAt90Deg = 0.7
steeringGain = steeringFractionAt90Deg / (pi / 2)
maxSteeringFraction = 0.45
```

That means:

```text
90 degree heading error -> raw steering command about 0.7
larger errors -> steering capped to +/-0.45
```

This is a practical choice:

- small errors give small steering corrections,
- moderate errors give visible turning authority,
- very large errors do not command the servo to its mechanical end stops,
- the servo command remains bounded even if ARKit pose jumps,
- the front wheel should stop making end-stop chatter unless the mechanical
  linkage itself is binding.

The controller is not trying to model tire slip, steering linkage geometry, or
Ackermann dynamics. It is using pose feedback to correct the car's observed
motion. That is simpler than a full vehicle model and appropriate for the
current missing-front-wheel-angle hardware state.

## 8. Speed Control

The current implementation controls speed in an open-loop way: it chooses a
throttle command from heading error, but it does not yet close the loop on
measured vehicle speed.

The throttle law is:

```text
absError = abs(yawError)

if absError > maxPoweredHeadingError:
    throttle = 0
else:
    fade = 1 - absError / pi
    throttle = maxThrottle * max(minimumThrottleFraction, fade)
```

Current constants:

```text
minimumThrottleFraction = 0.35
maxPoweredHeadingError  = 5 * pi / 6   # 150 degrees
```

What this does:

- If the waypoint is mostly ahead, drive near `maxThrottle`.
- If the waypoint requires a turn, reduce throttle as the turn sharpens.
- If the waypoint is nearly behind the car, do not push forward into a bad
  U-turn.
- For ordinary turns, keep a throttle floor so the car does not creep and then
  stall.

With the default Telegram speed:

```text
maxThrottle = 0.4
minimum moving throttle = 0.4 * 0.35 = 0.14
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
            length = 4.0,
            width = 2.0,
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
        targetIndex = (currentWaypointIndex + closedLoopLookaheadCount) mod waypoints.count
        target = waypoints[targetIndex]
    else:
        target = waypoints[currentWaypointIndex]

    dx = target.x - context.pose.x
    dz = target.z - context.pose.z

    desiredYaw = atan2(-dz, dx)
    yawError = wrapToPi(desiredYaw - context.pose.yaw)

    rawSteering = -steeringGain * yawError
    steering = clamp(rawSteering, -maxSteeringFraction, +maxSteeringFraction)
    throttle = throttleForHeadingError(yawError)

    return ControlCommand(
        steering = steering,
        throttle = throttle,
        source = "WaypointPlanner"
    )
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
throttleForHeadingError(yawError):
    absError = abs(yawError)

    if absError > maxPoweredHeadingError:
        return 0

    fade = 1 - absError / pi
    fraction = max(minimumThrottleFraction, fade)

    return maxThrottle * fraction
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
- It delegates obstacle safety to the existing supervisor.
- It has direct tests for the sign convention that caused the field failure.

The main limitation is that the speed command is not yet true speed feedback.
If the floor is slippery, carpet is high-friction, or battery voltage changes,
the same throttle value may produce different vehicle speeds. A future upgrade
should add speed PI control and pure pursuit curvature tracking.

## 12. Future Pure Pursuit Upgrade

The waypoint proportional controller chooses one waypoint and points at it.
Pure pursuit improves this by choosing a lookahead point along the path, then
turning according to the curvature needed to reach that lookahead point.

The usual pure pursuit steering concept is:

```text
curvature = 2 * localLookaheadY / lookaheadDistance^2
```

In OpenOtter's ground frame, `localLookaheadY` would correspond to the
left/right offset of the lookahead point in robot-local coordinates. The
controller could then map curvature to steering after calibration.

That upgrade should wait until the waypoint baseline has real basement data:

- Does ARKit yaw drift too much?
- Is 0.12 m acceptance radius too loose or too tight?
- Does default 0.4 figure-eight throttle plus a 0.35 floor move reliably?
- Does the car understeer or oversteer on carpet?
- Is the 0.45 steering cap low enough to avoid end-stop chatter but high
  enough to complete both lobes?
- Does servo center need a trim offset?

Those answers should tune the next controller instead of guessing.
