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
  ├── operatingMode: OperatingMode    →  setOperatingMode(.drive|.park) ─┐
  ├── activePlanner: PlannerProtocol  →  plan(context:)  →  ControlCommand
  └── supervisor: SafetySupervisor    →  supervise(cmd, context) → ControlCommand
        │                                                                 │
        ▼                                                                 ▼
STM32BleManager (FE41 PWM commands)             STM32BleManager (FE44 mode byte)
```

The orchestrator is the single iOS-side source of truth for the operating
mode. `STM32BleManager` is registered as the optional
`OperatingModeReceiving` and is pushed synchronously on every transition,
which translates into a write to the firmware mode characteristic.

---

## 3.1 Operating Mode

`OperatingMode` is a binary, mutually-exclusive operator commitment:

| Mode    | Planner             | Forward supervisor | Firmware (FE44)        | Firmware reverse supervisor | Firmware throttle output |
|---------|---------------------|--------------------|------------------------|------------------------------|--------------------------|
| `drive` | active, may emit motion | armed; may publish BRAKE on close obstacle | `0x00 = DRIVE`         | armed; may publish BRAKE on FE43 | passes commanded throttle, clamped on BRAKE |
| `park`  | inactive (`reset`)  | passes through; cannot enter BRAKE because planner emits neutral | `0x02 = PARK`          | held disarmed; no FE43 events | hard-neutral regardless of FE41 payload |

Transitions are driven exclusively by the orchestrator:

- `setGoal(_:)` → `.drive`. Always re-pushes Drive through the receiver
  (idempotent), so a stale firmware Park left over from another client is
  cleared on the first goal-set.
- `reset()` → `.park`. Drops the planner goal, drops any supervisor latch,
  pushes Park through the receiver, and clears the cached firmware safety
  event in the BLE bridge so the UI overlay/alarm collapse without waiting
  for the firmware's SAFE snapshot to round-trip.

Park is a stable terminal state by construction:

- iOS forward supervisor cannot enter BRAKE because it only inspects the
  planner command and the planner emits neutral throttle.
- Firmware reverse supervisor is held SAFE (not ticked) so it cannot fire
  BRAKE on residual reverse coast.

The only way out of Park is an explicit `setGoal` (operator intent to
drive). `STM32ControlViewModel.init` writes `.drive` unconditionally so
manual control re-arms the firmware regardless of the prior session.

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
├── OperatingMode.swift               ← Park/Drive enum + receiving protocol
├── PlannerOrchestrator.swift         ← wires planner + supervisor + mode
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
