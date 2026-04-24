# OpenOtter AI Chat History

This file stores the historical context, milestones, and prompts to resume development across sessions.

---

## 2026-04-24 - OpenOtter v1.0 Safety Milestone

### Summary
Released the first v1.0.0 milestone across the iOS app and STM32 firmware. The integrated safety loop now covers forward LiDAR braking, rear ToF firmware braking, Telegram Park/Drive state management, and Self Driving emergency UI parity.

### Achievements
1. **Rear emergency panel parity:** Reverse firmware BRAKE notifications now appear in the Self Driving emergency panel with the same operational detail as forward collision warnings.
2. **Park state correctness:** Telegram/app Park clears planner, firmware-event, brake-record, and emergency presentation state instead of leaving stale BRAKE visible while speed is zero.
3. **Safety latch hardening:** Forward BRAKE holds through sensor dropout, and re-sending Drive during BRAKE no longer releases the latch through transient planner zero throttle.
4. **Simulator workflow captured:** `openotter-ios/build.sh test` now auto-selects a stable installed simulator and supports explicit simulator overrides.
5. **Version synchronization:** Bumped and tagged:
   - iOS App: `v1.0.0`
   - STM32 MCP: `v1.0.0`

### Current State
- **iOS App:** `v1.0.0` release metadata is current.
- **STM32 Firmware:** `v1.0.0` release metadata is current.
- **Next Step:** Deploy iOS v1.0.0 and flash STM32 v1.0.0 for the physical milestone validation run.

### Prompt Context for Next Session
"OpenOtter is at the v1.0.0 safety milestone. iOS and STM32 are synchronized at v1.0.0, with rear firmware BRAKE events shown in the Self Driving emergency panel, Park clearing stale emergency state, and forward/reverse safety latches hardened. Next priority is physical validation on the vehicle phone and STM32 board."

---

## 2026-04-22 - Safety Calibration & ToF Sensor Support Release

### Summary
Replaced the conservative constant deceleration safety model with a physical linear drag model calibrated directly from field data. Integrated native VL53L1CB ToF sensor support into the STM32 firmware and streamed it over BLE. Advanced the Telegram agent with stateful speed controls and dynamic help.

### Achievements
1. **Safety Calibration:** Modeled motor back-EMF and rolling friction using a spatial integral `a(v) = 0.66 + 0.87*v`. This drastically improved the accuracy of the braking distance predictions and fixed the massive overshoot bumper gaps.
2. **STM32 ToF Integration:** Implemented a native driver for the VL53L1CB, handling 8x8 multi-zone data, and streamed it via a new 0xFE60 BLE GATT service with ATT_MTU chunking.
3. **Agent Speed Controls:** Added Telegram bot keyboard presets (Slow, Normal, Fast), stateful throttle tracking, and a dynamic `/help` command that suppresses TTS output.
4. **Version Synchronization:** Bumped versions across subsystems:
   - iOS App: `v0.11.0`
   - STM32 MCP: `v0.3.1`
5. **Git Tags Created:** Applied corresponding git tags (`ios-v0.11.0`, `stm32-mcp-v0.3.1`) to the main branch.

### Current State
- **Safety Policy:** Linear drag model fully deployed and active.
- **STM32 Firmware:** `v0.3.1` deployed with robust ToF capabilities.
- **Next Step:** Validate the Agent commands in physical test runs, and proceed with Phase C of the Agent MVP plan.

### Prompt Context for Next Session
"In the last session, we released iOS v0.11.0 and STM32 v0.3.1, replacing the constant safety model with an exact physical linear drag model and adding native ToF sensor support via BLE. The Agent Runtime was also upgraded with speed controls. The next priority is to validate the Telegram Agent physically and proceed with Phase C of the MVP."

---

## 2026-04-16 - Project Rename & v0.10.0 Rebrand Release

### Summary
Formally rebranded the project from \"Metabot\" to **OpenOtter** and synchronized version numbers across all component subsystems to establish a unified release baseline.

