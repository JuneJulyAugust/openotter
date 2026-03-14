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
- STM32 MCP for low-level command execution.

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
- Velocity estimation (iPhone IMU first).
- Speed planner and control.
- Planner-triggered stop on blocked future path.
- iPhone to STM32 command path.
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
- Maintain orientation-correct camera/world transforms for stable geometry.
- Provide obstacle points to the planner.
- Keep RGB + point-cloud debug visualization for perception validation.

### 3.2 Estimation component

#### 3.2.1 MVP1 velocity and orientation

- iPhone IMU (gyro + accelerometer) is the only velocity source for MVP1.
- Heading reference: gyro yaw-rate hold for straight driving; magnetometer available as coarse orientation context.

### 3.3 Planner and control component

#### 3.3.1 Speed planning and control baseline

- Speed planner: reach target speed, then keep it.
- Planner checks whether obstacle points block the future path from the speed planner.
- Planner emits stop signal when the future path is blocked.
- Controller tracks planner speed command.
- Heading hold for straight driving.
- Initial command loop baseline: `10 Hz` (subject to testing).
- Initial speed envelope: `0.1` to `2.0` m/s (configurable).

### 3.4 Safety component

#### 3.4.1 Safety policy baseline

- Planner stop threshold is configurable.
- Planner stop signal has higher priority than normal speed command.
- `estop` always overrides normal drive commands.

### 3.5 Actuation and transport component

#### 3.5.1 MCP interface strategy

- Command protocol includes bounded actuator values, sequence, and timestamp.
- Transport decision is pending: BLE vs Wi-Fi; both will be prototyped.
- STM32 PWM control is in-progress and external collaboration is ongoing.

## 4. Engineering Invariants

### 4.1 Cross-component invariants

#### 4.1.1 Rules

- Every sensor sample and command carries a monotonic timestamp.
- Safety constraints dominate performance targets.
- Core algorithms remain physics-based and deterministic, not ad-hoc heuristics.
- Camera/pixel/world coordinate transforms are explicit and validated.
- Interfaces are testable, versioned, and bounded.
- MVP boundaries are strict to avoid scope drift.
