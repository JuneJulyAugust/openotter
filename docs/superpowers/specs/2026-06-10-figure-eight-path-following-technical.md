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

The path generator uses a Gerono figure eight:

```text
curve_x(t) = (length / 2) * sin(t)
curve_z(t) = (width  / 2) * sin(2t)
```

where `t` moves from `0` to almost `2 * pi`.

Intuition:

- `sin(t)` moves smoothly forward and backward once per loop.
- `sin(2t)` moves left and right twice per loop.
- Combining them forms a sideways "8" shape.

The current command defaults are:

```text
segmentCount      = 120
length            = 1.5 m
width             = 1.0 m
acceptanceRadius  = 0.22 m
maxThrottle       = current Telegram speed, default 0.6
```

`segmentCount` turns the smooth curve into a list of waypoints. With 120
segments, neighboring waypoints are close enough for smooth steering, but not
so dense that the controller spends all its time advancing tiny steps.

## 4. Starting The Path Forward

A raw Gerono curve starts at `(0, 0)`, but its first tangent points diagonally.
If the first target is diagonal, the car may begin by steering hard instead of
driving forward into the maneuver.

To avoid that, the path is rotated in the car-local frame so its initial
tangent points forward.

At `t = 0`:

```text
d/dt curve_x(t) = (length / 2) * cos(t)
d/dt curve_z(t) = width * cos(2t)
```

So the initial tangent is:

```text
tangent = (length / 2, width)
```

The tangent angle is:

```text
initialTangentAngle = atan2(width, length / 2)
```

The implementation computes the same value as:

```text
initialTangentAngle = atan2(2 * zScale, xScale)
```

where:

```text
xScale = length / 2
zScale = width / 2
```

Then it rotates every local curve point by `-initialTangentAngle`. After that
rotation:

- waypoint 0 is exactly the car's start pose,
- waypoint 1 is mostly forward,
- the path still forms a figure eight,
- the whole path rotates with the car's yaw.

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

For normal finite waypoint missions:

```text
after final waypoint -> output neutral
```

For figure-eight missions:

```text
after final waypoint -> wrap back to waypoint 0
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
steering = clamp(-steeringGain * yawError, -1, +1)
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
steeringFractionAt90Deg = 0.6
steeringGain = steeringFractionAt90Deg / (pi / 2)
```

That means:

```text
90 degree heading error -> steering command about 0.6
```

This is a practical choice:

- small errors give small steering corrections,
- moderate errors give useful turning authority,
- very large errors saturate at `-1` or `+1`,
- the servo command remains bounded even if ARKit pose jumps.

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
maxThrottle = 0.6
minimum moving throttle = 0.6 * 0.35 = 0.21
```

That is intentionally faster than the earlier `0.4` default with no practical
floor. The safety supervisor still has final authority over forward and
reverse braking.

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
            segmentCount = 120,
            length = 1.5,
            width = 1.0,
            acceptanceRadius = 0.22
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
    xScale = config.length / 2
    zScale = config.width / 2
    dt = 2 * pi / config.segmentCount

    initialTangentAngle = atan2(2 * zScale, xScale)

    waypoints = []

    for i in 0 ..< config.segmentCount:
        t = i * dt

        curveX = xScale * sin(t)
        curveZ = zScale * sin(2 * t)

        localX =  curveX * cos(-initialTangentAngle)
                - curveZ * sin(-initialTangentAngle)

        localZ =  curveX * sin(-initialTangentAngle)
                + curveZ * cos(-initialTangentAngle)

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

    target = waypoints[currentWaypointIndex]

    dx = target.x - context.pose.x
    dz = target.z - context.pose.z

    desiredYaw = atan2(-dz, dx)
    yawError = wrapToPi(desiredYaw - context.pose.yaw)

    steering = clamp(-steeringGain * yawError, -1, +1)
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
- Is 0.22 m acceptance radius too loose or too tight?
- Does 0.6 throttle plus a 0.35 floor move reliably?
- Does the car understeer or oversteer on carpet?
- Does servo center need a trim offset?

Those answers should tune the next controller instead of guessing.
