# LQRTrack Technical Note

**Status:** Technical note for initial `LQRTrack` implementation
**Date:** 2026-06-15
**Companion design:** `docs/superpowers/specs/2026-06-15-lqr-track-design.md`

## 1. What This Document Teaches

This note explains `LQRTrack` from first principles. It assumes comfort with
algebra, graphs, and functions, but not college control theory.

The shortest useful explanation is:

1. The path gives a desired position, heading, curvature, and target speed.
2. The car gives its measured position, heading, and speed.
3. The controller turns those measurements into five errors.
4. LQR chooses steering and speed corrections that reduce those errors without
   using unnecessarily harsh commands.
5. OpenOtter converts those corrections into normalized steering and throttle,
   then lets the safety supervisor override them if needed.

`TangentTrack` and `LQRTrack` share the same red figure-eight path. The
difference is how they decide the next steering and throttle command.
`TangentTrack` uses hand-shaped PID/feedforward rules. `LQRTrack` uses a small
prediction model plus a weighted score.

## 2. The Four Questions Per Control Tick

Every tick should answer the same four questions in this order:

1. **Where am I on the path?** Project the car position onto the reference
   path and find the tangent direction.
2. **What errors matter right now?** Measure sideways error, heading error,
   speed error, and whether those errors are growing.
3. **What correction best balances tracking and smoothness?** Use LQR to
   trade off error reduction against steering/throttle effort.
4. **What can the actuators safely receive?** Add curvature feedforward,
   convert to normalized commands, clamp, and pass through safety supervision.

This order is important. LQR does not replace path geometry, and it does not
replace actuator limits. It sits between them.

## 3. Coordinate And Sign Contract

