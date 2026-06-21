# Figure-Eight Path Following Technical Note

**Status:** Companion technical document for `TangentTrack` PID/feedforward control
**Date:** 2026-06-10
**Feature:** Telegram/iOS `/figure8` basement trajectory following

## 1. What The Controller Is Trying To Do

The car does not know its front wheel angle. That removes a common feedback
signal, but it does not prevent feedback control. The iOS app still has an
estimated car pose from ARKit:

| Field | Meaning |
| --- | --- |
| `pose.x` | ground-plane $x$ position, metres |
| `pose.z` | ground-plane $z$ position, metres |
| `pose.yaw` | heading angle $\psi$, radians |

The current controller is named `TangentTrack`. The Swift implementation type is
still `TangentTrackPlanner`, because it also handles ordinary finite waypoint
missions, but telemetry, tests, and design discussion use `TangentTrack` for
this path-tangent PID/feedforward behavior.

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

OpenOtter planner code uses a 2D ground-plane model. Height, roll, and pitch
are ignored by this controller.

The most important rule is: equations use `(x, z)` component order, while the
iOS map draws `z` horizontally and `x` vertically. In other words, math
`x` is the app-map up/down direction, not the app-map left/right direction.

| Quantity | Meaning |
| --- | --- |
| $x$ | forward/up ground-plane coordinate |
| $z$ | right/horizontal ground-plane coordinate |
| $p=[x,z]^\top$ | a point or car position in ground-plane coordinates |
| $\psi$ | the math symbol for `pose.yaw`, in radians |
| $\psi=0$ | car nose points along $+x$ |
| $\psi>0$ | car nose rotates left toward $-z$ |
| $\psi<0$ | car nose rotates right toward $+z$ |

`PoseMapView` renders those axes as:

| Screen direction | World/local direction |
| --- | --- |
| up | $+x$ forward |
| right | $+z$ right |

So a "horizontal" figure eight in the app map is long in local `+Z/-Z` and
shorter in local `+X/-X`.

![Coordinate convention diagram](figures/figure-eight-coordinate-conventions.png)

The symbols $\mathbf{f}_{\mathrm{world}}$ and
$\mathbf{r}_{\mathrm{world}}$ are unit vectors. They tell us where the car's
local axes point after yaw rotation:

| Symbol | Plain-English meaning | Components |
| --- | --- | --- |
| $\mathbf{f}_{\mathrm{world}}$ | car's local forward/nose direction, written in world `(x,z)` coordinates | $(f_x,f_z)$ |
| $\mathbf{r}_{\mathrm{world}}$ | car's local right-side direction, written in world `(x,z)` coordinates | $(r_x,r_z)$ |

For a given yaw angle, these two unit vectors are:

$$
\mathbf{f}_{\mathrm{world}} =
\begin{bmatrix}
\cos\psi \\
-\sin\psi
\end{bmatrix},
\qquad
\mathbf{r}_{\mathrm{world}} =
\begin{bmatrix}
\sin\psi \\
\cos\psi
\end{bmatrix}
$$

These formulas are just a rotation. They are easier to trust by checking two
special cases.

At $\psi=0$, `cos(0) = 1` and `sin(0) = 0`, so:

$$
\mathbf{f}_{\mathrm{world}} =
\begin{bmatrix}
1 \\
0
\end{bmatrix},
\qquad
\mathbf{r}_{\mathrm{world}} =
\begin{bmatrix}
0 \\
1
\end{bmatrix}
$$

That matches the planner convention.

At $\psi=\pi/2$, the car nose points left on the app map, so:

$$
\mathbf{f}_{\mathrm{world}} =
\begin{bmatrix}
0 \\
-1
\end{bmatrix},
\qquad
\mathbf{r}_{\mathrm{world}} =
\begin{bmatrix}
1 \\
0
\end{bmatrix}
$$

That means the car's forward direction is world $-z$, and the car's right side
is world $+x$.

