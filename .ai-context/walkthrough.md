# metalbot Walkthrough (Development Log)

This file is for implementation-time learning, not upfront planning.

Add entries only after real coding, integration, or testing work reveals valuable issues or decisions.

## Logging Rules

- Log concrete events: implemented feature, observed bug, measured behavior, resolved issue.
- Avoid speculative design notes that belong in `plan.md`.
- Keep each entry short and technical.
- Include reproducible evidence when possible (logs, metrics, trace IDs, test names).

## Entry Template

### YYYY-MM-DD - Short Title

- **Context:** What subsystem and scenario were involved.
- **What we built/tested:** Concrete implementation action.
- **Issue observed:** Actual failure mode or limitation.
- **Root cause:** Confirmed cause, not guesswork.
- **Resolution:** Code/config/protocol change made.
- **Validation:** How we proved the fix works.
- **Follow-up:** Remaining risk or next step.

## Entries

### 2026-03-22 - MVP1 Step 4: ARKit 6D Pose Integration and Visualization

- **Context:** Implementing the new pose estimation module based on the ARKit VIO pivot.
- **What we built/tested:** Created `ARKitPoseViewModel` configuring an `ARWorldTrackingConfiguration` with `.gravity` alignment, `.sceneDepth`, `.mesh` reconstruction, and vertical/horizontal plane detection for maximum accuracy. Built a custom, forced-landscape `ARKitPoseView` featuring an interactive 2D trajectory canvas, auto-zoom, and a Jet colormap for history playback.
- **Issue observed:** (1) Initial drift was high when moving the phone before ARKit fully initialized. (2) Standard iOS views cut off text around the physical notch when forced into landscape while the device was held vertically.
- **Root cause:** (1) ARKit requires time and environmental texture to build its initial visual anchors. (2) `SafeAreaInsets` behave unintuitively when a view is mathematically rotated 90 degrees to bypass system orientation locks.
- **Resolution:** (1) Added UI states mapping to `ARCamera.TrackingState` to warn the user during initialization, and blocked trajectory recording until tracking is `.normal`. (2) Hardcoded generous `leftPad` and `rightPad` tailored to the physical dimensions of the iPhone 13 Pro Max.
- **Validation:** Trajectory visualization maps movement cleanly to a 1.0m grid. Jet colormap correctly indicates time-series history when tracking is stopped.
- **Follow-up:** Begin integration of Raspberry Pi Bluetooth connection to read ESC velocity data.

### 2026-03-22 - Research: Transition to ARKit 6D Pose and ESC Velocity

- **Context:** Moving from experimental IMU-only estimation to robust robotics sensors.
- **What we built/tested:** Research phase only. Evaluated ARKit `worldTracking` for 6D pose and ESC Bluetooth telemetry for velocity.
- **Issue observed:** Pure IMU double-integration for velocity and position is not feasible due to high drift and noise floor on mobile-grade sensors.
- **Root cause:** Physics of low-cost MEMS IMUs; lack of external reference leads to unbounded error growth.
- **Resolution:** Updated `plan.md` and `task.md` to pivot:
  - **Pose**: Use ARKit's Visual-Inertial Odometry (VIO) for 6D position and orientation.
  - **Velocity**: Use Raspberry Pi to connect to the ESC via Bluetooth for direct RPM/speed telemetry.
  - **New Task**: Add `ARKitPoseView` to the iOS app to validate tracking stability before planner integration.
- **Validation:** N/A (Research and Plan update).
- **Follow-up:** Implement `ARKitPoseView` and establish Raspberry Pi <-> ESC Bluetooth communication.

### 2026-03-14 - MVP1 Step 1: LiDAR capture + RGB debug display

- **Context:** iPhone 13 Pro/Pro Max app bring-up for MVP1 perception foundation.
- **What we built/tested:** Implemented ARKit `sceneDepth` capture, depth-to-point-cloud back-projection, Metal point rendering, RGB camera preview, adaptive split layout, diagnostics HUD, and CLI build/deploy workflow.
- **Issue observed:** (1) CLI deploy failed from signing/provisioning mismatch. (2) Auto device detection failed in script parsing. (3) Point cloud appeared rotated/misaligned vs RGB. (4) App icon did not appear correctly on device.
- **Root cause:** (1) Wrong team identifier usage and missing provisioning update flag. (2) Device parser assumed leading whitespace. (3) Projection/view math mixed orientation assumptions; view matrix must be interface-orientation aware and intrinsics must be scaled to depth resolution. (4) `Assets.xcassets` was not being compiled into `Assets.car`, and previous icon source had low contrast/alpha issues.
- **Resolution:** Added `-allowProvisioningUpdates`, fixed team setup, corrected device UUID extraction, switched to orientation-aware `viewMatrix(for:)`, fixed intrinsics scaling and axis signs, enabled rich diagnostics, moved icon to asset catalog pipeline, and ensured `Assets.car` is compiled in builds.
- **Validation:** `./build.sh deploy` succeeds; app installs and launches on device; RGB + point-cloud debug screen runs at ~30 FPS with live points and camera image.
- **Follow-up:** Next step is to convert live point cloud into planner-ready obstacle features and integrate with speed/stop planning.

#### Visual Evidence