Most controller mistakes in this feature are sign mistakes, so the coordinate
contract comes first. The vehicle-body convention follows
[ROS REP-103](https://github.com/ros-infrastructure/rep/blob/master/rep-0103.rst):
vehicle $+x$ points forward, vehicle $+y$ points left, vehicle $+z$ points
up, and positive yaw rotates the vehicle counter-clockwise by the right-hand
rule. OpenOtter's app map stores ground-plane points as $(x_M,z_M)$, where
$z_M$ is screen-right, so each equation names the frame explicitly.

| Symbol or quantity | Meaning |
| --- | --- |
| $M$ | app-map frame; a point is $p_M=[x_M,z_M]^\top$ |
| $+x_M$ | forward/up ground-plane coordinate |
| $+z_M$ | right/horizontal ground-plane coordinate |
| $B$ | standard vehicle body frame; $+x_B$ forward, $+y_B$ left, $+z_B$ up |
| $L$ | OpenOtter mission-local frame; $x_L=x_B$ and $z_L=-y_B$ |
| $\psi$ | the math symbol for `pose.yaw`, in radians |
| $\psi=0$ | car nose points along $+x_M$ |
| $\psi>0$ | car nose rotates left toward $-z_M$ |
| $\psi<0$ | car nose rotates right toward $+z_M$ |
| positive steering command | front wheel steers right |
| figure-eight length | $3.2\ \mathrm{m}$ along $+z_M/-z_M$ |
| figure-eight width | $1.6\ \mathrm{m}$ along $+x_M/-x_M$ |

![Coordinate convention diagram](figures/figure-eight-coordinate-conventions.png)

Yaw sign and steering sign are not the same thing. Positive yaw means the car
body has rotated left. Positive steering means the front wheel is commanded
right. This is why the controller equations use explicit signs instead of
saying only "positive means turn."

For any yaw angle, the standard vehicle body axes expressed in the app-map
frame are:

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

OpenOtter's mission-local `localZ` axis points right, so it is the opposite of
standard body-left:

$$
{}^{M}\mathbf{e}_{z_L} =
-{}^{M}\mathbf{e}_{y_B} =
\begin{bmatrix}
\sin\psi \\
\cos\psi
\end{bmatrix}
$$

Here ${}^{M}\mathbf{e}_{x_B}$ is where the car's nose points,
${}^{M}\mathbf{e}_{y_B}$ is the standard body-left direction, and
${}^{M}\mathbf{e}_{z_L}$ is the right-positive local axis used by the
OpenOtter path generator. They are unit vectors, not actuator commands.

`PathReference` reports cross-track error as $e_{\mathrm{ct}}$. Positive
$e_{\mathrm{ct}}$ means the car is right of the path. Internally, `LQRTrack`
uses:

$$
e=-e_{\mathrm{ct}}
$$

That negative sign is deliberate. A car right of the path usually needs a left
steering correction, but OpenOtter's positive steering command means right.
The sign conversion makes the LQR feedback align with the actuator convention.

The heading error uses the car heading minus the path heading:

$$
\theta_e=\mathrm{wrapToPi}(\psi-\psi_{\mathrm{ref}})
$$

Here `wrapToPi` means "choose the equivalent angle between $-\pi$ and $+\pi$."
For example, $181^\circ$ becomes $-179^\circ$ because the shortest turn is
slightly right, not almost one full turn left.

With this definition, positive $\theta_e$ means the car body is yawed left of
the path tangent. At the center crossing of the default figure eight, the
first branch points forward/right, so a car starting at $\psi=0$ has positive
$\theta_e$ and needs a right steering correction.

## 4. Step 1: Project The Car Onto The Path

The red path is stored as waypoints. At a given tick, `PathReference` picks a
segment from waypoint $P_0$ to waypoint $P_1$. The car's current ground-plane
position is $p_M$.

![Path-reference geometry diagram](figures/path-reference-geometry.png)

The projection symbols are:

| Symbol | Meaning |
| --- | --- |
| $P_0$ | active segment start waypoint |
| $P_1$ | active segment end waypoint |
| $p_M$ | current car position in app-map coordinates |
| $\mathbf{s}$ | segment vector from $P_0$ to $P_1$ |
| $\alpha$ | clamped progress along the segment |
| $P_{\mathrm{ref}}$ | projected point on the path segment |
| $P$ | path frame at $P_{\mathrm{ref}}$ |
| ${}^{M}\mathbf{e}_{x_P}$ | path-tangent unit axis, expressed in app-map coordinates |
| ${}^{M}\mathbf{e}_{z_P}$ | path-right unit axis, expressed in app-map coordinates |

First define the segment vector:

$$
\mathbf{s}=P_1-P_0
$$

For 2D points, the dot product is:

$$
\mathbf{a}\cdot\mathbf{b}=a_xb_x+a_zb_z
$$

In plain terms, the dot product measures how much one vector points in the
same direction as another. `PathReference` uses it to find how far along the
segment the car's closest path point should be:

$$
\alpha =
\mathrm{clip}
\left(
\frac{(p_M-P_0)\cdot\mathbf{s}}{\mathbf{s}\cdot\mathbf{s}},
0,
1
\right)
$$

The `clip` keeps $\alpha$ on the segment:

- $\alpha=0$ means the closest point is $P_0$,
- $\alpha=1$ means the closest point is $P_1$,
- $\alpha=0.5$ means halfway between them.

The projected point is:

$$
P_{\mathrm{ref}}=P_0+\alpha\mathbf{s}
$$

This projected point is the controller's "nearest useful spot" on the red
path. The controller does not steer toward a random future waypoint; it steers
relative to the path tangent at this projected spot.

## 5. Step 2: Compute Path Heading, Side Error, And Curvature

The segment direction gives the path tangent heading:

$$
\psi_{\mathrm{ref}} =
\mathrm{atan2}
\left(
-(P_{1,z}-P_{0,z}),
P_{1,x}-P_{0,x}
\right)
$$

The negative sign on the $z$ difference comes from OpenOtter's yaw convention.
The result is the heading the car should have if it is perfectly aligned with
this piece of the path.

Concrete checks:

- if the segment points along $+x$, then $\psi_{\mathrm{ref}}=0$,
- if the segment points along $+z$ on the app map, then
  $\psi_{\mathrm{ref}}=-\pi/2$,
- if the segment points along $-z$ on the app map, then
  $\psi_{\mathrm{ref}}=+\pi/2$.

The path-right unit axis is:

$$
{}^{M}\mathbf{e}_{z_P} =
\begin{bmatrix}
\sin\psi_{\mathrm{ref}} \\
\cos\psi_{\mathrm{ref}}
\end{bmatrix}
$$

The signed cross-track error is:

$$
e_{\mathrm{ct}} =
(p_M-P_{\mathrm{ref}})\cdot{}^{M}\mathbf{e}_{z_P}
$$

This equation compares the car's offset from the path with the path's right
direction. Positive means the car is right of the path. Negative means it is
left of the path.

Curvature estimates how sharply the path is bending:

$$
\kappa \approx
\frac{\mathrm{wrapToPi}(\psi_{\mathrm{after}}-\psi_{\mathrm{before}})}
{s_{\mathrm{arc}}}
$$

Curvature is large in tight turns and near zero on straight parts. `LQRTrack`
uses curvature for feedforward steering: if the path is about to bend, start
turning before lateral error grows.

## 6. Step 3: Build The Five-Error State

The controller state is just a list of five numbers:

![LQR error-state diagram](figures/lqr-error-state.png)

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

The table below is the most important part of the controller. If these five
numbers are wrong, the LQR solve can be mathematically valid and still drive
badly.

| State value | Formula | Meaning |
| --- | --- | --- |
| $e$ | $-e_{\mathrm{ct}}$ | signed lateral error in LQR convention |
| $\dot{e}$ | $(e-e_{\mathrm{prev}})/\Delta t$ | lateral error rate |
| $\theta_e$ | $\mathrm{wrapToPi}(\psi-\psi_{\mathrm{ref}})$ | heading error |
| $\dot{\theta}_e$ | $\mathrm{wrapToPi}(\theta_e-\theta_{e,\mathrm{prev}})/\Delta t$ | heading error rate |
| $v_e$ | $v_{\mathrm{measured}}-v_{\mathrm{target}}$ | speed error |

The dots mean "rate of change." For example, $\dot{e}$ is positive when
lateral error is increasing and negative when the car is recovering toward the
path.

Derivative memory must be reset when the path index jumps far ahead during
reacquisition. Otherwise the controller subtracts an old error from a new
path segment and invents a fake large rate. That can produce an unnecessary
steering kick.

## 7. Step 4: Predict One Tick Ahead

LQR needs a simple prediction model. The model does not need to be perfect. It
only needs to express the main relationships:

- lateral position changes when lateral error has a rate,
- heading error creates sideways drift while the car is moving,
- steering changes heading rate,
- acceleration changes speed error.

In compact form:

$$
\mathbf{x}_{k+1}=A\mathbf{x}_k+B\mathbf{u}_k
$$

The input vector is:

$$
\mathbf{u} =
\begin{bmatrix}
u_s &
u_a
\end{bmatrix}^{\top}
$$

where $u_s$ is steering feedback and $u_a$ is acceleration feedback.

The OpenOtter model follows the PythonRobotics LQR speed/steer structure:

$$
A =
\begin{bmatrix}
1 & \Delta t & 0 & 0 & 0 \\
0 & 0 & v & 0 & 0 \\
0 & 0 & 1 & \Delta t & 0 \\
0 & 0 & 0 & 0 & 0 \\
0 & 0 & 0 & 0 & 1
\end{bmatrix}
$$

$$
B =
\begin{bmatrix}
0 & 0 \\
0 & 0 \\
0 & 0 \\
v/L & 0 \\
0 & \Delta t
\end{bmatrix}
$$

A few approximations make this model simple enough for real-time control:

$$
\sin\theta_e \approx \theta_e
$$

$$
\tan u_s \approx u_s
$$

Those are small-angle approximations. They say that for modest angles, the
angle itself is a good enough substitute for sine or tangent. That is why the
model can use multiplication instead of heavier trigonometry inside the LQR
solve. Large errors are still handled by feedback on the next tick and by
actuator clamps.

A matrix is only a table of multipliers. Reading the first row of $A$:

$$
e_{\mathrm{next}}=1\cdot e+\Delta t\cdot\dot{e}
$$

That says "new sideways error equals current sideways error plus rate times
time." This is the same idea as:

$$
\mathrm{new\ distance}=\mathrm{old\ distance}+\mathrm{speed}\cdot\mathrm{time}
$$

Reading the fourth row with $B$:

$$
\dot{\theta}_{e,\mathrm{next}}\approx\frac{v}{L}u_s
$$

That says steering changes heading rate more strongly when the car is moving
faster, and less strongly when the effective wheelbase $L$ is larger.

For OpenOtter, $L$ is a tuning length. It should start near the physical
wheelbase if known, but it is not trusted as a precise model because the car
does not report actual front wheel angle.

## 8. Step 5: Define The Score LQR Minimizes

The controller needs a way to decide whether one possible correction is better
than another. LQR uses a weighted score:

$$
J = \sum_{k=0}^{N}
\left(
\mathbf{x}_k^\top Q \mathbf{x}_k +
\mathbf{u}_k^\top R \mathbf{u}_k
\right)
$$

This looks abstract, but with diagonal weights it is just weighted squared
errors. For one tick:

$$
\mathbf{x}^{\top}Q\mathbf{x}
=
q_e e^2
+q_{\dot{e}}\dot{e}^2
+q_{\theta}\theta_e^2
+q_{\dot{\theta}}\dot{\theta}_e^2
+q_v v_e^2
$$

The command effort term is:

$$
\mathbf{u}^{\top}R\mathbf{u}
=
r_s u_s^2+r_a u_a^2
$$

Squaring has two useful effects:

- positive and negative errors both cost something,
- big errors cost much more than small errors.

The weights decide personality:

- large $q_e$ means "do not drift sideways from the path,"
- large $q_{\theta}$ means "align heading with the path tangent,"
- large $q_v$ means "keep speed close to target,"
- large $r_s$ means "avoid aggressive steering,"
- large $r_a$ means "avoid aggressive speed changes."

This is the main tuning language for LQR.

## 9. Step 6: Solve For The Gain Matrix

After the model and score are defined, LQR computes a gain matrix $K$. At
runtime, the controller uses:

$$
\mathbf{u}=-K\mathbf{x}
$$

This means "multiply the current errors by $K$, then command the opposite
correction." If the errors are zero, the feedback correction is zero. If the
errors grow, the correction grows in a way chosen by the model and the score.

The Swift implementation solves the discrete algebraic Riccati equation. You
do not need to tune this equation directly, but it is useful to know what it
does. It computes a matrix $P$ that represents the future cost of being in a
state. The iteration is:

$$
P_{i+1}
= A^\top P_i A
- A^\top P_i B
\left(R+B^\top P_i B\right)^{-1}
B^\top P_i A
+ Q
$$

Then the gain is:

$$
K =
\left(R+B^\top P B\right)^{-1}
B^\top P A
$$

Engineering interpretation:

- $Q$ says how bad current errors are,
- the model says how current commands affect future errors,
- $P$ summarizes the future cost,
- $K$ becomes the shortcut from current error to best feedback command.

If the solve produces `NaN`, infinity, or a singular matrix, the planner should
output neutral for that tick and log the failure. Sending stale LQR output is
worse than skipping one tick.

## 10. Step 7: Convert Feedback To Steering And Throttle

The LQR feedback is not sent directly to firmware. It is combined with
feedforward and actuator mapping.

First compute feedback:

$$
\mathbf{f}=K\mathbf{x}
$$

The conventional LQR command is:

$$
\mathbf{u}=-\mathbf{f}
$$

For steering, OpenOtter uses the converted sign that matches the normalized
steering command:

$$
s_{\mathrm{fb}}=k_s f_0
$$

Curvature feedforward is:

$$
s_{\mathrm{ff}}=-k_{\kappa}\kappa
$$

The final steering command is:

$$
s =
\mathrm{clip}
\left(
s_{\mathrm{ff}}+s_{\mathrm{fb}},
-1,
1
\right)
$$

For throttle, the second LQR command is treated as an acceleration-like trim:

$$
\tau =
\mathrm{clip}
\left(
\tau_{\mathrm{base}}+k_{\tau}u_1,
0,
\tau_{\max}
\right)
$$

This mapping is intentionally conservative. OpenOtter commands normalized
throttle, not physical acceleration, so $k_{\tau}$ starts small and must be
tuned from logs.

## 11. Target Speed And Base Throttle

Start with a stable target speed:

$$
v_{\mathrm{target}}=0.20\ \mathrm{m/s}
$$

The base throttle maps target speed into a reasonable command before LQR trim:

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

Later, speed can slow down on high curvature:

$$
\ell_{\kappa} =
\mathrm{clip}
\left(
\frac{|\kappa|}{\kappa_{\mathrm{slow}}},
0,
1
\right)
$$

$$
v_{\mathrm{target}}
=v_{\max}-(v_{\max}-v_{\min})\ell_{\kappa}
$$

Do not start with aggressive curvature speed scheduling. First prove that
`LQRTrack` can follow the same $3.2\ \mathrm{m}$ by $1.6\ \mathrm{m}$ figure
eight at one stable target speed.

## 12. Full Planner Pseudocode

The pseudocode below shows the whole loop in the same order as the explanation
above.

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
    steeringFB = steeringScale * feedback[0]
    steering = clamp(steeringFF + steeringFB, -1, 1)

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

## 13. Initial Values

The initial values are intentionally conservative. They are not final truth;
they are a safe starting point for simulation and low-risk field tests.

| Parameter | Initial value | Why |
| --- | --- | --- |
| $\Delta t$ clamp | $0.02 \ldots 0.25\ \mathrm{s}$ | avoids divide-by-zero and huge stale steps |
| $L$ | $0.35\ \mathrm{m}$ | effective wheelbase/tuning length |
| $v_{\mathrm{target}}$ | $0.20\ \mathrm{m/s}$ | faster than crawling, still controlled |
| $\tau_{\max}$ | Telegram speed, default $0.4$ | keeps operator speed intent explicit |
| $k_s$ | $1.0$ | direct steering feedback scale |
| $k_{\tau}$ | $0.15$ | small throttle trim until acceleration is calibrated |
| $k_{\kappa}$ | $0.10\ \mathrm{m}$ | same starting feedforward scale as TangentTrack |

Initial weights:

$$
Q = \mathrm{diag}(3.0,\ 0.2,\ 2.5,\ 0.2,\ 0.8)
$$

$$
R = \mathrm{diag}(1.0,\ 2.0)
$$

Expanded, the state cost is:

$$
3.0e^2
+0.2\dot{e}^2
+2.5\theta_e^2
+0.2\dot{\theta}_e^2
+0.8v_e^2
$$

The intent is: prioritize lateral and heading error, care moderately about
speed, and keep rate terms present but not dominant.

## 14. How To Tune From Symptoms

Tuning should start in `tools/trajectory-sim`, then move to slow basement
tests. Change one idea at a time. If two knobs move together, it becomes hard
to know which one helped.

| Field symptom | Likely meaning | First change |
| --- | --- | --- |
| blue path is consistently outside lobes | lateral error is too cheap | increase $q_e$ |
| car points across the path instead of along it | heading error is too cheap | increase $q_{\theta}$ |
| steering is too busy or ticks | steering effort is too cheap | increase $r_s$ or reduce $k_s$ |
| car follows path but crawls | speed error is too cheap | increase $v_{\mathrm{target}}$ or $q_v$ |
| throttle surges | throttle effort is too cheap | increase $r_a$ or reduce $k_{\tau}$ |
| first seconds after path reacquisition are violent | stale derivatives are leaking in | reset previous $e$ and $\theta_e$ on large index jumps |
| controller drives the wrong way across the center | sign convention is wrong | inspect $e_{\mathrm{ct}}$, $e$, $\theta_e$, and final steering sign |

The most useful debug values per tick are:

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

For comparing `TangentTrack` and `LQRTrack`, look at metrics instead of one
screenshot:

- maximum envelope overshoot,
- 95th-percentile cross-track error,
- average speed,
- steering saturation time,
- number of neutral outputs caused by invalid LQR solves.

## 15. Practical Limitations

`LQRTrack` is useful, but it is not magic. The first implementation has three
known limits.

First, the model does not know the front wheel angle. It commands steering and
watches ARKit pose feedback. If the steering linkage binds or servo response
lags, the model will be optimistic.

Second, throttle is not calibrated acceleration. A throttle command that gives
$0.20\ \mathrm{m/s}$ on one floor may give a different speed on carpet or
concrete. That is why speed feedback and logs matter.

Third, ARKit pose is the main feedback signal. If yaw jumps or drifts, the
controller will react to that measurement. The safety supervisor and firmware
watchdogs remain mandatory layers, not optional backup.

The reason to keep `LQRTrack` behind `/figure8_lqr` is exactly this: it gives
us a clean experimental controller without risking the already-useful
`TangentTrack` baseline.