To convert a point from car-local coordinates into ARKit-derived world
coordinates:

$$
x_{\mathrm{world}} =
x_{\mathrm{anchor}} +
x_{\mathrm{local}} f_x +
z_{\mathrm{local}} r_x
$$

$$
z_{\mathrm{world}} =
z_{\mathrm{anchor}} +
x_{\mathrm{local}} f_z +
z_{\mathrm{local}} r_z
$$

This is why `/figure8` is now anchored inside `TangentTrackPlanner.plan(context:)`.
The Telegram command does not know the current pose, but the planner does.

## 3. Figure-Eight Path Shape

The path generator uses a smoother Bernoulli-style figure eight:

$$
\theta = t + \frac{\pi}{2}
$$

$$
x_{\mathrm{raw}} =
\frac{-\cos\theta}{1+\sin^2\theta},
\qquad
z_{\mathrm{raw}} =
\frac{-\sin\theta\cos\theta}{1+\sin^2\theta}
$$

where `t` moves from `0` to `2 * pi`. The `pi / 2` shift makes `t = 0`
the center crossing, and the negative signs make the first segment move
forward/right. The raw curve is normalized to the configured app-map length
and width, then resampled by arc length so neighboring controller waypoints are
nearly evenly spaced.

Intuition:

- The curve still forms the requested sideways "8".
- The lobes are rounder than the earlier Gerono curve.
- Arc-length spacing gives the tangent-heading controller a smooth reference
  direction from segment to segment.

The current command defaults are:

| Parameter | Default |
| --- | --- |
| `segmentCount` | $240$ |
| `length` | $3.2\ \mathrm{m}$ |
| `width` | $1.6\ \mathrm{m}$ |
| `acceptanceRadius` | $0.12\ \mathrm{m}$ |
| `maxThrottle` | current Telegram speed, with no hidden boost |
| default `/figure8` throttle | $0.4$ |

`segmentCount` turns the smooth curve into a list of waypoints. With 240
segments, neighboring waypoints are close enough for smooth steering, but not
so dense that the controller spends all its time advancing tiny steps. The
`3.2 m x 1.6 m` envelope is 80% of the previous `4.0 m x 2.0 m` default, which
preserves the reference shape while adding wall margin for real tracking lag.
Here, `length = 3.2 m` means left/right on the app map (`+Z/-Z`), and
`width = 1.6 m` means forward/back on the app map (`+X/-X`).

## 4. Horizontal Infinity Shape And Start

The requested shape is a horizontal infinity track: two side-by-side lobes
that cross in the center, like the reference image. The current generator keeps
that literal shape in the app map:

| App-map axis | Figure-eight role |
| --- | --- |
| $+z/-z$ | long left/right axis |
| $+x/-x$ | shorter forward/back width |

Waypoint `0` is the center crossing at the car's pose when `/figure8` starts.
The first few waypoints move forward and right into the first lobe. Halfway
through the waypoint list, the path returns to the center crossing and enters
the other lobe.

The initial tangent is diagonal: it points forward and right.

With full normalized steering authority, firmware-side PWM clamping/slew,
smoother curve, smaller path, and arc-length spacing, that diagonal start is
practical. It also preserves the requested visual shape.
The earlier implementation
rotated the curve to make this tangent point forward; that made the math tidy
but made the plotted path less like the requested horizontal track.

The whole local path is still transformed through the car's yaw, so the
horizontal infinity is horizontal in the app map relative to the car's
starting pose, not hard-coded to an arbitrary ARKit world axis.

### Practical Initial Pose

For the best basement test, place the car at the desired center crossing of the
figure eight. Point the nose along the desired forward/back width axis of the
track before sending `/figure8`; the long 3.2 m lobe-to-lobe axis will run
left/right across the car on the app map.

That means:

