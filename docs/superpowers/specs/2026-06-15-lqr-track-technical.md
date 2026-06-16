# LQRTrack Technical Note

**Status:** Technical note for initial `LQRTrack` implementation
**Date:** 2026-06-15
**Companion design:** `docs/superpowers/specs/2026-06-15-lqr-track-design.md`

## 1. Plain-English Idea

`TangentTrack` controls steering with a PID-like heading loop and shapes
throttle with practical rules. `LQRTrack` controls steering and speed from one
shared math problem.

The controller keeps a short list of errors: lateral position, lateral error
rate, heading error, heading error rate, and speed error.

LQR chooses steering and speed corrections that make those errors small while
also avoiding excessive actuator effort. In high-school-math terms: it tries
to minimize a weighted score where large errors and large commands cost more.

## 2. Cost Function

The score LQR minimizes is:

$$
J = \sum_{k=0}^{N}
\left(
\mathbf{x}_k^\top Q \mathbf{x}_k +
\mathbf{u}_k^\top R \mathbf{u}_k
\right)
$$

Read it as:

- `x` is the error list.
- `u` is the command correction list.
- `Q` says which errors are most important.
- `R` says how much we dislike strong steering or throttle changes.

If lateral error matters more, raise its `Q`. If steering is too aggressive,
raise steering `R`. The result is a gain matrix `K`:

$$
\mathbf{u} = -K\mathbf{x}
$$

This means the controller multiplies the current errors by a precomputed gain
and sends the opposite correction.

## 3. State Vector

Use this state:

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

Definitions:

| Term | Definition |
| --- | --- |
| $e$ | LQR lateral state, metres |
| $\dot{e}$ | $(e - e_{\mathrm{prev}}) / \Delta t$ |
| $\theta_e$ | $\operatorname{wrapToPi}(\psi - \psi_{\mathrm{ref}})$ |
| $\dot{\theta}_e$ | $\operatorname{wrapToPi}(\theta_e - \theta_{e,\mathrm{prev}}) / \Delta t$ |
| $v_e$ | $v_{\mathrm{measured}} - v_{\mathrm{target}}$ |

OpenOtter sign convention:

- $e_{\mathrm{ct}} > 0$ means the car is right of the path.
- The LQR state uses $e = -e_{\mathrm{ct}}$.
- Positive normalized steering means steer right.
- $\theta_e > 0$ means the car yaw is left of the path tangent.

That sign conversion is deliberate. A car right of the path should usually
steer left, while a positive heading error at the center crossing should steer
right to align with the first forward/right branch. The sign tests verify this
directly, because sign mistakes are easy and field-visible.

## 4. Path Reference

For each control tick, let $P_0$ and $P_1$ be the active path segment endpoints,
$p$ be the car position, and $\mathbf{s}=P_1-P_0$. The projected reference
point is:

$$
\alpha =
\operatorname{clip}
\left(
\frac{(p-P_0)\cdot\mathbf{s}}{\mathbf{s}\cdot\mathbf{s}},
0,
1
\right)
$$

$$
P_{\mathrm{ref}} = P_0 + \alpha \mathbf{s}
$$

The reference yaw and path-right unit vector are:

$$
\psi_{\mathrm{ref}} =
\operatorname{atan2}\left(-(P_{1,z}-P_{0,z}),\, P_{1,x}-P_{0,x}\right)
$$

$$
\mathbf{r}_{\mathrm{path}} =
\begin{bmatrix}
\sin(\psi_{\mathrm{ref}}) &
\cos(\psi_{\mathrm{ref}})
\end{bmatrix}^{\top}
$$

Then the signed cross-track error and LQR lateral state are:

$$
e_{\mathrm{ct}} = (p-P_{\mathrm{ref}})\cdot\mathbf{r}_{\mathrm{path}},
\qquad
e = -e_{\mathrm{ct}}
$$

Curvature is estimated from nearby heading change over arc length:

