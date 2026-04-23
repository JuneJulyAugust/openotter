# Changelog - openotter-ios

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.11.0] - 2026-04-22

### Added
- **VL53L1CB Multi-Zone ToF Rendering**: Implemented a 2D depth grid in `STM32ControlView` to visualize 1x1, 3x3, and 4x4 ToF depth maps streamed over BLE.
- **Speed-Dependent Decel Model**: Replaced constant deceleration with a physical linear drag model `a(v) = a0 + k*v` fitting motor back-EMF and rolling friction. Calibrated directly from field data for exact stopping distances.
- **Agent Speed Controls**: Added Telegram bot keyboard presets (Slow, Normal, Fast) and stateful `.setSpeed` actions.
- **Agent Help Command**: Added `/help` handler that returns dynamic usage instructions while suppressing Text-To-Speech output (`speakable: false`).
- **Safety Prototype**: Added `fit_decel.py` to `prototypes/decel_fit/` for calibrating deceleration parameters via spatial integration error minimization.

### Changed
- **Safety Policy Tune**: Replaced v0.4 tri-zone FSM with a unified time-to-brake policy using empirical tuning.
- **HUD Diagnostics**: Renamed `overshootM` to `brakingDistanceM`, added HUD display of exact `actualDecelMPS2`, and embedded trigger speeds inside emergency overlay views.
- **BLE Management**: Implemented frame reassembly for chunked 0xFE62 ATT_MTU packets to support the BlueNRG-MS module limit. Disabled ToF BLE notifications to prioritize high-frequency motor actuation, maintaining self-driving keepalive signals.


## [0.10.0] - 2026-04-16

### Changed
- **Project Rename**: Rebranded from "Metabot" to **OpenOtter** across the entire codebase, assets, and documentation.

### Added
- **Unified Branding**: Updated app icons, splash screens, and telemetry UI with the new OpenOtter identity.

## [0.9.0] - 2026-04-05

### Added
- **Telegram Agent Runtime (MVP1)**: Implemented an OpenClaw-inspired agent running entirely on-device. Enables zero-infrastructure remote control via a Telegram bot using long-polling.
- **Agent Subsystems**: Added `CommandInterpreter` (normalized keyword mapping aliases), `ActionDispatcher`, and TTS confirmation via `SpeechOutput` (fresh synthesizer bypassing iOS bugs).
- **Diagnostics UI**: Integrated a standalone `AgentDebugView` to verify the command pipeline before engaging the driving stack.
- **Security**: Added secure Keychain backing for the Telegram bot token and chat-ID whitelist enforcement.

## [0.8.1] - 2026-04-04

### Changed
- **Safety policy tuning**: Reduced TTC thresholds (brake 0.8→0.3s, caution 1.5→0.8s) and raised max deceleration to 2.5 m/s² to match measured tire grip. Raised minimum brake/caution floor distances (0.15→0.30m, 0.25→0.50m) to eliminate low-speed BRAKE→CAUTION slip caused by kinematic overshoot landing above the brake threshold.
- **DESIGN.md**: Rewritten with concrete worked examples at each speed tier and analysis of the low-speed slip root cause.

### Added
- **Safety trigger snapshots**: Captures filtered depth, motor speed, and ARKit speed at the exact frame CAUTION and BRAKE are first triggered. Displayed in the SAFETY HUD card and emergency brake overlay so the operator can read the conditions that caused each intervention.

## [0.8.0] - 2026-03-31

### Added
- **End-to-End Self-Driving & Safety**: The first complete autonomous driving stack. The robot can hold a target speed, follow a heading, and automatically stop for obstacles.
- **Tri-Zone Safety Supervisor**: Redesigned the safety override into a clear state machine (CLEAR, CAUTION, BRAKE) with latched speed thresholds and asymmetric EMA depth filtering.
- **Anti-Oscillation Logic**: Eliminated "stop-go" boundary oscillation using cooldown timers and a linear throttle ramp in the constant speed planner.
- **Comprehensive Test Suite**: Added 56 new XCTest unit and integration tests covering the planner, supervisor math, EMA filtering, and full mission orchestrator scenarios. Run with `./build.sh test`.

## [0.7.1] - 2026-03-30

### Added
- **Motor Calibration**: Integrated physical wheel calibration logic ($88\text{mm}$ diameter) to convert raw motor RPM to vehicle speed in $\text{m/s}$.
- **Robust Filtering**: Implemented a window-based `MovingAverageFilter` to smooth noisy motor RPM data with minimal latency.
- **Speed Telemetry**: Added $\text{m/s}$ speed display to both `SelfDrivingView` and `STM32ControlView`.

### Changed
- Reorganized project resources by moving `motor_wheel_calibration.csv` to the `Resources/` directory.
- Updated `ESCBleManager` to use the new filtering and conversion pipeline for all telemetry updates.

## [0.7.0] - 2026-03-29

### Added
- **Planner Framework**: Scaffolded the planner protocol, context, and orchestrator. Added a simple `WaypointPlanner` to follow target paths.
- **Safety Supervisor**: Implemented a safety module that triggers a brake alarm based on TTC (Time-to-Collision) distance using center-pixel LiDAR depth. Tested to trigger correctly at 2m/s assumed speed.

### Changed
- Integrated planner and safety supervisor into `SelfDrivingViewModel` to form the first functional autonomous control loop foundation.

## [0.6.0] - 2026-03-29