![MVP1 LiDAR point-cloud + RGB debug view](../assets/achievements/mvp1/2026-03-14_lidar-pointcloud-rgb-capture-display.png)

### 2026-03-14 - Capture pipeline refactor for robustness and testability

- **Context:** LiDAR capture/render stack was functional but had avoidable crash-risk patterns and limited unit-test coverage for projection math.
- **What we built/tested:** Extracted depth back-projection into `DepthPointProjector`, added unit tests for projection invariants, added renderer init error handling, and introduced frame-coalescing in `CaptureViewModel` to prevent unbounded per-frame main-thread task buildup.
- **Issue observed:** Potential one-off crashes and memory pressure from force-unwrapped Metal setup and per-frame asynchronous UI update fan-out under load.
- **Root cause:** (1) renderer initialization used `fatalError`/force unwrap paths, (2) frame delivery created one main-thread task per AR frame with no coalescing, and (3) projection logic lived inside session callbacks with no isolated test seam.
- **Resolution:** Made renderer initialization throwable with user-visible error propagation, moved projection math into a dedicated module, added explicit frame mailbox/coalescing behavior guarded by lock, and added `autoreleasepool` around camera image conversion/frame processing.
- **Validation:** Build succeeds after refactor; new tests validate camera-model equations, intrinsics scaling, and confidence filtering behavior.
- **Follow-up:** Run on-device with Memory Graph/Instruments to confirm stable allocations over long sessions and to tune point count/performance for planner integration.

### 2026-03-14 - Release optimization profile documented and validated

- **Context:** Need deterministic CLI commands for debug vs optimized release deployment on physical device.
- **What we built/tested:** Added explicit `Debug`/`Release` optimization settings in `project.yml` and updated `README.md` with command arguments for both profiles.
- **Issue observed:** Build profile behavior was implicit and command guidance did not clearly separate development and performance runs.
- **Root cause:** Optimization settings and release deployment workflow were not documented as first-class build profiles.
- **Resolution:** Set `Debug` to `-Onone` + `singlefile` and `Release` to `-O` + `wholemodule`; documented `./build.sh deploy` and `./build.sh --release deploy` with manual `xcodebuild` equivalents.
- **Validation:** Verified settings via `xcodebuild -showBuildSettings` and confirmed successful `Release` build and deploy on device.
- **Follow-up:** Add quantitative frame-time benchmarks (Debug vs Release) after planner features increase CPU load.

### 2026-03-19 - MVP1 Step 2: Raspberry Pi MCP Bridge and iOS Diagnostics UI

- **Context:** Transition from STM32 to Raspberry Pi 4B + Arduino architecture for motor control.
- **What we built/tested:**
  - Developed `metalbot-mcp`: a C++17 application on Raspberry Pi using `Asio` for event-driven UDP networking and `FTXUI` for a TUI dashboard.
  - Implemented bi-directional UDP heartbeats (1Hz) between iPhone and Pi with a synchronized 1.5-second connection timeout.
  - Built a car-style TUI on the Pi with stationary, bi-directional meters for steering/motor power (Blue/Left for negative, Green/Right for positive).
  - Added "MCP Diagnostics" view on iOS with real-time status, network metrics (Sent/Received counts/times), and manual sliders for remote control.
  - Fixed iOS IP discovery and macOS-specific API build issues.
- **Issue observed:** (1) Layout jitter in TUI when meters were growing dynamically. (2) Heartbeat RX counter on Pi was erroneously counting control commands. (3) iOS build error on `Host.current().localizedName`.
- **Root cause:** (1) Flexible-width elements caused the center point to shift; fixed with explicit container sizing. (2) Packet parsing didn't distinguish by prefix; fixed with `hb_iphone:`/`cmd:` separation. (3) `Host` API is macOS-only; replaced with `UIDevice`.
- **Resolution:** Refined TUI layout for absolute stability, hardened packet parsing, and implemented iOS device discovery using UIKit.
- **Validation:** Smooth, jitter-free dashboard on Pi; iPhone shows "Connected" status based on Pi heartbeats; 1.5s timeout works bi-directionally.
- **Follow-up:** Next is vehicle validation of the Pi serial bridge, Arduino timeout policy, and planner/control integration.

### 2026-03-20 - MVP1 Step 3: Pi serial bridge + Arduino actuation path

- **Context:** Raspberry Pi bridge and Arduino firmware for low-level actuation.
- **What we built/tested:** Implemented USB serial forwarding from the Pi to the Arduino with automatic reconnect, 3.5-second boot sync, serial buffer flushing, and ACK feedback in the dashboard. The Arduino firmware accepts normalized steering/motor commands and maps them to servo and ESC outputs.
- **Issue observed:** The firmware README described timeout neutralization, but the sketch only logs a warning when no command arrives.
- **Root cause:** `neutralize()` is intentionally commented out in the sketch for debugging.
- **Resolution:** Updated the firmware README to match the current warning-only timeout behavior.
- **Validation:** The implemented protocol and timeout behavior are reflected in `metalbot-mcp/CHANGELOG.md` `0.2.0` and `firmware/metalbot-arduino/metalbot-arduino.ino`.
- **Follow-up:** Revisit timeout neutralization before vehicle-level driving tests.
