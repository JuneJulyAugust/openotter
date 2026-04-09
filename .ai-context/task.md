# openotter Task Backlog

This backlog is hierarchical and execution-focused. Primary STM32 work comes first; the Raspberry Pi WiFi bridge remains only for compatibility, bench testing, and transition support.

## 1. MVP1 - LiDAR-first closed loop + obstacle stop (active)

### 1.1 Foundation and app bring-up

#### 1.1.1 Project and runtime setup

- [x] Create initial iOS app target (`openotter`) and baseline module layout.
- [x] Add runtime support checks for LiDAR-capable devices and fallback error states.
- [x] Add app permissions/configuration required for capture and motion pipelines.

#### 1.1.2 LiDAR point-cloud data contract

- [x] Implement LiDAR `sceneDepth` stream with on-screen diagnostics.
- [x] Define `PointCloud` and `CaptureFrame` contracts with timestamp, points, camera transform, and RGB image.
- [x] Implement orientation-correct point cloud projection (camera-pov aligned view matrix).
- [x] Add RGB + point-cloud split-screen debug view (portrait top/bottom, landscape left/right).

### 1.2 Estimation component

#### 1.2.1 ARKit pose and ESC velocity

- [x] Define `VehicleState` model (`pose: SIMD-float4x4`, `speed_mps`, `timestamp`).
- [x] Implement ARKit `worldTracking` session to extract 6D camera pose.
- [x] Add `ARKitPoseView` to demonstrate and validate 6D pose tracking.
- [x] Implement ARKit World Map management (save/load/management UI) for persistent localization.
- [x] Refactor iOS and transport ViewModels for testability (SRP/DIP).
- [x] Implement `SelfDrivingView` and `SelfDrivingViewModel` orchestrator (10Hz control loop).
- [x] Integrate ESC velocity telemetry into `VehicleState` and planner feedback.

### 1.3 Planner and control component

#### 1.3.1 Speed planner and control

- [x] Define planner output contract (`target_speed_mps`, `stop_requested`, `timestamp`).
- [x] Implement speed planner: reach target speed, then keep it.
- [x] Implement controller to track planner speed command (baseline loop: `10 Hz`).
- [ ] Keep target speed configurable (initial range: `0.1` to `2.0` m/s).
- [x] Implement straight-drive heading hold using iPhone yaw-rate feedback (magnetometer as optional coarse reference).

#### 1.3.2 Obstacle blocking and stop signal

- [x] Add obstacle-point input from LiDAR to planner.
- [x] Implement blocked-future-path check in planner.
- [x] Emit planner stop signal when future path is blocked.
- [x] Make planner stop threshold configurable.
- [x] Ensure planner stop signal has higher priority than normal speed command.
- [x] Ensure `estop` command path has strict priority over all drive commands.

#### 1.3.3 STM32 direct BLE control

- [x] Generate STM32CubeMX project for STM32L475 target (`stm32-mcp`).
- [x] Develop command-line build and flash script `build.sh` using STM32CubeCLT.
- [x] Establish CMake presets and correct `.gitignore` & Git LFS for STM32 drivers.
- [x] Fix the STM32/iOS BLE reconnect loop by aligning GAP device naming with iOS cache behavior.

### 1.4 Legacy Raspberry Pi WiFi bridge

#### 1.4.1 Protocol and transport implementation

- [x] Define protocol v1 fields (`hb_iphone`, `hb_pi`, `cmd:s=x,m=y`).
- [x] Implement Wi-Fi (UDP) adapter on Raspberry Pi 4B with bi-directional heartbeat.
- [x] Implement TUI dashboard on Pi (FTXUI) with stationary bi-directional meters.
- [x] Implement USB serial bridge between Raspberry Pi and Arduino.
- [x] Implement Arduino firmware for PWM/servo command execution.
- [x] Implement Bluetooth LE connection from macOS to ESC for telemetry reverse-engineering.
- [x] Pivot: Migrate ESC BLE telemetry directly to the iPhone to bypass the Raspberry Pi hop.

#### 1.4.2 Bridge integration contract

- [x] Implement iPhone heartbeat (1 Hz) and 1.5 s timeout logic.
- [x] Implement Raspberry Pi heartbeat (1 Hz) and 1.5 s timeout logic.
- [x] Implement `Raspberry Pi WiFi` view on iOS for real-time monitoring.

### 1.5 Agent Runtime and Telegram control

#### 1.5.1 Agent subsystem foundation

- [x] Create `Agent/` source directory under `openotter-ios/Sources/`.
- [x] Define `AgentAction` enum (move, stop, queryStatus, unknown).
- [x] Define `CommandInterpreter` protocol and implement `KeywordInterpreter`.
- [x] Define `ActionDispatching` protocol and implement `ActionDispatcher` routing to `PlannerOrchestrator`.
- [x] Define `ResponseBuilding` protocol and implement `ResponseBuilder`.

#### 1.5.2 Telegram Gateway

- [x] Implement `TelegramGateway` with long-poll loop (30s timeout, back-to-back polling).
- [x] Implement `KeychainHelper` for secure bot token storage.
- [x] Implement chat ID whitelist for authorized user filtering.
- [x] Implement exponential backoff retry on poll errors (1s→2s→4s→8s, cap 30s).

#### 1.5.3 Speech output

- [x] Implement `SpeechOutput` wrapping `AVSpeechSynthesizer` with enable/disable toggle.
- [x] Integrate TTS into `AgentRuntime` response path.

#### 1.5.4 Future extension stubs

- [x] Define `SkillProviding` and `SkillRegistering` protocols with no-op implementation.
- [x] Define `MemoryStoring` protocol with no-op implementation.

#### 1.5.5 Debug and diagnostic UI

- [x] Implement `AgentDebugView` with token input, connection status, message log, and manual test input.
- [x] Add `AgentDebugView` to `HomeView` diagnostics section.

#### 1.5.6 Integration

- [x] Wire `ActionDispatcher` to real `PlannerOrchestrator` and `SafetySupervisor`.
- [x] End-to-end test: Telegram command from second phone → car executes → TTS speaks → Telegram reply received.

### 1.6 Validation and exit criteria

#### 1.6.1 MVP1 acceptance checks (autonomous driving)

- [x] Hold target speed on flat indoor floor for repeatable runs.
- [x] Maintain straight driving within defined drift tolerance.
- [x] Stop before obstacle under configurable stop policy.
- [x] Trigger safe stop on stale LiDAR data or control-link timeout.

#### 1.6.2 MVP1 acceptance checks (agent runtime)

- [x] Telegram bot receives and responds to commands from a second phone.
- [x] Commands dispatch through planner/safety stack (safety cannot be bypassed).
- [x] App speaks confirmations aloud via TTS.
- [x] AgentDebugView works in isolation without Telegram or BLE connections.
- [x] Bot token stored in Keychain, never in source code or UserDefaults.

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

### 4.1 Pending product and engineering decisions

#### 4.1.1 Open items

- [ ] Decide whether to continue reverse-engineering the Snail ESC BLE protocol (via Android HCI snoop) or pivot to using ARKit VIO for velocity estimation.
- [ ] Decide whether BLE remains worth keeping as a prototype transport after Wi-Fi UDP is validated on vehicle.
- [ ] Finalize stop-policy defaults after initial braking tests.
- [ ] Finalize controller loop rate after latency and stability measurements.
- [ ] Decide whether any legacy Pi/Arduino code should remain beyond maintenance support.
