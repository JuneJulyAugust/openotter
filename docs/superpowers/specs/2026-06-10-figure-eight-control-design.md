# Figure-Eight Basement Control - Revised Design

**Status:** Implemented waypoint-controller baseline for review
**Date:** 2026-06-10
**Branch/worktree:** `control-figure-eight-design` at `.worktrees/control-figure-eight-design`

## 1. Goal

Make OpenOtter follow a repeatable figure-eight path indoors from a Telegram
or iOS agent command. This milestone intentionally starts with a waypoint
proportional controller, not pure pursuit or MPC.

The target behavior is:

- `/figure8` starts a closed figure-eight mission from the car's current pose.
- The first target segment points mostly forward, not hard-left or hard-right.
- Steering sign matches the firmware PWM convention.
- The car keeps looping until the operator sends `/stop`.
- The map overlay shows the active planned waypoints.
- Firmware remains the deterministic actuator and safety layer.

## 2. Field Failure Review

Observed behavior:

- front wheels turned left,
- the car moved slowly for a while,
- then it stopped.

Root causes in the first implementation:

1. **Steering sign was inverted.** Firmware and `PwmMapping` define negative
   steering as left and positive steering as right, but `WaypointPlanner`
   produced negative steering for a target on robot-right.
2. **Figure-eight waypoints were not anchored to the current pose.** The
   command built a small path around ARKit world `(0, 0)` instead of the car's
   pose when the mission began.
3. **The path was too small and finite.** A `0.8 m x 0.5 m` one-lap waypoint
   list can be consumed quickly, after which the planner correctly emits
   neutral. From the operator seat, that looks like the mission died.
4. **The map overlay used stale state.** `SelfDrivingViewModel.waypoints` was
   never populated, so the UI was not showing the actual active path.

The fix is not to jump to a more advanced controller yet. The fix is to make
the simple controller coherent and testable.

## 3. Coordinate And PWM Invariants

OpenOtter planner code uses the ARKit ground plane as:

```text
+x = robot forward
+z = robot right
yaw 0 = facing +x
```

Yaw rotates the robot's local axes into world coordinates:

```text
forward_world = ( cos(yaw), -sin(yaw))
right_world   = ( sin(yaw),  cos(yaw))
```

Firmware PWM convention is:

```text
steering -1.0 -> 1000 us -> full left
steering  0.0 -> 1500 us -> centered
steering +1.0 -> 2000 us -> full right
```

Therefore a target at robot-right must produce **positive** steering. This is
locked by `WaypointPlannerTests`.

## 4. Controller Strategy

The baseline controller is a waypoint proportional heading controller:

1. Keep an ordered list of waypoints.
2. If the current waypoint is inside its acceptance radius, advance to the
   next waypoint.
3. Compute the desired heading from current pose to target waypoint:

```text
dx = target.x - pose.x
dz = target.z - pose.z
desired_yaw = atan2(-dz, dx)
heading_error = wrap_to_pi(desired_yaw - pose.yaw)
```

4. Convert heading error to steering:

```text
steering = clamp(-K * heading_error, -1, +1)
```

The minus sign matters because, in this coordinate convention, a target to the
right has negative heading error, but the actuator expects positive steering
for right.

5. Throttle fades down during turns, but does not collapse to near-zero for
ordinary curves:

```text
fade = 1 - abs(heading_error) / pi
throttle = maxThrottle * max(minimumThrottleFraction, fade)
```

If the target is nearly behind the car, throttle is held at zero instead of
forcing a powered U-turn.

## 5. Figure-Eight Path

The path is a Gerono-style figure eight:

```text
curve_x(t) = (length / 2) * sin(t)
curve_z(t) = (width  / 2) * sin(2t)
```

The generator then rotates the local curve so the initial tangent points
forward in the robot frame. Finally, it transforms local `(x, z)` into ARKit
world coordinates using the mission anchor pose.

That means:

- waypoint 0 is exactly the car pose at mission start,
- waypoint 1 is mostly forward,
- the path rotates with car yaw,
- the figure eight is closed enough to loop smoothly without duplicating the
  first waypoint.

Current default command parameters:

```text
segmentCount      = 120
length            = 1.5 m
width             = 1.0 m
acceptanceRadius  = 0.22 m
default throttle  = 0.6
```

`length` and `width` are generator scale parameters. Because the path is
rotated to make the first tangent forward, the final world-frame envelope is
slightly larger than the raw axis-aligned half-spans. The tests verify the path
stays inside the rotated envelope and forms a continuous loop.

## 6. Runtime Flow

```text
Telegram /figure8
  -> KeywordInterpreter.figureEight
  -> ActionDispatcher
  -> PlannerGoal.followFigureEight(config, maxThrottle)
  -> PlannerOrchestrator switches to WaypointPlanner
  -> first control tick anchors waypoints from PlannerContext.pose
  -> WaypointPlanner emits steering/throttle
  -> SafetySupervisor may brake
  -> STM32 receives PWM command
```

Anchoring inside `WaypointPlanner.plan(context:)` is deliberate. Telegram does
not have pose. The planner does.

## 7. Component Ownership

### iOS

- `FigureEightTrajectory` generates waypoint paths.
- `RobotGeometry` owns yaw/local/world transformations.
- `WaypointPlanner` owns waypoint advancement, steering, throttle shaping, and
  figure-eight looping.
- `PlannerOrchestrator` routes figure-eight goals to `WaypointPlanner` and
  publishes active waypoints for UI overlay.
- `ActionDispatcher` maps `/figure8` to a figure-eight planner goal.
- `PoseMapView` receives active waypoints through `SelfDrivingView`.

### Firmware

Firmware does not own figure-eight tracking. It continues to own:

- PWM clamping,
- watchdog neutral behavior,
- Park/Drive arbitration,
- forward and reverse safety supervision.

No firmware changes are required for this waypoint-controller baseline.

## 8. Tests

The implementation is covered by:

- `RobotGeometryTests` for forward/right axis invariants.
- `FigureEightTrajectoryTests` for defaults, bounds, anchoring, yaw rotation,
  and loop continuity.
- `WaypointPlannerTests` for steering sign, anchored figure-eight startup,
  finite waypoint completion, and closed figure-eight looping.
- `PlannerOrchestratorTests` for routing and active waypoint publication.
- `ActionDispatcherTests` and `AgentRuntimeTests` for `/figure8` command flow.
- Existing safety tests still cover forward/reverse braking behavior.

Verification command:

```bash
SIMULATOR_UDID=40B418BA-9B70-4B34-9D13-81E3A3F281A9 bash openotter-ios/build.sh test
```

## 9. Future Controller Upgrade

Pure pursuit is still the right next upgrade after waypoint proportional control
has field data. It should add:

- closest-path projection,
- lookahead target selection by arc length,
- curvature-based steering,
- speed feedback PI control,
- slow steering trim for servo/linkage bias.

That is intentionally a later milestone. This PR should make the simple
controller behave honestly first.
