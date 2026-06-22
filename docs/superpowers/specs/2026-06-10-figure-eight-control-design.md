# Figure-Eight Basement Control - Revised Design

**Status:** Implemented `TangentTrack` PID/feedforward baseline for review
**Date:** 2026-06-10
**Branch/worktree:** `control-figure-eight-design` at `.worktrees/control-figure-eight-design`
**Technical note:** `docs/superpowers/specs/2026-06-10-figure-eight-path-following-technical.md`
**Trajectory plot:** `docs/superpowers/specs/figures/figure-eight-start-and-direction.png`

## 1. Goal

Make OpenOtter follow a repeatable figure-eight path indoors from a Telegram
or iOS agent command. This milestone intentionally stays below pure pursuit,
LQR, or MPC complexity, but now uses path reference heading, PID-shaped
feedback, and curvature feedforward. This baseline controller is named
`TangentTrack`.

The target behavior is:

- `/figure8` starts a closed figure-eight mission from the car's current pose.
- `/figure8_lqr` starts the same path with the experimental `LQRTrack`
  controller.
- The first target segment enters the first lobe with bounded steering, not
  hard-left or hard-right.
- Steering sign matches the firmware PWM convention.
- The car keeps looping until the operator sends `/stop`.
- The map overlay shows the active planned waypoints.
- Firmware remains the deterministic actuator and safety layer.

## 2. Design Requirements And Constraints

`TangentTrack` is the formal baseline controller for `/figure8`. It is designed
for an indoor basement environment with no front wheel angle sensor, imperfect
low-speed yaw response, and firmware-owned safety supervision. The controller
therefore keeps the path-following math in iOS, sends only normalized steering
and throttle requests to firmware, and relies on firmware for PWM clamping,
slew limiting, watchdog behavior, and safety braking.

The controller must satisfy these requirements:

1. **Use the operator's current pose as the path anchor.** The command starts
   the figure eight at the car's pose from the first planning tick, not at a
   fixed ARKit/map origin. This makes the command repeatable anywhere in the
   basement.
2. **Render and follow the same path.** The red app-map reference overlay must
   come from the same waypoint samples used by the controller, and it should
   remain visible while other driving commands are selected so the operator can
   compare planned and actual motion.
3. **Follow a closed horizontal infinity path.** The long axis is app-map
   left/right along `+Z/-Z`; the shorter width is app-map forward/back along
   `+X/-X`. The default envelope is $3.2\ \mathrm{m}$ by
   $1.6\ \mathrm{m}$.
4. **Honor steering sign conventions.** Robot-right path error must produce
   positive steering because firmware maps positive normalized steering to
   right PWM.
5. **Advance along the path robustly.** The planner should not get stuck
   chasing one missed waypoint. It searches a bounded future window and tracks
   the closest valid path segment on the closed loop.
6. **Control heading and lateral position together.** A point-chasing waypoint
   rule is not enough for this path. The baseline uses path tangent heading,
   signed cross-track error, PID-shaped steering feedback, and curvature
   feedforward.
7. **Keep speed practical and visible.** The default `/figure8` throttle is
   $0.4$, with speed reduced for large path-heading error or heavy steering
   load and with limited anti-stall support when measured speed is very low.
8. **Avoid abrupt steering commands.** iOS may request the full normalized
   steering range $[-1,1]$, but firmware must clamp and slew PWM so full-range
   requests remain bounded at the actuator.

These requirements intentionally keep `TangentTrack` understandable and
testable. The next controller, `LQRTrack`, can use the same path reference to
compare model-based speed and steering control against this baseline.

## 3. Coordinate, Yaw, And PWM Invariants