$$
\kappa \approx
\frac{\operatorname{wrapToPi}(\psi_{\mathrm{after}}-\psi_{\mathrm{before}})}
{s_{\mathrm{arc}}}
$$

This uses the same app-map convention as `TangentTrack`:

| Quantity | Convention |
| --- | --- |
| screen up | $+x$ forward |
| screen right | $+z$ right |
| figure-eight length | $3.2\ \mathrm{m}$ along $+Z/-Z$ |
| figure-eight width | $1.6\ \mathrm{m}$ along $+X/-X$ |

## 5. Linear Model

LQR needs a simple prediction model:

$$
\mathbf{x}_{k+1} = A\mathbf{x}_k + B\mathbf{u}_k
$$

The initial model follows the PythonRobotics LQR speed/steer structure:

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

where $\Delta t$ is the control time step, $v$ is measured speed, $L$ is the
effective wheelbase/tuning length, $u_0$ is steering feedback, and $u_1$ is
acceleration feedback.

This is a simplified model. It does not know the actual front wheel angle. The
controller corrects using ARKit pose feedback, so the model only needs to be
good enough to choose useful corrections.

## 6. Solving For K

At each tick, or for each speed bucket, solve the discrete algebraic Riccati
equation:

$$
P_{i+1}
= A^\top P_i A
- A^\top P_i B
\left(R + B^\top P_i B\right)^{-1}
B^\top P_i A
+ Q
$$

Iterate until `P_next` changes very little or a fixed iteration cap is reached.
Then compute:

$$
K =
\left(R + B^\top P B\right)^{-1}
B^\top P A
$$

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

$$
s_{\mathrm{ff}} = -k_{\kappa}\kappa
$$

Then add LQR feedback. The discrete LQR solve returns $K$, and the conventional
control law is $\mathbf{u}=-K\mathbf{x}$. Because OpenOtter steering command
sign is opposite the bicycle steering angle sign used in the model, the
normalized steering command uses the converted feedback sign:

$$
\mathbf{f} = K\mathbf{x},
\qquad
s_{\mathrm{fb}} = k_s f_0
$$

$$
s =
\operatorname{clip}
\left(
s_{\mathrm{ff}} + s_{\mathrm{fb}},
-1,
1
\right)
$$

Speed control uses the acceleration output as a throttle trim:

$$
\mathbf{u} = -\mathbf{f}
$$

$$
\tau =
\operatorname{clip}
\left(
\tau_{\mathrm{base}} + k_{\tau}u_1,
0,
\tau_{\max}
\right)
$$

OpenOtter does not command acceleration directly, so `throttleAccelScale` is a
tuning constant. Start small and tune from logs.

## 8. Target Speed

Start with a simple speed profile:

$$
v_{\mathrm{target}} = 0.20\ \mathrm{m/s}
$$

Later, the speed profile can slow slightly at high curvature:

$$
\ell_{\kappa} =
\operatorname{clip}
\left(
\frac{|\kappa|}{\kappa_{\mathrm{slow}}},
0,
1
\right)
$$

$$
v_{\mathrm{target}}
= v_{\max} - (v_{\max}-v_{\min})\ell_{\kappa}
$$

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

| Parameter | Initial value |
| --- | --- |
| $\Delta t$ clamp | $0.02 \ldots 0.25\ \mathrm{s}$ |
| $L$ | $0.35\ \mathrm{m}$ |
| $v_{\mathrm{target}}$ | $0.20\ \mathrm{m/s}$ |
| $\tau_{\max}$ | Telegram speed, default $0.4$ |
| $k_s$ | $1.0$ |
| $k_{\tau}$ | $0.15$ |
| $k_{\kappa}$ | $0.10\ \mathrm{m}$ |

$$
Q = \operatorname{diag}(3.0,\ 0.2,\ 2.5,\ 0.2,\ 0.8),
\qquad
R = \operatorname{diag}(1.0,\ 2.0)
$$

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