### Achievements
1. **Unified Branding:** Performed a global search-and-replace to rename the project to OpenOtter across the entire codebase, assets, and documentation.
2. **Version Synchronization:** Bumped and tagged all major components:
   - iOS App: `v0.10.0` (previously `v0.9.0`)
   - Raspberry Pi MCP: `v0.4.0` (previously `v0.3.0-dev`)
   - STM32 MCP: `v0.3.0` (previously `v0.2.1`)
3. **Documentation Updated:** Refreshed `CHANGELOG.md` files, `VERSION` files, and `.ai-context` documentation (`walkthrough.md`, `achievements.md`, `plan.md`, `task.md`, `chat.md`) to reflect the new identity and release state.
4. **Git Tags Created:** Applied corresponding git tags (`ios-v0.10.0`, `raspberry-pi-mcp-v0.4.0`, `stm32-mcp-v0.3.0`) to the main branch.

### Current State
- **Project Identity:** Consistent OpenOtter branding established.
- **Release Baseline:** Unified v0.10.0 / v0.4.0 / v0.3.0 state achieved.
- **Next Step:** Resume MVP1 Agent Runtime implementation following the rebranded path.

### Prompt Context for Next Session
\"In the last session, we formally rebranded the project to OpenOtter and bumped the versions to ios-v0.10.0, rpi-mcp-v0.4.0, and stm32-mcp-v0.3.0. All documentation and tags have been updated. The next priority is to continue with the MVP1 Agent Runtime implementation, specifically focusing on Phase B (Telegram Gateway) and Phase C (App Core wiring) as outlined in the task backlog.\"

---

## 2026-04-05 - Agent Runtime & Telegram Gateway Design

### Summary
Designed an OpenClaw-inspired Agent Runtime to enable remote control of the RC car from a second phone via Telegram. The architecture adds a Telegram bot (long polling), swappable command interpreter, action dispatcher, TTS voice feedback, and stub interfaces for future LLM/skill/memory subsystems.

### Achievements
1. **Architecture design:** Defined the full Agent Runtime pipeline: TelegramGateway → CommandInterpreter → ActionDispatcher → ResponseBuilder → SpeechOutput.
2. **Feasibility validated:** Telegram Bot API long polling works directly from URLSession inside the iOS app with zero dependencies. No server needed.
3. **Safety invariant preserved:** The Agent Runtime is a new input source, not a control path. All commands flow through PlannerOrchestrator → SafetySupervisor.
4. **Future-proofed:** CommandInterpreter protocol allows swapping keyword matching for LLM interpretation. SkillRegistry and MemoryStore stubs exist for OpenClaw-inspired agent capabilities.
5. **Design spec written:** `docs/superpowers/specs/2026-04-05-agent-runtime-telegram-design.md`

### Current State
- **Autonomous driving:** v0.8.0 — fully operational.
- **Agent Runtime:** Design complete, implementation pending.
- **Next Step:** Implement the Agent subsystem following the phased plan.

### Prompt Context for Next Session
"In the last session, we designed the Agent Runtime and Telegram Gateway for MVP1. The design spec is at docs/superpowers/specs/2026-04-05-agent-runtime-telegram-design.md. The task backlog in .ai-context/task.md has the full breakdown under section 1.5. Start with Phase A: build the Agent/ subsystem and AgentDebugView in isolation, test with manual input before connecting Telegram or BLE."

---

## 2026-03-28 - STM32 BLE Reconnect Fix

### Summary
The STM32 BLE path now reconnects reliably after the first iPhone session. The root cause was iOS caching the wrong GAP name (`BlueNRG`) from the STM32 peripheral, which caused the scanner to ignore the device on later scans.

### Achievements
1.  **STM32 BLE Naming**: Updated the BlueNRG GAP device name to `OPENOTTER-MCP` and expanded the GAP device-name length to match the real advertising name.
2.  **iOS Scanner**: Hardened `STM32BleManager` to match both cached peripheral names and advertising local names, then clear stale references on disconnect.
3.  **Validation**: Rebuilt and flashed the firmware, then verified the app can rediscover the STM32 BLE board after reconnect.

### Current State
- **STM32 BLE**: Advertising and reconnecting correctly.
- **iOS Control**: `STM32ControlView` can connect after a prior session without staying stuck in scanning.
- **Next Step**: Keep the BLE path as the validated direct-control option while the rest of MVP1 continues.