OpenOtter planner code uses a two-dimensional app-map ground plane derived
from ARKit. The controls convention follows the standard robotics/vehicle
body frame used by [ROS REP-103](https://github.com/ros-infrastructure/rep/blob/master/rep-0103.rst):
vehicle $+x$ points forward, vehicle $+y$ points left, vehicle $+z$ points
up, and positive yaw rotates the vehicle counter-clockwise by the right-hand
rule. OpenOtter's app map stores the lateral screen-right coordinate as `z`,
so each symbol below names the frame it belongs to.

| Symbol | Meaning |
| --- | --- |
| $M$ | app-map frame; points are stored as $(x_M,z_M)$ |
| $+x_M$ | forward/up on the app map when yaw is zero |
| $+z_M$ | right/horizontal on the app map when yaw is zero |
| $B$ | standard vehicle body frame; $+x_B$ forward, $+y_B$ left, $+z_B$ up |
| $L$ | OpenOtter mission-local frame; $x_L=x_B$ and $z_L=-y_B$ |
| $\psi$ | `pose.yaw`, measured in radians from $+x_M$ |
| $\psi=0$ | car nose points along $+x_M$ |
| $\psi>0$ | car nose turns left toward $-z_M$ |
| $\psi<0$ | car nose turns right toward $+z_M$ |

![Coordinate convention diagram](figures/figure-eight-coordinate-conventions.png)

Yaw and steering use different signs. Positive yaw means the car body is
rotated left in the ground-plane frame. Positive steering command means the
front wheel is commanded right. This sign difference is intentional and is why
the controller equations are explicit about yaw sign and steering sign.

| Symbol | Definition |
| --- | --- |
| $\!{}^{M}\mathbf{e}_{x_B}$ | body forward unit axis, expressed in app-map $(x_M,z_M)$ components |
| $\!{}^{M}\mathbf{e}_{y_B}$ | body left unit axis, expressed in app-map $(x_M,z_M)$ components |
| $\!{}^{M}\mathbf{e}_{z_L}$ | OpenOtter mission-local right unit axis, expressed in app-map $(x_M,z_M)$ components |

Yaw rotates the standard vehicle body axes into app-map coordinates:

$$
{}^{M}\mathbf{e}_{x_B} =
\begin{bmatrix}
\cos\psi \\
-\sin\psi
\end{bmatrix},
\qquad
{}^{M}\mathbf{e}_{y_B} =
\begin{bmatrix}
-\sin\psi \\
-\cos\psi
\end{bmatrix}
$$

OpenOtter trajectory code uses `localZ` as the right-positive lateral axis.
That axis is the opposite of standard body-left:

$$
{}^{M}\mathbf{e}_{z_L} =
-{}^{M}\mathbf{e}_{y_B} =
\begin{bmatrix}
\sin\psi \\
\cos\psi
\end{bmatrix}
$$

At $\psi=0$, these become
$\!{}^{M}\mathbf{e}_{x_B}=(1,0)$,
$\!{}^{M}\mathbf{e}_{y_B}=(0,-1)$, and
$\!{}^{M}\mathbf{e}_{z_L}=(0,1)$. At $\psi=\pi/2$, the car nose points left on
the app map, so $\!{}^{M}\mathbf{e}_{x_B}=(0,-1)$.

Firmware PWM convention is:

| Normalized steering | PWM | Meaning |
| --- | --- | --- |
| $-1.0$ | $1000\ \mu\mathrm{s}$ | full left |
| $0.0$ | $1500\ \mu\mathrm{s}$ | centered |
| $+1.0$ | $2000\ \mu\mathrm{s}$ | full right |

`PoseMapView` renders the same ground plane as:

| Ground-plane direction | App-map direction |
| --- | --- |
| $+z$ | screen right |
| $+x$ | screen up / forward |

Therefore a horizontal figure-eight on the app map uses `+Z/-Z` as the long
left/right axis and `+X/-X` as the shorter forward/back width. A target at
robot-right must produce **positive** steering. These invariants are locked by
`RobotGeometryTests`, `FigureEightTrajectoryTests`, and
`TangentTrackPlannerTests`.

## 4. Controller Strategy

The baseline finite-waypoint controller still points at the current waypoint:

$$
\Delta x = x_{\mathrm{target}} - x,
\qquad
\Delta z = z_{\mathrm{target}} - z
$$

$$
\psi_{\mathrm{desired}} = \mathrm{atan2}(-\Delta z,\Delta x),
\qquad
e_{\psi} = \mathrm{wrapToPi}(\psi_{\mathrm{desired}}-\psi)
$$

For the closed-loop figure-eight, the controller follows the current path
segment instead of chasing a future point. The symbols are:

| Symbol | Meaning |
| --- | --- |
| $p_M$ | current car position in app-map $(x_M,z_M)$ coordinates |
| $P_0$ | start waypoint of the active path segment |
| $P_1$ | end waypoint of the active path segment |
| $\mathbf{s}$ | segment vector $P_1-P_0$ |
| $\alpha$ | scalar progress along the segment, clamped from $0$ to $1$ |
| $P_{\mathrm{ref}}$ | closest point on the active segment |
| $\psi_{\mathrm{ref}}$ | reference yaw of the path tangent |
| $P$ | path frame at $P_{\mathrm{ref}}$ |
| $\!{}^{M}\mathbf{e}_{x_P}$ | path-tangent unit axis, expressed in app-map coordinates |
| $\!{}^{M}\mathbf{e}_{z_P}$ | path-right unit axis, expressed in app-map coordinates |
| $e_{\mathrm{ct}}$ | signed cross-track error; positive means car is right of the path |

![Path-reference geometry diagram](figures/path-reference-geometry.png)

Let $P_0$ and $P_1$ be the current path segment endpoints, $p_M$ be the car
position, and $\mathbf{s}=P_1-P_0$. The segment projection is:

$$
\alpha =
\mathrm{clip}
\left(
\frac{(p_M-P_0)\cdot\mathbf{s}}{\mathbf{s}\cdot\mathbf{s}},
0,
1
\right),
\qquad
P_{\mathrm{ref}} = P_0 + \alpha\mathbf{s}
$$

$$
\psi_{\mathrm{ref}} =
\mathrm{atan2}\left(-(P_{1,z}-P_{0,z}),\,P_{1,x}-P_{0,x}\right)
$$

The negative sign on the $z$ difference is required by the yaw convention. A
segment moving straight forward has $\Delta z=0$ and therefore
$\psi_{\mathrm{ref}}=0$. A segment moving to the app-map right has
$\Delta x=0$, $\Delta z>0$, and therefore
$\psi_{\mathrm{ref}}=-\pi/2$, meaning the desired body yaw points right.

The path-right unit axis is:

$$
{}^{M}\mathbf{e}_{z_P} =
\begin{bmatrix}
\sin\psi_{\mathrm{ref}} \\
\cos\psi_{\mathrm{ref}}
\end{bmatrix}
$$

$$
e_{\mathrm{ct}} =
(p_M-P_{\mathrm{ref}})\cdot{}^{M}\mathbf{e}_{z_P}
$$

The desired yaw combines path tangent and lateral correction. When
$e_{\mathrm{ct}}>0$, the car is right of the path, so the desired yaw is biased
left to bring it back:

$$
\psi_{\mathrm{desired}} =
\psi_{\mathrm{ref}} +
\mathrm{atan2}
\left(k_{\mathrm{ct}}e_{\mathrm{ct}},\,d_{\mathrm{soft}}\right)
$$

$$
e_{\psi,\mathrm{steer}} =
\mathrm{wrapToPi}(\psi_{\mathrm{desired}}-\psi),
\qquad
e_{\psi,\mathrm{path}} =
\mathrm{wrapToPi}(\psi_{\mathrm{ref}}-\psi)
$$

Steering is PID-shaped heading feedback plus feedforward:

$$
\kappa \approx
\frac{\mathrm{wrapToPi}(\psi_{\mathrm{after}}-\psi_{\mathrm{before}})}
{s_{\mathrm{arc}}},
\qquad
s_{\mathrm{ff}} = -k_{\kappa}\kappa
$$

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

The controller deliberately keeps two heading errors:

- `steeringYawError` includes cross-track correction and can be aggressive.
- `pathHeadingError` is only the path tangent error and drives throttle.

This handles the important case where the car is tangent-aligned but off the
path: steering should work hard to recover, but throttle should not fade just
because the recovery heading is aggressive.

Current defaults:

| Parameter | Value |
| --- | --- |
| $s_{\max}$ | $1.0$ |
| steering throttle scale at limit | $0.70$ |
| steering full-load fraction | $0.45$ |
| $k_{\mathrm{ct}}$ | $2.2$ |
| $d_{\mathrm{soft}}$ | $0.18\ \mathrm{m}$ |
| $k_{\kappa}$ | $0.10\ \mathrm{m}$ |
| $K_p$ | $0.9/(\pi/2)$ |
| $K_i$ | $0.0$ |
| $K_d$ | $0.02$ |

The integral term is deliberately present but disabled by default. Without a
front wheel angle sensor and with steering saturation possible, integral should
only be enabled later from logs if there is a steady steering bias.

Throttle still starts from the current Telegram speed. It fades from the plain
path tangent error, slows when the car is both off the centerline and
steering-loaded, and blends in anti-stall throttle when speed feedback says the
car is stuck or nearly stuck:

$$
\tau_{\mathrm{base}} =
\tau_{\max}
\max\left(0.35,\ 1-\frac{|e_{\psi,\mathrm{path}}|}{\pi}\right)
$$

$$
\ell_s = \frac{|s|}{0.45},
\qquad
\tau_{\mathrm{scale}} =
1-(1-0.70)\ell_s\ell_{\mathrm{lat}}
$$

$$
\tau = \tau_{\mathrm{base}}\tau_{\mathrm{scale}}
$$

When $v_{\mathrm{measured}} < 0.12\ \mathrm{m/s}$ and
$|e_{\psi,\mathrm{path}}| < \pi/2$, the controller blends toward
$0.75\tau_{\max}$ as anti-stall breakaway throttle.

For closed-loop figure-eight missions, the planner also scans a short window
of future waypoints and advances to the closest one. This prevents the car from
orbiting around a waypoint it physically missed.

## 5. Figure-Eight Path

The path is a smoother Bernoulli-style lemniscate, then resampled by arc length
into evenly spaced controller waypoints:

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

The raw curve is normalized to the requested 3.2 m by 1.6 m app-map envelope:
3.2 m left/right along local `+Z/-Z`, and 1.6 m forward/back along local
`+X/-X`. This keeps the literal horizontal infinity shape, but reduces tight
corner-like curvature and gives the segment-tangent controller a smooth
reference heading.

That means:

- waypoint 0 is exactly the center crossing at the car pose when the mission
  starts,
- waypoint 1 enters the first right lobe,
- waypoint `segmentCount / 2` crosses the anchor again into the other lobe,
- the path rotates with car yaw,
- the figure eight is closed enough to loop smoothly without duplicating the
  first waypoint.

### Starting Point And Direction

The mission starts at the center crossing of the figure eight:

$$
t=0,
\qquad
x_{\mathrm{local}}=0,
\qquad
z_{\mathrm{local}}=0,
\qquad
i_{\mathrm{waypoint}}=0
$$

This mission-local point is transformed into app-map coordinates using the car
pose from the first control tick. In other words, `/figure8` treats the car's
current pose as the crossing point of the track.

Good physical setup:

1. Put the car at the desired center crossing of the 8.
2. Point the car's nose along the desired forward/back width axis of the 8.
3. The long $3.2\ \mathrm{m}$ axis will run left/right across the car on the
   app map.
4. Leave about $0.8\ \mathrm{m}$ clear in front and behind the car.
5. Leave about $1.6\ \mathrm{m}$ clear on each side.
6. Send `/figure8`.

The orange map marker is this start/crossing point. Its arrow shows the first
desired motion. The green ego heading should roughly agree with that arrow
before launch. If the green heading points across the track instead, the first
seconds will be spent recovering heading error, and the actual blue trace will
usually bulge outside the reference.

The first segment moves into the forward/right branch:

$$
x_{\mathrm{local},1} > 0,
\qquad
z_{\mathrm{local},1} > 0
$$

At `segmentCount / 2`, the path crosses the same center point again, then
enters the opposite lobe. The plot below is generated from the same 240
waypoint samples that the controller follows:

![Figure-eight start and direction plot](figures/figure-eight-start-and-direction.png)

Current default command parameters:

| Parameter | Default |
| --- | --- |
| `segmentCount` | $240$ |
| `length` | $3.2\ \mathrm{m}$ |
| `width` | $1.6\ \mathrm{m}$ |
| `acceptanceRadius` | $0.12\ \mathrm{m}$ |
| figure-eight throttle | current Telegram speed, with no hidden boost |
| default `/figure8` throttle | $0.4$ |
| maximum steering | $1.0$ |
| progress search | $32$ future samples |

`length` and `width` are app-map envelope parameters, not mathematical `x` and
`z` dimensions: `length` is the horizontal `+Z/-Z` span, and `width` is the
vertical `+X/-X` span. The current default is 80% of the previous
`4.0 m x 2.0 m` envelope, giving the controller more basement wall margin while
preserving the same horizontal infinity shape. The tighter acceptance radius
keeps the startup waypoints from being consumed too aggressively at the center
crossing. `TangentTrack` makes the front wheel visibly turn for the first lobe,
while firmware clamps and slews the PWM command so full-range steering remains
bounded and less abrupt. The tests verify the path stays inside the configured
app-map horizontal infinity dimensions, crosses the anchor halfway through the
loop, forms a continuous loop, keeps adjacent waypoint spacing even, avoids the
old tight corner-like curvature, and tracks the path under a slow-yaw
regression model.

## 6. Runtime Flow

```text
Telegram /figure8
  -> KeywordInterpreter.figureEight
  -> ActionDispatcher
  -> PlannerGoal.followFigureEight(config, maxThrottle, controller: .tangentTrack)
  -> PlannerOrchestrator switches to TangentTrackPlanner
  -> first control tick anchors waypoints from PlannerContext.pose
  -> TangentTrack emits steering/throttle
  -> SafetySupervisor may brake
  -> STM32 receives PWM command
```

Anchoring inside `TangentTrackPlanner.plan(context:)` is deliberate. Telegram does
not have pose. The planner does. The Swift implementation type remains
`TangentTrackPlanner`, while its controller/telemetry name is `TangentTrack`.

Experimental LQR flow uses the same trajectory and anchor:

```text
Telegram /figure8_lqr
  -> KeywordInterpreter.figureEight(controller: .lqrTrack)
  -> ActionDispatcher
  -> PlannerGoal.followFigureEight(config, maxThrottle, controller: .lqrTrack)
  -> PlannerOrchestrator switches to LQRTrackPlanner
  -> LQRTrack emits steering/throttle from shared path reference state
```

## 7. Component Ownership

### iOS

- `FigureEightTrajectory` generates waypoint paths.
- `RobotGeometry` owns yaw and mission-local-to-app-map transformations.
- `TangentTrackPlanner` implements the `TangentTrack` controller: waypoint
  advancement, tangent-heading feedback, curvature feedforward, throttle
  shaping, and figure-eight looping.
- `PathReference` owns shared projection, tangent heading, signed
  cross-track error, and curvature for controller comparison.
- `LQRTrackPlanner` implements the experimental `LQRTrack` controller for
  `/figure8_lqr`.
- `PlannerOrchestrator` routes figure-eight goals to the `TangentTrackPlanner`
  or `LQRTrackPlanner` implementation and publishes active/reference waypoints
  for UI overlay.
- `ActionDispatcher` maps `/figure8` and `/figure8_lqr` to figure-eight planner
  goals with explicit controller selection.
- `PoseMapView` receives active waypoints through `SelfDrivingView`.

### Firmware

Firmware does not own figure-eight tracking. It continues to own:

- PWM clamping,
- watchdog neutral behavior,
- Park/Drive arbitration,
- forward and reverse safety supervision.

No firmware changes are required for this iOS path-following baseline.

## 8. Tests

The implementation is covered by:

- `RobotGeometryTests` for forward/right axis invariants.
- `FigureEightTrajectoryTests` for defaults, horizontal infinity bounds,
  anchoring, yaw rotation, center crossing, and loop continuity.
- `TangentTrackPlannerTests` for steering sign, anchored figure-eight startup,
  steering cap, missed-waypoint skip-ahead, lateral-error correction from a
  path tangent, finite waypoint completion, closed figure-eight looping, and a
  slow-yaw simulation that checks segment cross-track error, reference-heading
  error, and envelope overshoot.
- `PlannerOrchestratorTests` for routing and active waypoint publication.
- `ActionDispatcherTests` and `AgentRuntimeTests` for `/figure8` command flow.
- `LQRMathTests` and `LQRTrackPlannerTests` for the experimental LQR speed and
  steering controller.
- `tools/trajectory-sim/tests` for local Python prototype parity and
  simulation behavior.
- Existing safety tests still cover forward/reverse braking behavior.

Verification command:

```bash
SIMULATOR_UDID=40B418BA-9B70-4B34-9D13-81E3A3F281A9 bash openotter-ios/build.sh test
```

## 9. Controller Comparison

`LQRTrack` is now available as `/figure8_lqr`, an experimental LQR
speed-and-steering controller based on the same path reference but with a small
state-space model and quadratic cost. Its design is documented in
`docs/superpowers/specs/2026-06-15-lqr-track-design.md`, and its math/pseudocode
is documented in `docs/superpowers/specs/2026-06-15-lqr-track-technical.md`.
`TangentTrack` stays the default, understandable `/figure8` baseline for
comparison.
