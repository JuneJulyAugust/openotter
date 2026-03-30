# Safety Supervisor — Design v0.1

**Status:** Design (pre-implementation)
**Date:** 2026-03-29

---

## 1. Purpose

The `SafetySupervisor` sits between the planner output and the actuators. If the forward path is blocked, it overrides the planner command with a brake. The planner and UI are notified.

---

## 2. Time-to-Collision (TTC)

Sample **one depth value** from the LiDAR depth map: the pixel closest to the camera's optical center (y=0, z=0 in camera frame — i.e., the center pixel of the depth image). This is the depth directly ahead.

```
d_forward = depthMap[cy, cx]     // center pixel, meters
v_eff     = |throttle| * MAX_SPEED_PROXY_MPS
TTC       = d_forward / max(v_eff, ε)
```

| Parameter | Default | Meaning |
|---|---|---|
| `MAX_SPEED_PROXY_MPS` | `1.0` | Estimated top speed at throttle=1.0 (placeholder until calibration) |
| `TTC_CRITICAL_S` | `1.0` | Below this → brake unconditionally |
| `ε` | `0.01` | Avoid division by zero at standstill |

---

## 3. Decision Logic

```
supervise(command, context):
  if depthMap is nil:       return command   // no sensor → pass through
  if command.throttle <= 0: return command   // not moving forward → pass through

  d_forward = centerDepth(depthMap)
  if d_forward is NaN or 0: return command   // invalid reading

  v_eff = command.throttle * MAX_SPEED_PROXY_MPS
  ttc   = d_forward / max(v_eff, ε)

  if ttc < TTC_CRITICAL_S:
      return .brake(reason: "TTC \(ttc)s, d=\(d_forward)m")

  return command
```

One threshold, one action: brake or pass through.

---

## 4. `SafetySupervisorEvent`

```swift
struct SafetySupervisorEvent {
    let timestamp: TimeInterval
    let ttc: Float
    let forwardDepth: Float
    let action: Action

    enum Action {
        case clear
        case brakeApplied(String)
    }
}
```

---

## 5. Extensibility

This is the simplest viable supervisor. Future versions can:
- Sample a forward cone instead of one pixel
- Add a warning threshold with throttle capping
- Use true velocity (m/s) once wheel radius is calibrated
- Incorporate lateral obstacles for steering constraints

Each extension modifies `SafetySupervisor` internals only. The `supervise(command, context) → ControlCommand` interface does not change.
