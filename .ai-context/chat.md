# Metalbot AI Chat History

This file stores the historical context, milestones, and prompts to resume development across sessions.

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
1.  **Arduino Control Module**: Created `firmware/metalbot-arduino/`, a dedicated firmware for the Arduino Mega.
    - Implemented a normalized `-1.0 to 1.0` serial protocol for steering and motor power.
    - Included safety features: ESC arming sequence and heartbeat monitoring (currently disabled for debugging).
    - Isolated toolchain: Self-contained `arduino-cli` setup on the Raspberry Pi for easy deployment.
2.  **MCP Serial Integration**: Updated the C++ bridge on the Raspberry Pi (`metalbot-mcp`) to forward UDP commands from the iPhone to the Arduino via USB Serial.
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
