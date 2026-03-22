# metalbot Task Backlog

This backlog is hierarchical and execution-focused. Complete MVP1 before expanding scope.

## 1. MVP1 - LiDAR-only drive straight + obstacle stop (active)

### 1.1 Foundation and app bring-up

#### 1.1.1 Project and runtime setup

- [x] Create initial iOS app target (`metalbot`) and baseline module layout.
- [x] Add runtime support checks for LiDAR-capable devices and fallback error states.
- [x] Add app permissions/configuration required for capture and motion pipelines.

#### 1.1.2 LiDAR point-cloud data contract

- [x] Implement LiDAR `sceneDepth` stream with on-screen diagnostics.
- [x] Define `PointCloud` and `CaptureFrame` contracts with timestamp, points, camera transform, and RGB image.
- [x] Implement orientation-correct point cloud projection (camera-pov aligned view matrix).
- [x] Add RGB + point-cloud split-screen debug view (portrait top/bottom, landscape left/right).

### 1.2 Estimation component

#### 1.2.1 IMU-first state estimation

- [ ] Define `VehicleState` model (`speed_mps`, `yaw_rate_rps`, `timestamp`).
- [ ] Implement Core Motion pipeline (gyro + accel, optional magnetometer context).
- [ ] Implement baseline velocity estimator.

### 1.3 Planner and control component

#### 1.3.1 Speed planner and control

- [ ] Define planner output contract (`target_speed_mps`, `stop_requested`, `timestamp`).
- [ ] Implement speed planner: reach target speed, then keep it.
- [ ] Implement controller to track planner speed command (baseline loop: `10 Hz`).
- [ ] Keep target speed configurable (initial range: `0.1` to `2.0` m/s).
- [ ] Implement straight-drive heading hold using iPhone yaw-rate feedback (magnetometer as optional coarse reference).

#### 1.3.2 Obstacle blocking and stop signal

- [ ] Add obstacle-point input from LiDAR to planner.
- [ ] Implement blocked-future-path check in planner.
- [ ] Emit planner stop signal when future path is blocked.
- [ ] Make planner stop threshold configurable.
- [ ] Ensure planner stop signal has higher priority than normal speed command.
- [ ] Ensure `estop` command path has strict priority over all drive commands.

### 1.4 Raspberry Pi + Arduino MCP interface

#### 1.4.1 Protocol and transport implementation

- [x] Define protocol v1 fields (`hb_iphone`, `hb_pi`, `cmd:s=x,m=y`).
- [x] Implement Wi-Fi (UDP) adapter on Raspberry Pi 4B with bi-directional heartbeat.
- [x] Implement TUI dashboard on Pi (FTXUI) with stationary bi-directional meters.
- [x] Implement USB serial bridge between Raspberry Pi and Arduino.
- [x] Implement Arduino firmware for PWM/servo command execution.

#### 1.4.2 MCP integration contract

- [x] Implement iPhone heartbeat (1Hz) and 1.5s timeout logic.
- [x] Implement Raspberry Pi heartbeat (1Hz) and 1.5s timeout logic.
- [x] Implement "MCP Diagnostics" view on iOS for real-time monitoring.
- [ ] Define the Pi<->Arduino watchdog semantics and decide whether timeout should neutralize outputs or only log during debugging.

### 1.5 Validation and exit criteria

#### 1.5.1 MVP1 acceptance checks

- [ ] Hold target speed on flat indoor floor for repeatable runs.
- [ ] Maintain straight driving within defined drift tolerance.
- [ ] Stop before obstacle under configurable stop policy.
- [ ] Trigger safe stop on stale LiDAR data or control-link timeout.

## 2. MVP2 - RGB to mono depth prototype (parallel, limited scope)

### 2.1 Perception prototype

#### 2.1.1 Camera-to-depth path

- [ ] Build camera stream ingestion path independent from MVP1 driving stack.
- [ ] Integrate one mono-depth Core ML model on iPhone Neural Engine.
- [ ] Measure latency, thermal behavior, and indoor depth quality.

## 3. MVP3 - Sparse LiDAR + RGB completion (future)

### 3.1 Fusion research track

#### 3.1.1 Feasibility tasks

- [ ] Define LiDAR/RGB calibration and fusion data contracts.
- [ ] Evaluate depth-completion model candidates for iPhone feasibility.
- [ ] Benchmark fused depth against LiDAR-only baseline.

## 4. Decision backlog

### 4.1 Pending product/engineering decisions

#### 4.1.1 Open items

- [ ] Decide whether BLE remains worth keeping as a prototype transport after Wi-Fi UDP is validated on vehicle.
- [ ] Finalize stop-policy defaults after initial braking tests.
- [ ] Finalize controller loop rate after latency and stability measurements.