### Prompt Context for Next Session
"The STM32 BLE direct-control path is working again after fixing the cached GAP-name mismatch. The next session should treat the reconnect-safe STM32 BLE link as the current baseline and build on top of it if more control features are added."

---

## 2026-03-23 - MCP Refactor and World Map Management

### Summary
Extensive architectural refactoring for both iOS and MCP (Raspberry Pi) components to ensure testability and separation of concerns. Implemented ARKit World Map management for persistent, drift-corrected localization.

### Achievements
1.  **iOS Refactor**: Decomposed `MCPTestViewModel` into `MCPConnection` (UDP transport), `MCPProtocol` (parsing), and a thin coordinator.
    - Added high-coverage XCTest suite for the iOS network protocol.
    - Implemented high-priority delegate queue for ARKit to prevent UI contention frame drops.
2.  **MCP (C++) Refactor**: Broke monolithic `main.cpp` into discrete modules: `protocol`, `network_server`, `serial_forwarder`, `dashboard`, and `mcp_status`.
    - Integrated GoogleTest for the C++ protocol logic, enabling hardware-independent CI.
3.  **World Map Management**:
    - Added `MapManagerView` for saving, loading, and deleting ARKit World Maps.
    - Implemented JSON-based metadata persistence for multiple named maps.
    - Enhanced `ARKitPoseViewModel` with relocalization handlers and visual marker (ARReferenceImage) support.
4.  **Tracking Accuracy**: Fixed a ±π discontinuity in yaw extraction and implemented gimbal-safe rotation handling.

### Current State
- **Perception**: LiDAR and RGB pipelines are stable.
- **Estimation**: 6D Pose with World Map persistence is operational.
- **Control**: Refactored, testable command path from iPhone to Arduino.

### Prompt Context for Next Session
"In the last session, we completed a major architectural refactor for testability and added ARKit World Map management for persistent localization. The protocol logic is now covered by unit tests on both iOS and MCP. The next priority remains the Raspberry Pi Bluetooth LE connection to the ESC for real-time velocity telemetry."

---

## 2026-03-22 - ARKit 6D Pose Estimation
...
### Summary
Successfully implemented and visualized the 6D pose estimation using ARKit's Visual-Inertial Odometry (VIO). We pivoted from pure IMU-based velocity/position tracking to ARKit for localization and Bluetooth ESC telemetry for velocity.

### Achievements
1.  **Home Page Redesign**: Reorganized `HomeView.swift` to act as the primary landing page, categorizing features into Perception, Estimation, and Diagnostics.
2.  **ARKit Pose ViewModel**: Implemented `ARKitPoseViewModel` to manage the `ARSession`.
    -   Configured for `.gravity` alignment to establish a consistent Robot Coordinate Frame (+X Forward, +Y Up, +Z Right).
    -   Enabled advanced accuracy features: `.sceneDepth` (LiDAR), `.mesh` scene reconstruction, and horizontal/vertical plane detection to minimize drift.
    -   Exposed internal `ARCamera.TrackingState` to ensure data is only recorded when VIO is fully initialized.
3.  **Landscape Visualization (`ARKitPoseView`)**:
    -   Built a robust, forced-landscape UI using `GeometryReader`, bypassing iOS system orientation locks, with fixed safe areas for the iPhone 13 Pro Max.
    -   Implemented a 2D canvas plotting the X-Z trajectory with continuous real-time rendering.
    -   Added auto-zooming, gesture-based pan/zoom, and a time-based Jet colormap gradient that renders the historical path when tracking is stopped.

### Current State
- **Perception**: LiDAR point cloud and RGB debug view operational.
- **Estimation**: 6D Pose (Position + Orientation) actively tracking with high accuracy via ARKit.
- **Control**: End-to-end path from iPhone to Arduino verified.

### Prompt Context for Next Session
"In the last session, we completed the ARKit 6D Pose estimation module on iOS. We have a highly accurate, drift-minimized trajectory visualization running in a forced-landscape view. We also established the 'HomeView' to tie the app together. The next major step is to tackle the other half of our new estimation strategy: implementing the Bluetooth LE connection on the Raspberry Pi to pull real-time velocity telemetry directly from the ESC, and forwarding that data back to the iPhone."