- the car's current ARKit pose becomes waypoint `0`,
- the orange start dot on the map is the car's starting pose,
- the small arrow leaving the orange dot shows the first desired movement,
- the first lobe is forward and to the car's right,
- the second lobe is behind the original start point after the path crosses
  the center again. By then the car has turned around, so it still drives
  forward along the path instead of reversing.

With the current `3.2 m x 1.6 m` default, reserve roughly this clear area around
the starting pose:

| Direction from start crossing | Clearance |
| --- | --- |
| forward | $0.8\ \mathrm{m}$ |
| behind | $0.8\ \mathrm{m}$ |
| left | $1.6\ \mathrm{m}$ |
| right | $1.6\ \mathrm{m}$ |

If you want the long left/right axis of the 8 to face a different physical
direction in the basement, rotate the car so its `+Z/-Z` side axis lines up
with that direction, then send `/figure8`. The controller does not use a fixed
room direction; it anchors the whole path to the car's pose and yaw at mission
start.

The ideal starting alignment is not at the outside of a lobe. It is at the
center crossing, with the green ego heading approximately aligned with the
orange start arrow. Starting near the center but with the car pointed 90
degrees away from that arrow makes the first seconds harder, because the
controller must spend steering authority correcting heading instead of smoothly
entering the first lobe.

## 5. Waypoint Advancement

The controller stores:

| State | Purpose |
| --- | --- |
| `waypoints` | sampled reference path |
| `currentWaypointIndex` | active path progress index |
| `isClosedLoop` | whether the planner wraps at the end |

On each tick, it checks whether the car is close enough to the current
waypoint:

$$
d =
\sqrt{(x_{\mathrm{target}}-x)^2+(z_{\mathrm{target}}-z)^2}
$$

$$
\mathrm{reached} =
d < r_{\mathrm{accept}}
$$

If reached, the controller advances to the next waypoint.

For a closed-loop figure eight, the controller also searches a short window of
future waypoints and advances to the closest one. This matters in real driving:
if the car misses a waypoint by more than the acceptance radius, a naive
controller keeps turning back toward that stale waypoint. On a tight lobe that
looks exactly like the map screenshot: the car circles one loop and never
commits to the crossing.

For normal finite waypoint missions, reaching the final waypoint makes the
planner output neutral. For figure-eight missions, reaching the final waypoint
wraps progress back to waypoint $0$; if a future waypoint in the progress
window is closer than the current one, the planner skips ahead to it.

That makes `/figure8` continue until the operator sends Stop/Park.

## 6. Steering Control

Finite waypoint missions still use the original bearing-to-waypoint rule. The
closed-loop figure-eight mission uses a path-reference controller instead,
because chasing a single future point can orbit outside a lobe when the car's
yaw response is slow.

For the active path segment:

| Symbol | Definition |
| --- | --- |
| $P_0$ | active segment start waypoint, in `(x,z)` coordinates |
| $P_1$ | active segment end waypoint, in `(x,z)` coordinates |
| $p$ | current car position, in `(x,z)` coordinates |
| $\mathbf{s}$ | segment vector $P_1-P_0$ |
| $\alpha$ | progress along the segment, clamped between $0$ and $1$ |
| $P_{\mathrm{ref}}$ | closest point on the active segment |
| $\psi_{\mathrm{ref}}$ | yaw angle of the path tangent |
| $\mathbf{r}_{\mathrm{path}}$ | unit vector pointing to the path's right side |
| $e_{\mathrm{ct}}$ | cross-track error; positive means car is right of the path |

![Path-reference geometry diagram](figures/path-reference-geometry.png)

$$
P_0 = \mathrm{waypoint}[i],
\qquad
P_1 = \mathrm{waypoint}[i+1],
\qquad
\mathbf{s}=P_1-P_0
$$

The controller projects the car position onto this segment:

$$
\alpha =
\mathrm{clip}
\left(
\frac{(p-P_0)\cdot\mathbf{s}}{\mathbf{s}\cdot\mathbf{s}},
0,
1
\right)
$$

