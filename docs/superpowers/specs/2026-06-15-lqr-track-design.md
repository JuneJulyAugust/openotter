# LQRTrack Speed And Steering Control Design

**Status:** Initial implementation behind `/figure8_lqr`, not the default `/figure8` controller
**Date:** 2026-06-15
**Baseline controller:** `TangentTrack`
**Experimental controller:** `LQRTrack`
**Companion technical note:** `docs/superpowers/specs/2026-06-15-lqr-track-technical.md`
**References:**

- PythonRobotics LQR speed/steer example:
  `https://github.com/AtsushiSakai/PythonRobotics/tree/master/PathTracking/lqr_speed_steer_control`
- PythonRobotics technical page:
  `https://atsushisakai.github.io/PythonRobotics/modules/6_path_tracking/lqr_speed_and_steering_control/lqr_speed_and_steering_control.html`
- Source function:
  `https://raw.githubusercontent.com/AtsushiSakai/PythonRobotics/master/PathTracking/lqr_speed_steer_control/lqr_speed_steer_control.py`

## 1. Design Goal

`LQRTrack` is a second figure-eight controller for learning and comparison. It
does not replace `TangentTrack`. The point is to test whether a model-based
controller can keep the car closer to the red reference path while still
commanding enough speed to avoid crawling.

The tracking problem is coupled: steering and speed affect each other. If
steering is late, the blue trajectory balloons outside the lobe. If throttle
fades too much, the car turns but barely moves. `TangentTrack` handles those
two problems with separate practical rules. `LQRTrack` handles them in one
scoring problem: large tracking errors cost points, and large actuator commands
also cost points. The controller chooses the steering and speed corrections
with the best tradeoff.

The design success criterion is modest and testable:

- `/figure8` still runs the default `TangentTrack` baseline.
- `/figure8_lqr` runs `LQRTrack` on the same reference trajectory.
- The map, simulation, and tests can compare both controllers on the same
  figure-eight path.
- The LQR controller clamps outputs and fails neutral if the math solve is not
  trustworthy.

## 2. What LQRTrack Is And Is Not

The important design choice is separation. `TangentTrack` remains the default
because it has already completed the real basement figure eight. `LQRTrack` is
an explicit experiment because its model has assumptions that still need field
tuning.

| Command | Controller | Purpose |
| --- | --- | --- |
| `/figure8` | `TangentTrack` | default field controller |
| `/figure8_lqr` | `LQRTrack` | model-based controller experiment |

`LQRTrack` is not a perfect car model. OpenOtter does not measure front wheel
angle, and the ESC throttle command is not a calibrated acceleration command.
Instead, the controller uses ARKit pose feedback every tick. The model only
needs to be good enough to choose useful steering and throttle corrections
between feedback updates.

The practical mental model is:

1. Measure where the car is relative to the path.
2. Build a short list of errors.
3. Use LQR to decide how much to correct steering and speed.
4. Add path-curvature feedforward so the car starts turning before it drifts.
5. Clamp the final steering and throttle before safety supervision.

## 3. Shared Path Contract

Both controllers must follow the same path. Otherwise controller comparisons
are meaningless. `FigureEightTrajectory` owns the path shape, and
`PathReference` owns projection onto that path.

