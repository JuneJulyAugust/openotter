# metalbot Plan (Invariant v0)

This plan is high-level and stable for now. We refine internals only after implementation evidence.

## 1. Identity and Scope

### 1.1 Project identity

#### 1.1.1 Name and meaning

- Project name: `metalbot`.
- Name source: Apple Metal API focus for high-performance on-device perception and compute.

### 1.2 Target platform

#### 1.2.1 Hardware baseline

- iPhone 13 Pro / iPhone 13 Pro Max.
- RC chassis with steering/throttle actuation.
- Raspberry Pi 4B + Arduino MCP for high-level communication and low-level command execution.

### 1.3 Environment assumptions

#### 1.3.1 MVP1 operating conditions

- Indoor flat floor only.
- Obstacle classes for MVP1 include both large and small/near-field obstacles.
- Fixed phone mount planned via 3D-printed bracket.

## 2. Product Milestones

### 2.1 MVP1 (primary): LiDAR-only closed loop

#### 2.1.1 Functional objective

- Drive straight, track target speed, and stop for obstacle.

#### 2.1.2 Scope

- LiDAR raw point-cloud pipeline (from ARKit `sceneDepth` back-projection).
- 6D Pose estimation (ARKit World Tracking).
- Velocity estimation (ESC telemetry via Bluetooth on Raspberry Pi).
- Speed planner and control.
- Planner-triggered stop on blocked future path.
- iPhone to Raspberry Pi command path.
- Configurable obstacle-stop policy.

### 2.2 MVP2 (parallel): RGB to mono-depth prototype

#### 2.2.1 Objective

- Build camera-to-depth inference path on iPhone Neural Engine.

### 2.3 MVP3 (future): sparse LiDAR + RGB depth completion

#### 2.3.1 Objective

- Fuse sparse LiDAR and RGB depth priors.
- Candidate research direction includes MetricAnything-style depth completion.

## 3. MVP1 System Architecture

### 3.1 Perception component

#### 3.1.1 LiDAR point-cloud processing

- Capture `sceneDepth` depth/confidence maps and back-project to 3D point cloud.
- Maintain orientation-correct camera/world transforms for stable geometry using ARKit pose.
- Provide obstacle points to the planner.
- Keep RGB + point-cloud debug visualization for perception validation.

### 3.2 Estimation component

#### 3.2.1 MVP1 Pose and Velocity

- **Pose**: 6D Pose (position + orientation) sourced from ARKit `worldTracking`. This provides stable localization relative to the start point.
- **World Map Persistence**: ARKit `ARWorldMap` save/load logic provides drift-corrected relocalization for recurring runs.
- **Velocity**: Real-time speed sourced from the Electronic Speed Controller (ESC) via Bluetooth connection on the Raspberry Pi. This telemetry is forwarded to the iPhone Brain.

### 3.3 Planner and control component

#### 3.3.1 Speed planning and control baseline

- Speed planner: reach target speed, then keep it.
- Planner checks whether obstacle points block the future path from the speed planner.
- Planner emits stop signal when the future path is blocked.
- Controller tracks planner speed command using ESC telemetry as feedback.
- Heading hold using ARKit orientation.
- Initial command loop baseline: `10 Hz` (subject to testing).
- Initial speed envelope: `0.1` to `2.0` m/s (configurable).

### 3.4 Safety component

#### 3.4.1 Safety policy baseline

- Planner stop threshold is configurable.
- Planner stop signal has higher priority than normal speed command.
- `estop` always overrides normal drive commands.

### 3.5 Actuation and transport component

#### 3.5.1 MCP interface strategy

- Command protocol: UDP-based, bi-directional heartbeats (1.0 Hz) and asynchronous control commands.
- Transport: Wi-Fi (UDP) is the primary transport for initial testing; BLE remains a prototype candidate.
- Raspberry Pi 4B: Acts as the high-level bridge ("MCP High-Level"), running a modular event-driven C++ application (Asio) with a TUI dashboard (FTXUI).
- Architectural Integrity: Pure logic (protocol/status) decoupled from transport (UDP/Serial) and UI.
- ESC Telemetry: iPhone maintains a direct Bluetooth LE connection to the ESC to pull real-time RPM/speed and temperature data.
- Arduino: Handles low-level PWM/servo control ("MCP Low-Level") via Serial bridge from the Pi.
- Safety: 1.5-second connection timeout enforced on both iPhone (Brain) and Raspberry Pi (MCP).
- Diagnostics: Real-time dashboard on Pi and dedicated "MCP Diagnostics" view on iOS.
- **ARKit Feasibility**: Dedicated iOS view for 6D pose stability, trajectory tracking, and world map management.

#### 3.5.2 Transport and watchdog matrix

| Layer | Path | Current behavior | Status |
| --- | --- | --- | --- |
| iPhone <-> Pi | Wi-Fi UDP heartbeats and commands | 1.5-second connection timeout on both sides; refactored for testability | Implemented |
| Pi <-> Arduino | USB serial forwarding | Auto-reconnect, 3.5-second boot sync, ACK logging; firmware timeout currently logs without neutralization in debug mode | Implemented |
| Drive arbitration | planner / estop | Planner stop should override normal speed; estop remains top priority | Planned |

## 4. Engineering Invariants

### 4.1 Cross-component invariants

#### 4.1.1 Rules

- Every sensor sample and command carries a monotonic timestamp.
- Safety constraints dominate performance targets.
- Core algorithms remain physics-based and deterministic, not ad-hoc heuristics.
- Camera/pixel/world coordinate transforms are explicit and validated.
- Interfaces are testable, versioned, and bounded.
- MVP boundaries are strict to avoid scope drift.