$$
P_{\mathrm{ref}} = P_0 + \alpha\mathbf{s}
$$

Then it derives the reference heading from the segment tangent:

$$
\psi_{\mathrm{ref}} =
\mathrm{atan2}\left(-(P_{1,z}-P_{0,z}),\,P_{1,x}-P_{0,x}\right)
$$

This is the key upgrade. `referenceYaw` is the direction of the path, not the
bearing from the car to a future dot. If the path is turning through the lobe,
the controller knows the heading it should be trying to achieve.

The negative sign on the $z$ difference comes directly from the yaw convention.
If the segment points straight forward, then $\Delta z=0$ and
$\psi_{\mathrm{ref}}=0$. If the segment points straight right on the app map,
then $\Delta x=0$, $\Delta z>0$, and
$\psi_{\mathrm{ref}}=-\pi/2$, which means right-facing yaw.

The signed side error is measured in the path's local right direction:

$$
\mathbf{r}_{\mathrm{path}} =
\begin{bmatrix}
\sin\psi_{\mathrm{ref}} \\
\cos\psi_{\mathrm{ref}}
\end{bmatrix}
$$

$$
e_{\mathrm{ct}} =
(p-P_{\mathrm{ref}})\cdot\mathbf{r}_{\mathrm{path}}
$$

Positive `crossTrackError` means the car is right of the path. Positive yaw is
left in OpenOtter's ground frame, so a positive cross-track error should bias
the desired yaw left:

$$
\Delta\psi_{\mathrm{ct}} =
\mathrm{atan2}
\left(
k_{\mathrm{ct}}e_{\mathrm{ct}},
d_{\mathrm{soft}}
\right)
$$

$$
\psi_{\mathrm{desired}} =
\mathrm{wrapToPi}(\psi_{\mathrm{ref}}+\Delta\psi_{\mathrm{ct}})
$$

$$
e_{\psi,\mathrm{steer}} =
\mathrm{wrapToPi}(\psi_{\mathrm{desired}}-\psi)
$$

$$
e_{\psi,\mathrm{path}} =
\mathrm{wrapToPi}(\psi_{\mathrm{ref}}-\psi)
$$

The `atan2` correction has a useful property: small side errors behave almost
linearly, but large side errors saturate smoothly instead of demanding an
impossible instant turn.

The controller intentionally keeps both heading errors:

- `steeringYawError` includes the cross-track correction and drives steering.
- `pathHeadingError` is just the tangent direction and drives throttle.

This separation matters when the car is pointed mostly along the red path but
is still off the centerline. In that case the steering controller should ask
for a strong recovery turn, but the throttle controller should not interpret
that recovery turn as "the path is behind me; almost stop."

## 7. PID Feedback And Feedforward

The steering output uses a PID-shaped heading controller plus a curvature
feedforward term:

$$
u_{\mathrm{pid}} =
K_p e_{\psi,\mathrm{steer}} +
K_i \int e_{\psi,\mathrm{steer}}\,dt +
K_d \frac{d e_{\psi,\mathrm{steer}}}{dt}
$$

$$
s =
\mathrm{clip}
\left(
s_{\mathrm{ff}} - u_{\mathrm{pid}},
-s_{\max},
s_{\max}
\right)
$$

The sign is deliberate:

| Condition | Command effect |
| --- | --- |
| $e_{\psi,\mathrm{steer}} > 0$ | path heading is left of car, command negative steering |
| $e_{\psi,\mathrm{steer}} < 0$ | path heading is right of car, command positive steering |
| $\kappa > 0$ | path turns left, command negative feedforward |

Current constants:

