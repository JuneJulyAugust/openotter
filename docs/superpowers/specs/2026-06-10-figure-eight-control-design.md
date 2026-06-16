# Figure-Eight Basement Control - Revised Design

**Status:** Implemented `TangentTrack` PID/feedforward baseline for review
**Date:** 2026-06-10
**Branch/worktree:** `control-figure-eight-design` at `.worktrees/control-figure-eight-design`
**Technical note:** `docs/superpowers/specs/2026-06-10-figure-eight-path-following-technical.md`
**Trajectory plot:** `docs/superpowers/specs/2026-06-10-figure-eight-trajectory-plot.svg`

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

## 2. Field Failure Review

Observed behavior:

- front wheels turned left,
- the car moved slowly for a while,
- then it stopped.

Root causes in the first implementation:

1. **Steering sign was inverted.** Firmware and `PwmMapping` define negative
   steering as left and positive steering as right, but the first
   `TangentTrackPlanner` implementation produced negative steering for a target on
   robot-right.
2. **Figure-eight waypoints were not anchored to the current pose.** The
   command built a small path around ARKit world `(0, 0)` instead of the car's
   pose when the mission began.
3. **The path was too small and finite.** A `0.8 m x 0.5 m` one-lap waypoint
   list can be consumed quickly, after which the planner correctly emits
   neutral. From the operator seat, that looks like the mission died.
4. **The map overlay used stale state.** `SelfDrivingViewModel.waypoints` was
   never populated, so the UI was not showing the actual active path.

Second field review after the waypoint baseline:

- The requested trajectory is a horizontal infinity-track figure eight, not a
  rotated/diagonal center-crossing convenience curve.
- The car's map trace collapsed into one lobe, which is consistent with a
  waypoint follower chasing a missed waypoint instead of advancing along the
  closed path.
- The front wheel servo made end-stop chatter during abrupt command changes.
  The revised policy is to allow full normalized steering authority in the
  app, clamp PWM to the safe firmware range, and slew steering PWM changes in
  firmware so full-range requests do not become instantaneous servo jumps.

Third field review after raising mission speed:

- `0.6` normalized throttle was too fast for the basement test.
- The car still looked like it did not turn enough to follow the figure eight.
- The controller's computed initial steering was only about `0.23`, which is
  mathematically nonzero but may be too weak to overcome steering deadband,
  carpet load, or linkage friction.
- The earlier `0.25 m` waypoint acceptance radius was also too loose for the
  roughly `5 cm` waypoint spacing, so the controller could skip the first
  shaping waypoints at the center crossing.

Fourth field review after the smaller 3.2 m by 1.6 m path:

- The reference figure-eight shape appeared correctly on the map.
- The actual car trajectory still ballooned outside the lobes, and heading was
  visibly not aligned with the reference path direction.
- A deterministic slow-yaw simulation reproduced this behavior: the older
  point follower made progress, but reached about `0.40 m` max path error.

The fix is not to jump to MPC. The practical upgrade is to keep the waypoint
path, but control against the path tangent, signed lateral error, and simple
curvature feedforward.

## 3. Coordinate And PWM Invariants

OpenOtter planner code uses the ARKit ground plane as:

| Axis | Meaning |
| --- | --- |
| $+x$ | robot forward |
| $+z$ | robot right |
| $\psi = 0$ | facing $+x$ |

Yaw rotates the robot's local axes into world coordinates:

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
`FigureEightTrajectoryTests` and `TangentTrackPlannerTests`.

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

For the closed-loop figure-eight, the controller now follows the current path
segment instead of chasing a future point:

Let $P_0$ and $P_1$ be the current path segment endpoints, $p$ be the car
position, and $\mathbf{s}=P_1-P_0$. The segment projection is:

$$
\alpha =
\mathrm{clip}
\left(
\frac{(p-P_0)\cdot\mathbf{s}}{\mathbf{s}\cdot\mathbf{s}},
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

$$
e_{\mathrm{ct}} =
(p-P_{\mathrm{ref}})\cdot
\begin{bmatrix}
\sin\psi_{\mathrm{ref}} \\
\cos\psi_{\mathrm{ref}}
\end{bmatrix}
$$

The desired yaw combines path tangent and lateral correction:

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

This prevents the field failure where the car is tangent-aligned but off the
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

This local point is transformed into world coordinates using the car pose from
the first control tick. In other words, `/figure8` treats the car's current
pose as the crossing point of the track.

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

![Figure-eight trajectory plot](2026-06-10-figure-eight-trajectory-plot.svg)

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
- `RobotGeometry` owns yaw/local/world transformations.
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
`TangentTrack` stays the understandable, field-tested `/figure8` baseline for
comparison.
