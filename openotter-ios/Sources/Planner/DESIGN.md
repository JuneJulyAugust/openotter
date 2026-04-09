# Planner Framework — Design v0.1

**Status:** Design (pre-implementation)
**Date:** 2026-03-29

---

## 1. Problem Statement

The 10 Hz control loop in `SelfDrivingViewModel` has a planner stub returning `(0.0, 0.0)`. We need:

1. A **planner protocol** that is extensible (waypoint follower now, A\*, RRT, iLQR later).
2. A **safety supervisor** that can override any planner command when collision is imminent.
3. An **orchestrator** that wires planner + supervisor and is the only thing `SelfDrivingViewModel` calls.

---

## 2. Scope (v0.1)

- **Localization:** ARKit 6D pose (`PoseEntry`) only.
- **Speed unit:** Normalized throttle `[-1, +1]`. No m/s conversion yet (wheel radius uncalibrated).
- **Safety input:** Single center-pixel depth from LiDAR depth map.
- **First planner:** Straight-line waypoint follower with proportional heading control.

---

## 3. Architecture

```
SelfDrivingViewModel (10 Hz)
        │  tick(context:) → ControlCommand
        ▼
PlannerOrchestrator
  ├── activePlanner: PlannerProtocol  →  plan(context:)  →  ControlCommand
  └── supervisor: SafetySupervisor    →  supervise(cmd, context) → ControlCommand (safe or brake)
        │
        ▼
STM32BleManager (PWM)
```

---

## 4. Core Types

### `PlannerContext` — immutable sensor snapshot per tick

```swift
struct PlannerContext {
    let pose: PoseEntry
    let currentThrottle: Float       // last commanded [-1, +1]
    let escTelemetry: ESCTelemetry?
    let depthMap: CVPixelBuffer?     // nil if unavailable
    let depthMapWidth: Int
    let depthMapHeight: Int
    let timestamp: TimeInterval
}
```

### `ControlCommand` — output with provenance

```swift
struct ControlCommand {
    let steering: Float      // [-1, +1]
    let throttle: Float      // [-1, +1]
    let source: CommandSource

    enum CommandSource {
        case planner(String)     // planner name
        case safetySupervisor
        case idle
    }

    static let neutral = ControlCommand(steering: 0, throttle: 0, source: .idle)

    static func brake(reason: String) -> ControlCommand {
        ControlCommand(steering: 0, throttle: 0, source: .safetySupervisor)
    }
}
```

### `PlannerProtocol` — extensibility contract

```swift
protocol PlannerProtocol: AnyObject {
    var name: String { get }
    func setGoal(_ goal: PlannerGoal)
    func plan(context: PlannerContext) -> ControlCommand
    func reset()
}
```

Adding a new planner = one new file implementing this protocol. Nothing else changes.

### `PlannerGoal` / `Waypoint`

```swift
enum PlannerGoal {
    case idle
    case followWaypoints([Waypoint], maxThrottle: Float)
}

struct Waypoint {
    let x: Float              // ARKit world frame
    let z: Float              // ARKit world frame (XZ = ground plane)
    let acceptanceRadius: Float  // meters, default 0.2
}
```

---

## 5. `WaypointPlanner`

Proportional heading controller with waypoint sequencing.

```
plan(context):
  if no waypoints or all reached: return .neutral

  target = waypoints[currentIndex]
  d = distance2D(pose, target)
  if d < acceptanceRadius: advance index

  desiredYaw = atan2(target.x - pose.x, target.z - pose.z)
  yawError   = wrapToPi(desiredYaw - pose.yaw)

  steering = clamp(K_STEERING * yawError, -1, +1)
  throttle = maxThrottle * (1 - |yawError| / π)

  return ControlCommand(steering, throttle, .planner("WaypointPlanner"))
```

| Parameter | Default | Meaning |
|---|---|---|
| `K_STEERING` | `0.6 / (π/2)` | Full steering at 90° error |
| Throttle fade | `1 - |yawError|/π` | Slow down in turns |
| `acceptanceRadius` | `0.2 m` | Waypoint reached threshold |

---

## 6. Safety Supervisor

Separate design document: [`Safety/DESIGN.md`](Safety/DESIGN.md)

Summary: sample center-pixel depth, compute `TTC = d / (|throttle| * MAX_SPEED_PROXY)`. If `TTC < 1.0s` → brake. One threshold, one action.

---

## 7. File Layout

```
Sources/Planner/
├── DESIGN.md                         ← this file
├── PlannerProtocol.swift             ← protocol, PlannerGoal, Waypoint
├── PlannerContext.swift              ← sensor snapshot
├── ControlCommand.swift              ← command + source
├── PlannerOrchestrator.swift         ← wires planner + supervisor
├── Safety/
│   ├── DESIGN.md                     ← safety design
│   ├── SafetySupervisor.swift        ← supervise() logic
│   └── SafetySupervisorEvent.swift   ← event type
└── Planners/
    └── WaypointPlanner.swift         ← first planner
```

---

## 8. Open TODOs

| ID | Item |
|---|---|
| P-01 | Measure wheel radius → enable m/s velocity |
| P-02 | Calibrate `MAX_SPEED_PROXY_MPS` (run at known throttle, measure distance/time) |
| P-03 | Wire raw `CVPixelBuffer` from `LiDARCaptureSession` to `PlannerContext` |
| P-04 | UI for setting waypoints (tap on 2D map) |
| P-05 | Tune `TTC_CRITICAL_S` and `K_STEERING` in field testing |