| Parameter | Value |
| --- | --- |
| steering fraction at $90^\circ$ | $0.9$ |
| $K_p$ | $0.9/(\pi/2)$ |
| $s_{\max}$ | $1.0$ |
| steering throttle full-load fraction | $0.45$ |
| $k_{\mathrm{ct}}$ | $2.2$ |
| $d_{\mathrm{soft}}$ | $0.18\ \mathrm{m}$ |
| $K_i$ | $0.0$ |
| $K_d$ | $0.02$ |
| heading integral limit | $0.5\ \mathrm{rad\,s}$ |
| $k_{\kappa}$ | $0.10\ \mathrm{m}$ |
| curvature sample span | $3$ waypoints each side |

That means:

$$
|e_{\psi,\mathrm{steer}}| = \frac{\pi}{2}
\quad\Rightarrow\quad
|K_p e_{\psi,\mathrm{steer}}| \approx 0.9
$$

Larger errors plus feedforward are capped to $s\in[-1,1]$.

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

$$
\kappa \approx
\frac{\mathrm{wrapToPi}(\psi_{\mathrm{after}}-\psi_{\mathrm{before}})}
s_{\mathrm{arc}}}
$$

$$
s_{\mathrm{ff}} = -k_{\kappa}\kappa
$$

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

Let $a = |e_{\psi,\mathrm{path}}|$. If
$a > e_{\psi,\mathrm{powered,max}}$, the throttle command is zero:

$$
\tau = 0
$$

Otherwise, the base throttle fades with path-heading error:

$$
f_{\psi} = 1-\frac{a}{\pi}
$$

$$
\tau_{\mathrm{base}} =
\tau_{\max}\max(f_{\min}, f_{\psi})
$$

Then steering and lateral load scale the command:

$$
\ell_s =
\mathrm{clip}
\left(
\frac{|s|}{s_{\mathrm{full}}},
0,
1
\right),
\qquad
\ell_{\mathrm{lat}} =
\mathrm{clip}
\left(
\frac{|e_{\mathrm{ct}}|}{d_{\mathrm{lat}}},
0,
1
\right)
$$

$$
\tau_{\mathrm{scale}} =
1-(1-\tau_{\mathrm{scale,min}})\ell_s\ell_{\mathrm{lat}}
$$

$$
\tau_{\mathrm{shaped}} =
\tau_{\mathrm{base}}\tau_{\mathrm{scale}}
$$

For low-speed anti-stall, if $\tau_{\mathrm{shaped}}>0$,
$a<\pi/2$, and $v_{\mathrm{measured}} < v_{\mathrm{stall}}$, the command
blends toward breakaway throttle:

$$
\tau_{\mathrm{breakaway}} =
\tau_{\max} f_{\mathrm{breakaway}}
$$

$$
\beta = 1-\frac{v_{\mathrm{measured}}}{v_{\mathrm{stall}}}
$$

$$
\tau =
\tau_{\mathrm{shaped}} +
\left(\tau_{\mathrm{breakaway}}-\tau_{\mathrm{shaped}}\right)\beta
$$

Current constants:

| Parameter | Value |
| --- | --- |
| $f_{\min}$ | $0.35$ |
| $e_{\psi,\mathrm{powered,max}}$ | $5\pi/6$ or $150^\circ$ |
| $\tau_{\mathrm{scale,min}}$ | $0.70$ |
| $d_{\mathrm{lat}}$ | $0.20\ \mathrm{m}$ |
| $f_{\mathrm{breakaway}}$ | $0.75$ |
| $v_{\mathrm{stall}}$ | $0.12\ \mathrm{m/s}$ |

What this does:

- If the waypoint is mostly ahead, drive near `maxThrottle`.
- If the waypoint requires a turn, reduce throttle as the turn sharpens.
- If the waypoint is nearly behind the car, do not push forward into a bad
  U-turn.
- If the car is on the centerline, do not slow just because the planned path is
  curved.
- If the car is off the centerline and steering is near the cap, slow down
  enough for yaw to catch up, but keep at least 70% of the base throttle so
  the figure-eight mission does not crawl once the car is already moving.