### Added
- **Self Driving Mode**: Introduced `SelfDrivingView` and `SelfDrivingViewModel` to orchestrate ARKit (localization), ESC BLE (telemetry), and STM32 BLE (actuation) into a single unified 10Hz control loop.
- **Persistent AR Maps**: Added the ability to select and persist an active `ARWorldMap` across sessions and relocalize dynamically without restarting the app.
- **Horizontal Dashboard**: Redesigned `HomeView` into a forced-landscape layout featuring modern transparent materials, distinct "Self Driving" and "Diagnostics" paths, and updated iconography.

### Changed
- Refactored 2D trajectory rendering from `ARKitPoseView` into a reusable `PoseMapView` component.
- Extracted shared telemetry and control UI components into `CommonViews.swift`.
- Renamed references of "Full Self-Driving" to "Self Driving".

## [0.5.1] - 2026-03-28

### Fixed
- Hardened the STM32 BLE control screen so it matches both the cached GAP name and the advertising local name, restoring reconnects after the first peripheral session.
- Cleared stale `CBPeripheral` and characteristic references on disconnect and discovery failure to prevent scan-only states.

## [0.5.0] - 2026-03-27

### Added
- **Direct ESC BLE Telemetry**: Integrated `ESCBleManager` for direct Bluetooth LE connection between the iPhone and the Snail ESC.
- Added real-time telemetry card to `MCPTestView` displaying motor speed (RPM), voltage, ESC/Motor temperatures, update frequency (Hz), and message count.
- Dynamic `CoreBluetooth` write typing to handle ESC initialization handshakes correctly.

### Changed
- Promoted development 0.5.x-dev versions (World Map UI, ARKit Accuracy, ViewModel refactor) into this release.

## [0.5.1-dev] - 2026-03-23

### Changed
- **ARKit Localization Accuracy**: Rewrote `ARKitPoseViewModel` with 8 improvements:
  - Gimbal-safe yaw extraction via `atan2` (fixes ±π discontinuities).
  - Dedicated high-priority delegate queue (prevents frame drops from UI contention).
  - Session interruption + automatic relocalization handlers.
  - ARWorldMap save/load for drift correction when revisiting mapped areas.
  - `smoothedSceneDepth` enabled for better mesh-based tracking.
  - ARReferenceImage detection for visual marker drift correction.
  - Tracking confidence field (`PoseEntry.confidence`) for planner quality gating.
  - Updated `ARKitPoseView` with interruption warnings, confidence display, and world map controls.
- **World Map Management UI**:
  - Implemented named multiple map storage (`WorldMapEntry`) with JSON metadata persistence.
  - Added `MapManagerView` sheet for saving, selecting, and deleting specific maps.
  - Redesigned `ARKitPoseView` controls with smaller 40pt icon buttons and a narrower right panel.
  - Active map name and selection status now clearly displayed in the data panel.

## [0.5.0-dev] - 2026-03-23

### Changed
- **MCP Test ViewModel Refactor**: Extracted pure parsing (`MCPProtocol.swift`) and UDP networking (`MCPConnection.swift`) into separate, highly-testable components.
- ViewModel now serves as a thin coordinator over protocol and transport injected layers.

### Added
- Comprehensive XCTest suite for `MCPProtocol.swift` validating edge cases, clamping, and round-trip parsing with C++.

## [0.4.0] - 2026-03-22

### Added
- **ARKit 6D Pose Estimation**: New `ARKitPoseView` to demonstrate and validate visual-inertial odometry.
- **Landscape UI**: Forced landscape orientation for the pose view with custom layout and safe area handling.
- **Trajectory Visualization**: Interactive 2D map with auto-zoom, grid scaling, and Jet colormap for history playback.
- **Enhanced Accuracy**: Enabled `.sceneDepth`, `.mesh` scene reconstruction, vertical plane detection, and max video resolution in the ARSession to minimize VIO drift.

### Changed
- Reorganized `HomeView` to serve as a unified landing page for Perception, Estimation, and Diagnostics modules.

## [0.3.0] - 2026-03-20

### Added
- **Full End-to-End Control Path**: iPhone commands now actuate RC car servos.
- **Arduino Control Module**: New Arduino Mega firmware with normalized serial protocol and safety arming logic.
- **Robust Serial Bridging**: MCP (Pi) now features auto-reconnect and boot-sync for stable Arduino communication.
- **Pi-native Toolchain**: Self-contained `arduino-cli` environment for Pi-side compilation and flashing.
- Real-time hardware feedback from actuators back to the MCP dashboard.

### Changed
- Refined steering/motor command protocol with 10Hz/20Hz update rate and ACK logging.

## [0.2.0] - 2026-03-19

### Added
- Bi-directional MCP bridge for Raspberry Pi 4B over Wi-Fi (UDP).
- `MCPTestView` diagnostics interface with real-time network metrics and manual controls.
- Dynamic IP discovery and device naming in diagnostics view.
- 1.5-second watchdog timeout for connection status.
- Card-based modern UI with `GroupBox` and SF Symbols.

### Fixed
- Build error on iOS by replacing macOS-specific `Host` API with `UIDevice`.
- Network communication logic for reliable packet parsing.
- Diagnostics view integration with `DepthCaptureView` start prompt.

## [0.1.0] - 2026-03-14


### Added
- Initial project scaffold with LiDAR-capable support checks.
- ARKit `sceneDepth` stream capture and diagnostics.
- Raw point cloud back-projection and Metal rendering.
- Orientation-aware camera view matrix and intrinsics scaling.
- RGB + point-cloud split-screen debug view (portrait/landscape).
- CLI build and deploy scripts (`build.sh`).
- Project branding with custom AppIcon assets.
- Explicit `Debug` and `Release` optimization profiles.
- Unit tests for `DepthPointProjector` math.