Every controller comparison uses the same coordinate and path contract. The
vehicle-body frame follows [ROS REP-103](https://github.com/ros-infrastructure/rep/blob/master/rep-0103.rst);
OpenOtter's app-map storage keeps its existing $z_M$-right coordinate.

| Quantity | Convention |
| --- | --- |
| external vehicle-frame source | ROS REP-103: $+x_B$ forward, $+y_B$ left, $+z_B$ up |
| $M$ | app-map frame; equations store points as $(x_M,z_M)$ |
| `PoseMapView` screen up | app-map $+x_M$ forward |
| `PoseMapView` screen right | app-map $+z_M$ right |
| $B$ | standard vehicle body frame |
| $L$ | OpenOtter mission-local frame; $x_L=x_B$, $z_L=-y_B$ |
| $P$ | path frame at the projected point; $x_P$ tangent, $z_P$ path-right |
| yaw symbol | $\psi$, the same value as `pose.yaw` |
| $\psi=0$ | car nose points along $+x_M$ |
| $\psi>0$ | car nose turns left toward $-z_M$ |
| positive steering command | front wheel steers right |
| `length` | $3.2\ \mathrm{m}$ along $+z_M/-z_M$ |
| `width` | $1.6\ \mathrm{m}$ along $+x_M/-x_M$ |
| start point | center crossing at the car pose when the mission starts |
| first branch | forward and right from the start crossing |

![Coordinate convention diagram](figures/figure-eight-coordinate-conventions.png)

The yaw sign and steering sign are different on purpose. Positive yaw is a
left body rotation, while positive steering is a right wheel command. This
must stay explicit in both `TangentTrack` and `LQRTrack`.

`PathReference.project(...)` is the shared interface between the path and the
controllers. It should answer one question: "At this tick, where is the car
relative to the path it is supposed to follow?"

![Path-reference geometry diagram](figures/path-reference-geometry.png)

```text
PathReference.project(pose, waypoints, currentIndex)
  -> progress index
  -> projected point on the path
  -> tangent yaw at that point, psi_ref
  -> signed cross-track error, e_ct
  -> curvature
```

This shared contract keeps the experiment honest. If `LQRTrack` improves or
regresses, the difference comes from the controller, not from a different
trajectory.

## 4. Controller Data Flow

`LQRTrack` should sit at the same ownership level as `TangentTrack`: inside the
iOS planner layer. Firmware should not know about the figure-eight path or the
LQR math. Firmware remains the deterministic actuator layer.

```text
Telegram /figure8_lqr
  -> KeywordInterpreter.figureEight(controller: .lqrTrack)
  -> ActionDispatcher
  -> PlannerGoal.followFigureEight(config, maxThrottle, controller: .lqrTrack)
  -> PlannerOrchestrator switches to LQRTrackPlanner
  -> LQRTrackPlanner asks PathReference for path-relative errors
  -> LQRMath solves the small LQR problem
  -> LQRTrackPlanner emits steering and throttle
  -> SafetySupervisor may brake or neutralize
  -> STM32 receives bounded actuator commands
```

The boundary is intentional:

- `FigureEightTrajectory` generates the reference path.
- `PathReference` computes path-relative geometry.
- `LQRMath` owns matrix operations and Riccati solving.
- `LQRTrackPlanner` owns controller state, actuator mapping, and planner output.
- `SafetySupervisor` owns obstacle/sensor overrides.
- STM32 firmware owns PWM clamping, watchdog neutral, and Park/Drive
  arbitration.

## 5. Error State

LQR works by controlling a state vector. For OpenOtter, the state vector should
contain five errors:

$$
\mathbf{x} =
\begin{bmatrix}
e &
\dot{e} &
\theta_e &
\dot{\theta}_e &
v_e
\end{bmatrix}^{\top}
$$

| Error | Plain-English meaning | Why it matters |
| --- | --- | --- |
| $e$ | sideways distance from the path | tells whether the car is outside the lobe |
| $\dot{e}$ | whether sideways error is growing | catches drift before position error is huge |
| $\theta_e$ | heading error from the path tangent | tells whether the car points along the red path |
| $\dot{\theta}_e$ | whether heading error is growing | damps steering oscillation |
| $v_e$ | measured speed minus target speed | tells whether the car is crawling or too fast |

![LQR error-state diagram](figures/lqr-error-state.png)

OpenOtter's path geometry reports $e_{\mathrm{ct}}>0$ when the car is right of
the path. `LQRTrack` uses $e=-e_{\mathrm{ct}}$ internally so the LQR steering
sign lines up with the normalized OpenOtter steering command:

- positive normalized steering means right,
- a car right of the path should usually steer left,
- a positive heading error $\theta_e=\mathrm{wrapToPi}(\psi-\psi_{\mathrm{ref}})$
  means the car body is yawed left of the path tangent,
- at the center crossing, the first branch points forward/right, so a car that
  starts at $\psi=0$ has positive $\theta_e$ and should steer right.

This sign convention is not a detail. It is a safety-critical contract and
must stay covered by tests.

## 6. Model And Cost

The model is the controller's small prediction rule. It says how the five
errors are expected to change over one control tick:

$$
\mathbf{x}_{k+1}=A\mathbf{x}_k+B\mathbf{u}_k
$$

The input vector has two corrections:

$$
\mathbf{u} =
\begin{bmatrix}
u_{\delta} &
u_a
\end{bmatrix}^{\top}
$$

where $u_{\delta}$ is the LQR model's steering-angle-like input and $u_a$ is
the LQR model's acceleration input. These are internal model quantities. They
are not sent directly to firmware. OpenOtter later maps them to the normalized
actuator commands $u_{\mathrm{steer}}$ and $\tau$.

The design follows the PythonRobotics LQR speed/steer structure:

$$
A =
\begin{bmatrix}
1 & \Delta t & 0 & 0 & 0 \\
0 & 0 & v & 0 & 0 \\
0 & 0 & 1 & \Delta t & 0 \\
0 & 0 & 0 & 0 & 0 \\
0 & 0 & 0 & 0 & 1
\end{bmatrix},
\qquad
B =
\begin{bmatrix}
0 & 0 \\
0 & 0 \\
0 & 0 \\
v/L & 0 \\
0 & \Delta t
\end{bmatrix}
$$

Here $\Delta t$ is tick duration, $v$ is measured speed, and $L$ is an
effective wheelbase or tuning length. `L` should start near the physical
wheelbase if known, but it is allowed to be a tuning value because the car does
not report actual steering angle.

LQR chooses commands by minimizing this score:

$$
J = \sum_{k=0}^{N}
\left(
\mathbf{x}_k^\top Q \mathbf{x}_k +
\mathbf{u}_k^\top R \mathbf{u}_k
\right)
$$

The design meaning is simple:

- $Q$ decides which errors are expensive.
- $R$ decides which actuator efforts are expensive.
- Larger $Q$ makes the controller fight that error harder.
- Larger $R$ makes the controller use that actuator more gently.

The vector $\mathbf{u}_k$ in the score is the internal LQR model input. The
firmware-facing steering command is named $u_{\mathrm{steer}}$ later in the
mapping section.

## 7. Feedforward And Actuator Mapping

LQR computes feedback, but feedback should not do all steering work. The path
already tells us when a lobe is about to curve. That known bend becomes
feedforward steering. The final actuator command is therefore still the same
practical structure used by `TangentTrack`:

1. use the path curvature for a steering bias,
2. use LQR feedback to correct measured tracking error,
3. add the two steering terms,
4. clamp the result before firmware sees it.

### 7.1 Symbols

The actuator symbols are:

| Symbol | Meaning |
| --- | --- |
| $\mathbf{f}$ | raw LQR feedback vector $K\mathbf{x}$ |
| $f_0$ | steering channel of $\mathbf{f}$ |
| $f_1$ | speed channel of $\mathbf{f}$ |
| $u_{\mathrm{ff}}$ | curvature feedforward steering command |
| $u_{\mathrm{steer,fb}}$ | steering feedback command from the LQR gain |
| $u_{\mathrm{steer}}$ | final normalized steering command |
| $u_a$ | acceleration-like throttle trim from LQR feedback |
| $\tau$ | final normalized throttle command |

### 7.2 Curvature Feedforward

Feedforward comes from the reference path, not from the measured tracking
error. If the path curvature $\kappa$ says the next segment bends left, the
controller can request left steering before the blue trace has drifted outside
the red path.

$$
u_{\mathrm{ff}}=-k_{\kappa}\kappa
$$

The negative sign matches OpenOtter's actuator convention: positive
$\kappa$ means the reference yaw turns left, while positive steering command
means the front wheel steers right.

### 7.3 LQR Feedback

LQR feedback corrects real tracking error. The gain matrix $K$ turns the
five-value error state into two feedback channels:

$$
\mathbf{f}=K\mathbf{x}
$$

The first channel, $f_0$, is the steering-like feedback channel. The second
channel, $f_1$, is the speed-like feedback channel. They are still internal
controller values, not firmware commands.

### 7.4 Final Steering Command

The steering feedback channel is scaled into the same normalized steering
units used by firmware:

$$
u_{\mathrm{steer,fb}}=k_{\mathrm{steer}} f_0
$$

The final steering command adds curvature feedforward and feedback:

$$
u_{\mathrm{steer}} =
\mathrm{clip}
\left(
u_{\mathrm{ff}} + u_{\mathrm{steer,fb}},
-1,
1
\right)
$$

### 7.5 Final Throttle Command

Speed control uses the second LQR feedback channel as a throttle trim around a
base throttle. The sign conversion below keeps the command intuitive: if the
car is below target speed, the resulting trim should increase throttle.

$$
u_a=-f_1
$$

$$
\tau =
\mathrm{clip}
\left(
\tau_{\mathrm{base}} + k_{\tau}u_a,
0,
\tau_{\max}
\right)
$$

The target speed should start conservatively:

$$
v_{\mathrm{target}} = 0.20\ \mathrm{m/s}
$$

The throttle ceiling remains the current Telegram speed, default $0.4$. This
keeps operator intent visible: testing faster should be an explicit command,
not a hidden controller multiplier.

## 8. Initial Tuning Policy

Start with diagonal weights. This keeps tuning understandable because each
weight belongs mostly to one error or one actuator.

$$
Q = \mathrm{diag}(3.0,\ 0.2,\ 2.5,\ 0.2,\ 0.8),
\qquad
R = \mathrm{diag}(1.0,\ 2.0)
$$

| Symptom | First tuning move | Reason |
| --- | --- | --- |
| blue trace balloons outside the lobe | raise lateral $Q$ or heading $Q$ | tracking error is too cheap |
| steering chatters or servo ticks | raise steering $R$ or reduce $k_{\mathrm{steer}}$ | steering effort is too cheap |
| car crawls while tracking is stable | raise target speed or lower throttle $R$ | speed error is too cheap |
| throttle surges | raise throttle $R$ or reduce $k_{\tau}$ | acceleration effort is too cheap |
| controller reacts badly after reacquiring path | reset derivative memory on large index jumps | old rates no longer describe the new reference |

Tuning should use simulation first, then basement logs. Guessing from one map
screenshot is tempting, but logs make it clear whether the problem is lateral
error, heading error, speed error, saturation, or a sign mistake.

## 9. Implementation Files

Implemented code structure:

```text
openotter-ios/Sources/Planner/PathReference.swift
  Shared path projection, tangent, curvature, and progress helper.

openotter-ios/Sources/Planner/Controllers/LQRMath.swift
  Small fixed-size matrix utilities and DARE solver.

openotter-ios/Sources/Planner/Planners/LQRTrackPlanner.swift
  PlannerProtocol implementation for figure-eight LQR speed/steer.

openotter-ios/Sources/Planner/PlannerProtocol.swift
  Adds figure-eight controller selection to planner goals.

openotter-ios/Sources/Agent/KeywordInterpreter.swift
openotter-ios/Sources/Agent/ActionDispatcher.swift
  Adds /figure8_lqr command and keeps /figure8 on TangentTrack.

tools/trajectory-sim/
  Local Python package for controller prototyping, deterministic simulation,
  and comparison plots.
```

Do not add a heavy math dependency. The state has five values and the input
has two values, so a deterministic small-matrix implementation is enough for
iOS.

## 10. Tests And Rollout

The tests should protect the design contracts, not just line coverage.

| Test area | Contract |
| --- | --- |
| `LQRMathTests` | DARE solve converges, gain is finite, singular inverse fails safely |
| `LQRTrackPlannerTests` | right-of-path error steers left, left error steers right |
| `LQRTrackPlannerTests` | below target speed increases throttle, above target speed reduces it |
| `LQRTrackPlannerTests` | reference reacquisition resets derivative memory |
| `ActionDispatcherTests` | `/figure8_lqr` selects LQR without changing `/figure8` |
| Python simulation tests | LQR makes progress on the same figure-eight path as TangentTrack |

`LQRTrack` is safe to field-test as an explicit experiment when these remain
true:

- outputs are finite,
- steering is clamped to $[-1,1]$,
- throttle is clamped to $[0,\tau_{\max}]$,
- failed LQR solves output neutral for that tick,
- map overlay shows the same reference trajectory and direction arrows,
- `/figure8` still runs `TangentTrack`.

The first field comparison should focus on four numbers: maximum lateral
overshoot, 95th-percentile cross-track error, average speed, and steering
saturation time. Those numbers tell whether LQR is actually improving the
basement trajectory or merely looking more sophisticated in code.