- If the car is almost stopped, blend back toward useful breakaway throttle so
  static friction and loaded steering do not make it sit in place.

With the default Telegram speed:

$$
\tau_{\max} = 0.4
$$

$$
\tau_{\mathrm{minimum}} = 0.4 \cdot 0.35 = 0.14
$$

$$
\tau_{\mathrm{breakaway}} = 0.4 \cdot 0.75 = 0.30
$$

There is no hidden `/figure8` throttle multiplier. If the operator wants to
test faster, they should explicitly send `speed 0.5`, `speed 0.6`, or another
chosen value before `/figure8`. The safety supervisor still has final
authority over forward and reverse braking.

## 9. Safety Supervisor Interaction

The planner emits a desired command:

$$
\mathrm{ControlCommand}(s,\tau,\mathrm{source})
$$

Then `PlannerOrchestrator` passes it through `SafetySupervisor`. The supervisor
may return:

| Safety result | Meaning |
| --- | --- |
| same command | path-following command is allowed |
| brake or neutral | obstacle or sensor condition requires braking |

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
        source = "TangentTrack"
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
  slow-yaw simulation for outside-lobe overshoot.

The main limitations are:

- speed command is still throttle-shaped feedback, not direct speed control,
- steering output commands servo effort without measuring actual wheel angle,
- the gains are tuned for the current basement path and may need logs for other
  surfaces.

`LQRTrack` is now implemented as an explicit experimental controller behind
`/figure8_lqr`. It controls steering and speed from the same path reference
using a small state-space model and a quadratic cost. `TangentTrack` remains
the default `/figure8` baseline for comparison. The LQR controller design is
in `docs/superpowers/specs/2026-06-15-lqr-track-design.md`, with math and
pseudocode in `docs/superpowers/specs/2026-06-15-lqr-track-technical.md`.

## 12. `LQRTrack` Comparison

The current figure-eight controller follows the tangent of the current path
segment and adds cross-track correction. `LQRTrack` should improve this by
controlling a vector of errors together:

$$
\mathbf{x}_{\mathrm{LQR}} =
\begin{bmatrix}
e &
\dot{e} &
\theta_e &
\dot{\theta}_e &
v_e
\end{bmatrix}^{\top}
$$

where $e$ is lateral error, $\dot{e}$ is lateral error rate, $\theta_e$ is
heading error, $\dot{\theta}_e$ is heading error rate, and $v_e$ is speed
error.

![LQR error-state diagram](figures/lqr-error-state.png)

Instead of hand-tuning separate steering and throttle rules, LQR chooses the
steering and acceleration corrections that minimize a weighted sum of tracking
error and actuator effort. The detailed LQR design is documented separately so
the two controllers can be compared clearly.

The local Python prototype can compare both controllers quickly:

```bash
cd tools/trajectory-sim
PYTHONPATH=src python3 -m unittest discover tests
PYTHONPATH=src python3 -m openotter_sim.cli --controller both --output figure8-sim.png
```

The documentation diagrams are generated separately as high-resolution PNGs:

```bash
MPLCONFIGDIR=/private/tmp/openotter-mplconfig \
  /private/tmp/openotter-doc-plots-venv/bin/python tools/doc-plots/generate_control_diagrams.py
```

See `tools/doc-plots/README.md` for the full venv setup.

The next tuning questions should come from field data:

- Does ARKit yaw drift too much?
- Is 0.12 m acceptance radius too loose or too tight?
- Does default 0.4 figure-eight throttle plus steering-load slowdown move
  reliably?
- Does the car understeer or oversteer on carpet?
- Does the full normalized steering range, with firmware PWM slew limiting,
  complete both lobes without servo chatter or board resets?
- Does servo center need a trim offset?
- Does `LQRTrack` reduce outside-lobe ballooning compared with `TangentTrack`
  at the same max throttle?

Those answers should tune the next controller instead of guessing.