---

## 2026-03-20 - End-to-End Control Path

### Summary
Successfully implemented and verified the full control path from the iPhone brain to the physical actuators of the RC car. This milestone bridges the gap between our high-level iOS application and low-level Arduino firmware.

### Achievements
1.  **Arduino Control Module**: Created `firmware/openotter-arduino/`, a dedicated firmware for the Arduino Mega.
    - Implemented a normalized `-1.0 to 1.0` serial protocol for steering and motor power.
    - Included safety features: ESC arming sequence and heartbeat monitoring (currently disabled for debugging).
    - Isolated toolchain: Self-contained `arduino-cli` setup on the Raspberry Pi for easy deployment.
2.  **MCP Serial Integration**: Updated the C++ bridge on the Raspberry Pi (`raspberry-pi-mcp`) to forward UDP commands from the iPhone to the Arduino via USB Serial.
    - Added robustness features: Auto-reconnect on I/O errors, 3.5s boot delay handling, and serial buffer flushing.
    - Integrated real-time serial feedback into the FTXUI dashboard.
3.  **Deployment & Testing**: Established robust `deploy.sh` scripts for both the Arduino and MCP modules, enabling seamless updates from the development machine to the Pi.
4.  **Hardware Verification**: Confirmed that steering commands from the iPhone correctly actuate the servo on Pin 4.

### Current State
- **Steering**: Fully operational end-to-end.
- **Motor**: ESC arming logic is in place; physical motor disconnected for safety during initial testing.
- **Robustness**: MCP gracefully handles Arduino resets and power brownouts.

### Prompt Context for Next Session
"In the last session, we completed the control path from iPhone -> Raspberry Pi (UDP) -> Arduino (Serial) -> Actuators. We have a robust MCP bridge and a self-contained Arduino deployment system. Steering is verified on Pin 4. Next steps: Safely test the motor power on Pin 8 and begin integrating the LiDAR/Vision feedback loop for autonomous control."

---

## 2026-03-19 - MCP Bridge Reproduction (Legacy)

To reproduce the current state of the MCP bridge (Raspberry Pi + iOS), follow these instructions:

### 1. Raspberry Pi (MCP High-Level)
- Create a C++17 project with `CMake`.
- Dependencies: `asio` (libasio-dev), `ftxui` (cloned from GitHub).
- Port: UDP 8888.
- Protocol:
  - Rx `hb_iphone:<count>` -> Increment HB RX, update Brain Info (Name/IP).
  - Rx `cmd:s=<float>,m=<float>` -> Increment CMD RX, update Steering/Motor values.
  - Tx `hb_pi:<count>` -> Every 1.0s to the last seen iPhone endpoint.
- Features:
  - Bi-directional dashboard TUI.
  - Stationary meters (Blue/Left for negative, Green/Right for positive).
  - 1.5s timeout logic (mark OFFLINE if no data received).
  - Pi Local Time display.

### 2. iOS (Brain)
- Add `MCPTestViewModel` (ObservableObject):
  - Use `NWConnection` for UDP communication to Pi IP (192.168.2.189:8888).
  - Heartbeat: Send `hb_iphone:<count>` every 1.0s.
  - Timeout: 1.5s (mark Disconnected if no `hb_pi` received).
  - Commands: Send `cmd:s=%.2f,m=%.2f` when sliders change.
  - IP Discovery: Use `getifaddrs` to find local `en0` address.
- Add `MCPTestView` (SwiftUI):
  - Card-based layout with `GroupBox`.
  - Device info header (Brain & MCP).
  - Network Metrics card (iPhone TX vs Pi RX counts).
  - Manual Control card (Steering/Motor sliders + Neutral/Reset button).
- Integrate into `DepthCaptureView`:
  - Add "MCP Diagnostics" button to the start screen prompt.

### 3. Communication Contract
- Address: 192.168.2.189 (Pi), 192.168.2.111 (iPhone - typical).
- Port: 8888 (UDP).
- Frequency: 1Hz Heartbeat.
- Safety: 1.5s Watchdog Timeout.
