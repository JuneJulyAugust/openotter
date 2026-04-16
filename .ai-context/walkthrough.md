# openotter Walkthrough (Development Log)

This file is for implementation-time learning, not upfront planning.

Add entries only after real coding, integration, or testing work reveals valuable issues or decisions.

## Logging Rules

- Log concrete events: implemented feature, observed bug, measured behavior, resolved issue.
- Avoid speculative design notes that belong in `plan.md`.
- Keep each entry short and technical.
- Include reproducible evidence when possible (logs, metrics, trace IDs, test names).

## Terminology

- Current primary path: iPhone app -> STM32 control board.
- Legacy path: Raspberry Pi WiFi bridge.
- Historical entries below may still use older MCP wording where they describe work done before the rename.
- BLE device name `OPENOTTER-MCP` is retained for STM32 compatibility.

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

### 2026-04-16 - Project Rename to OpenOtter & v0.10.0 Release

- **Context:** Formalizing the project identity and synchronizing versions across all components.
- **What we built/tested:** Renamed the project from \"Metabot\" to **OpenOtter**. Updated all `CHANGELOG.md` files, `VERSION` files, and git tags.
- **Issue observed:** Fragmented versioning and legacy naming across components (iOS, Raspberry Pi, STM32) made it difficult to track a unified release state.
- **Root cause:** Incremental development led to divergent version numbers and inconsistent project naming.
- **Resolution:** Performed a global search-and-replace for naming. Bumped iOS to `v0.10.0`, Raspberry Pi MCP to `v0.4.0`, and STM32 MCP to `v0.3.0`.
- **Validation:** Verified all component versions match the new release tags and branding is consistent in the TUI and iOS UI headers.
- **Follow-up:** Update remaining assets and documentation to reflect the new identity.

### 2026-04-05 - SpeechOutput AVSpeechSynthesizer Crash Fix & iOS 18.2 Audio Session Override

- **Context:** AVSpeechSynthesizer would not produce audio when running simultaneously with ARKit, and eventually entered a permanently silent state.
- **What we built/tested:** (1) Replaced the persistent `AVSpeechSynthesizer` with a fresh instance per utterance. (2) Moved `AVAudioSession` configuration into the `speak()` method itself. (3) Stripped emoji/invisible variation-selectors (U+FE0F) from Telegram aliases via ASCII-only filtering.
- **Issue observed:** (1) `AVSpeechSynthesizer` went completely silent after overlapping `stopSpeaking(at: .immediate)` cycles. (2) ARKit silently overrode the audio session category, cutting off TTS.
- **Root cause:** Native iOS bug in `AVSpeechSynthesizer` state-machine recovery. ARKit steals the audio category on initialization.
- **Resolution:** Creating a fresh `AVSpeechSynthesizer` per request completely avoids the stuck-state bug. Applying `AVAudioSession.sharedInstance().setCategory(.playback)` instantly *before* each utterance dynamically re-asserts control over ARKit. Restored `0.92` rate for the correct "Premium Voice" delivery pacing.
- **Validation:** Triggered commands via tap buttons ("🚗 Drive", "🅿️ Park"). App audio speaks the mapped short alias "Drive" and "Park" via the iOS neural quality voice.
- **Follow-up:** Full-scale field tests with remote Telegram operation.

### 2026-04-05 - Telegram Gateway Networking MainActor Leak

- **Context:** The app briefly stalled the UI whenever a Telegram message was sent, despite the use of `Task`.
- **What we built/tested:** Switched `GatewayBridge`'s send response to `Task.detached`.
- **Issue observed:** UI thread stutter when replying to heavy command streams.
- **Root cause:** The `TelegramGatewayDelegate` was called from inside a `MainActor.run` block from the gateway's poll loop. `Task { ... }` inherits its lexical context (MainActor), meaning the `sendReply` network request was mistakenly running on the main UI thread.
- **Resolution:** Changed `Task` to `Task.detached` to break the MainActor inheritance and push the HTTP networking back to the cooperative background pool.
- **Validation:** Long-running send requests no longer block `SelfDrivingView` app updates.
- **Follow-up:** None.

### 2026-04-05 - Agent Runtime Main-Thread Data Race Fix

- **Context:** AgentRuntime was freezing and crashing the app when Telegram commands were received.
- **What we built/tested:** Dispatched `orchestrator.tick()` entirely to the Main thread.
- **Issue observed:** `orchestrator.tick()` ran on the ARKit `frameQueue` (background) while `orchestrator.setGoal()` was called synchronously from the Telegram Gateway on `MainActor`. This caused data races mutating `@Published` state.
- **Root cause:** Concurrent access to planner objects from two threads without actors or locks.
- **Resolution:** Modified `runControlLoop()` to wrap the entire `tick()` inside `DispatchQueue.main.async`, serializing all planner state mutations on the main thread alongside UI and Telegram interactions.
- **Validation:** Deployed via `build.sh deploy`. Sent spam commands from Telegram while self-driving was active; no UI freezes or crashes occurred.
- **Follow-up:** None.

### 2026-04-05 - Agent Runtime & Telegram Gateway Design

- **Context:** Enabling remote control of the car from a second phone without building a separate app or webpage.
- **What we designed:** An OpenClaw-inspired Agent Runtime architecture inside the openotter-ios app. A Telegram bot (long polling via URLSession, no third-party dependencies) receives commands, a swappable `CommandInterpreter` protocol parses them (keyword matching in v1, LLM in the future), an `ActionDispatcher` routes actions through the existing `PlannerOrchestrator` and `SafetySupervisor`, and `SpeechOutput` (AVSpeechSynthesizer) speaks confirmations aloud. Stub interfaces for `SkillRegistry` and `MemoryStore` are included for future AI agent capabilities.
- **Key decisions:** (1) No arm/disarm — the system is always under software control. (2) Telegram chosen over custom app/webpage for zero-infrastructure remote control. (3) Long polling (30s timeout, back-to-back) over webhooks to avoid needing a server. (4) Bot token in iOS Keychain, never in source. (5) Chat ID whitelist for authorization. (6) Standalone `AgentDebugView` for isolated subsystem testing before integration.
- **Design spec:** `docs/superpowers/specs/2026-04-05-agent-runtime-telegram-design.md`
- **Follow-up:** Implement the Agent subsystem following the phased integration plan (isolated dev → Telegram → App Core wiring → HomeView entry).

### 2026-03-31 - End-to-End Self-Driving & Safety (v0.8.0)

- **Context:** Ensuring long-term reliability of the autonomous navigation logic and preventing stop-go oscillation during obstacle approach.
- **What we built/tested:** Redesigned the `SafetySupervisor` into a tri-zone state machine (CLEAR, CAUTION, BRAKE) with latched speed thresholds and asymmetric EMA filtering. Added a throttle ramp to the `ConstantSpeedPlanner`. Implemented a comprehensive 56-test XCTest suite covering all planner and safety invariants, including end-to-end mission scenarios.
- **Issue observed:** The previous binary safety policy (0/1) caused severe stop-go oscillation because braking caused the speed-dependent safety threshold to shrink, which immediately released the brake.
- **Root cause:** Feedback loop between the control output (braking) and the safety threshold calculation (which used current speed).
- **Resolution:** Introduced latched speed (thresholds lock when entering a safety zone), cooldown timers to prevent rapid toggling, and a CAUTION zone for smooth deceleration before full braking.
- **Validation:** All 73 tests currently pass (`./build.sh test`). Integration tests specifically simulate the wall approach scenario to ensure a single state transition to BRAKE without bouncing.
- **Follow-up:** Conduct physical field testing on the vehicle to measure tuning parameters (EMA alpha, ramp rate, CAUTION scaling) against real-world sensor noise.

### 2026-03-29 - Planner Framework & Safety Supervisor (v0.7.0)

- **Context:** Implementing the first autonomous driving logic on top of the 10Hz control loop.
- **What we built/tested:** Created a flexible `PlannerProtocol`, `PlannerContext`, and `PlannerOrchestrator`. Implemented `WaypointPlanner` for straight-line target following with proportional heading control. Added `SafetySupervisor` to sample center-pixel LiDAR depth and compute a Time-to-Collision (TTC). If TTC drops below 1.0s at an assumed 2m/s speed, an emergency brake override is triggered with an audible alarm.
- **Issue observed:** Need a way to inject new planners without modifying the orchestrator or ViewModels, and a way to guarantee safety overrides always preempt the active planner.
- **Resolution:** Decoupled planning from safety. The orchestrator asks the planner for a command, then passes that command and context to the safety supervisor for potential overriding.
- **Validation:** Tested safety module triggering with 2m/s assumed speed. The emergency brake overlay and alarm activate correctly at the TTC distance limit.
- **Follow-up:** Test the waypoint following logic with the physical vehicle and tune the steering and speed parameters.

### 2026-03-29 - Self Driving Mode UI Reorganization

- **Context:** Orchestrating ARKit, ESC BLE, and STM32 BLE subsystems into a unified Self Driving mode.
- **What we built/tested:** Created `SelfDrivingViewModel` to manage the lifecycle and control loop (10Hz) of all three subsystems simultaneously. Built `SelfDrivingView` to provide a unified cockpit with a real-time trajectory map, telemetry HUD, and actuation status. Extracted shared UI components (`ControlSlider`, `MetricRow`, `PoseMapView`) into a common file. Reorganized the main `HomeView` into two clear paths: "Self Driving" and "Diagnostics & Debug".
- **Issue observed:** Code duplication in UI components and lack of a centralized orchestrator for the final autonomous control loop.
- **Resolution:** Applied DRY principles by creating `CommonViews.swift` and `PoseMapView.swift`. Implemented a `simplePlanner` placeholder in the new orchestrator.
- **Validation:** Built and deployed the iOS app successfully. The new UI displays the separated paths and the autonomous mode view compiles with simultaneous subsystem bindings.
- **Follow-up:** Implement actual path following and obstacle avoidance logic in the `simplePlanner`.

### 2026-03-28 - STM32 BLE Initialization Fix (Multiple Root Causes Resolved)

- **Context:** Transitioning low-level control from Arduino to STM32L475 (B-L475E-IOT01A) and enabling BLE command reception directly from the iPhone via the SPBTLE-RF (BlueNRG-MS) module.
- **Root causes identified and fixed:**
  1. **Missing HCI transport layer init:** `BLE_InitStack()` only called `SVCCTL_Init()`, which sends HCI commands to the BlueNRG chip. But the SPI transport layer (`TL_BLE_HCI_Init` → `HW_BNRG_Init`) was never called first. The first HCI command hung forever waiting for a response from an uninitialized chip. **Fix:** Added `TL_BLE_HCI_Init(TL_BLE_HCI_InitFull, ...)` before `SVCCTL_Init()`.
  2. **SPI3 initialization conflict:** CubeMX-generated `MX_SPI3_Init()` configured SPI3 with `SPI_DATASIZE_4BIT` (for ISM43362 WiFi). The BLE middleware's `hw_spi.c` owns SPI3 and needs 8-bit mode with DMA. **Fix:** Removed `MX_SPI3_Init()` entirely — `hw_spi.c` handles all SPI3 setup.
  3. **Missing RTC backup domain reset:** On pin-reset, stale RTC wakeup configuration from a previous run could hang the Timer Server. The reference P2P_LedButton example resets the backup domain on PINRST. **Fix:** Added `LL_RCC_ForceBackupDomainReset()` sequence in `main()`.
  4. **Missing DMA IRQ handlers:** The BLE SPI driver uses DMA2 channels 1 and 2 but the IRQ handlers were missing from `stm32l4xx_it.c`. **Fix:** Added `DMA2_Channel1_IRQHandler` and `DMA2_Channel2_IRQHandler`.
  5. **RTC_WKUP_IRQHandler not clearing flags:** Called `HW_TS_RTC_Wakeup_Handler()` directly without clearing EXTI/RTC flags. **Fix:** Route through `HAL_RTCEx_WakeUpTimerIRQHandler()` which clears flags, then the `HAL_RTCEx_WakeUpTimerEventCallback` calls the Timer Server.
  6. **BLE advertising missing service UUID:** iOS couldn't discover by service UUID. **Fix:** Added `AD_TYPE_16_BIT_SERV_UUID_CMPLT_LIST` to advertising data.
- **Validation:** Firmware builds cleanly (40KB flash, 6KB RAM). Flash and test with nRF Connect / iOS app.

### 2026-03-28 - STM32 BLE Reconnect Fix (Cached GAP Name Mismatch)

- **Context:** The iOS app connected once, then stayed in scanning mode on reconnect while nRF Connect still saw the peripheral.
- **Root cause:** BlueNRG still exposed the GAP device name as `BlueNRG` with a 7-byte characteristic, so iOS cached the wrong peripheral name after the first connection and the scanner filtered out the device on subsequent runs.
- **Resolution:** Renamed the GAP device to `OPENOTTER-MCP`, expanded the GAP device-name length, updated the iOS scanner to match both cached and advertising names, and rebuilt/flashed the firmware.
- **Validation:** Firmware rebuilt successfully and the iOS reconnect path now accepts the STM32 peripheral again.

### 2026-03-27 - STM32 BLE Advertising Debugging & Initialization Root Causes (Superseded)

- **Context:** Initial debugging session — see entry above for resolution.
- **Issue observed:** The STM32 firmware successfully built and flashed, but the BLE device "OPENOTTER-MCP" never appeared on nRF Connect or iOS. Adding a heartbeat LED in the main loop confirmed the main loop was entirely frozen.
- **Root cause:** Multiple initialization issues (see 2026-03-28 entry above).

### 2026-03-27 - STM32 Firmware Target Setup

- **Context:** Establishing a robust, command-line-buildable firmware foundation for the STM32L475 target using STM32CubeCLT.
- **What we built/tested:** Created `firmware/stm32-mcp` using STM32CubeMX. Authored a comprehensive `build.sh` script to wrap CMake configuration, Ninja builds, `.bin`/`.hex` artifact generation, and flashing via `STM32_Programmer_CLI`. Added Git LFS tracking for the large STM32 HAL Drivers.
- **Issue observed:** IDE-dependent workflows (like STM32CubeIDE) are difficult to integrate into an automated command-line CI/CD pipeline and go against the project's plain-text portability ethos.
- **Root cause:** Default ST tooling leans heavily toward monolithic Eclipse-based IDEs.
- **Resolution:** Leveraged the standalone STM32CubeCLT toolchain alongside the CMake generator in CubeMX.
- **Validation:** Successfully compiled `stm32-mcp.elf` and flashed the binary to the physical STM32L475 board via SWD using `./build.sh flash`.
- **Follow-up:** Begin porting low-level actuation and communication logic from the Arduino prototype to the STM32 HAL.

### 2026-03-27 - Direct iPhone-to-ESC BLE Telemetry Integration

- **Context:** Pivoting the ESC telemetry architecture to connect directly to the iPhone instead of routing through the Raspberry Pi.
- **What we built/tested:**
  - Ported the reverse-engineered Snail ESC BLE protocol logic from the macOS prototype (`esc_app.swift`) into a new `ESCBleManager` class within the iOS app.
  - Added Combine `@Published` properties for real-time `ESCTelemetry` updates (RPM, voltage, temperatures, message count, and update frequency in Hz).
  - Integrated `ESCBleManager` into `MCPTestViewModel` to manage the BLE connection lifecycle alongside the UDP socket.
  - Enhanced the `MCPTestView` UI with an "ESC TELEMETRY" dashboard card to visualize the live data streams.
  - Fixed a timing bug where the initial handshake was sent before the notification stream was confirmed active.
  - Corrected the voltage parsing scale factor (from `/ 100.0` to `/ 10.0`).
- **Issue observed:** The initial implementation successfully connected but failed to receive data because the handshake burst was sent before the ESC confirmed `isNotifying = true`. The voltage reading was also off by a factor of 10.
- **Root cause:** Asynchronous BLE state machine assumptions vs the ESC's strict wait-for-ack requirement.
- **Resolution:** Updated `peripheral(_:didUpdateNotificationStateFor:error:)` to act as the trigger for the handshake sequence. Updated the voltage division math based on observed physical data.
- **Validation:** Deployed iOS app v0.5.0 to the iPhone. The UI successfully connects to `ESDM_4181FB`, completes the handshake, and streams valid RPM and voltage data at measurable frequencies.
- **Follow-up:** Pass the validated RPM data into the `VehicleState` object to be used as feedback for the upcoming speed planner and control loop.

### 2026-03-27 - ESC Telemetry Prototype Cleanup and Documentation

- **Context:** Finalizing the macOS BLE scanner prototype for reverse-engineering.
- **What we built/tested:**
  - Cleaned up `prototypes/esc_telemetry/` by removing legacy Python and shell scripts.
  - Retained the macOS Swift application (`ESCScanner.app`), core logic (`esc_app.swift`), and build scaffolding.
  - Added a dedicated `README.md` for the prototype and updated the main project documentation.
  - Committed the cleaned-up source and configuration to the repository.
- **Issue observed:** The directory was cluttered with untracked experiments and non-functional scripts.
- **Resolution:** Surgical removal of non-essential files while preserving the XcodeGen-based build path.
- **Validation:** `build.sh` still correctly generates and builds the macOS application.
- **Follow-up:** Use the macOS tool to finalize the protocol decoding before porting the logic to the Raspberry Pi.

### 2026-03-24 - ESC Bluetooth Telemetry Reverse Engineering

- **Context:** Attempting to read real-time velocity telemetry from the Snail ESC via Bluetooth (BLE) to be used by the Raspberry Pi.
- **What we built/tested:**
  - Iterated through Python `bleak` scripts on macOS and Raspberry Pi to discover the ESC (`ESDM_4181FB`).
  - Pivoted to a native Swift `CoreBluetooth` macOS app due to Linux/BlueZ stability and timeout issues.
  - Decompiled the official Android APK (`Snail ESC`) using `jadx` to reverse-engineer the proprietary BLE protocol.
  - Extracted the exact Service (`AE3A`), Write Characteristic (`AE3B`), Notify Characteristic (`AE3C`), and the payload parsing logic (extracting Duty Cycle, Voltage, Temp, and RPM).
  - Implemented an automated polling script sending the discovered initialization and heartbeat bytes (e.g., `[0x45, 0x05, 0x04, 0x01]` and `[0x45, 0x04, 0x04, 0x00]`) to the `AE3B` characteristic.
- **Issue observed:** The ESC successfully connects and accepts the characteristic subscriptions, but it does not return any telemetry data on the `AE3C` notify channel in response to our polling commands.
- **Root cause:** The exact handshake sequence, state machine timing, or a hidden packet checksum requirement is still not perfectly matched with the official app's behavior. The ESC remains silent.
- **Resolution:** Documented the extracted protocol characteristics and parsing logic. Paused the reverse engineering effort.
- **Follow-up:** Future options are to perform a direct Bluetooth HCI Snoop on an Android device to capture the exact raw byte sequence sent by the official app, or to bypass the ESC entirely and use ARKit VIO for velocity estimation.

### 2026-03-24 - ESC Telemetry Probe Harness

- **Context:** Refining the macOS CoreBluetooth probe after the APK reverse engineering revealed two packet families.
- **What we built/tested:** Updated `prototypes/esc_telemetry/esc_app.swift` to wait for the AE3C notification ack before writing, then sequentially probe the APK-derived `0x02` and `0x45` families with repeated init and poll commands.
- **Issue observed:** The previous script wrote immediately after enabling notify and only exercised the legacy `0x45` packets.
- **Root cause:** The harness did not mirror the APK's startup burst and did not distinguish CCCD write acknowledgements from telemetry notifications.
- **Resolution:** Centralized packet generation for both families, added `didWriteValueFor` and `didUpdateNotificationStateFor` logging, and delayed writes until notifications are active.
- **Validation:** `swiftc -framework CoreBluetooth -framework Foundation prototypes/esc_telemetry/esc_app.swift -o /tmp/esc_app_probe` succeeds on macOS.
- **Follow-up:** Run on the physical ESC and capture which family, if either, produces live telemetry frames.

### 2026-03-24 - ESC Scanner macOS App Target

- **Context:** Packaging the BLE probe as a proper Finder-launchable macOS app while preserving the command-line probe path.
- **What we built/tested:** Added `prototypes/esc_telemetry/project.yml`, generated `ESCScanner.xcodeproj`, and split the top-level launcher into `main.swift` so `esc_app.swift` can be shared by both the app target and the CLI probe.
- **Issue observed:** Xcode app targets reject top-level executable statements even when wrapped in conditional compilation.
- **Root cause:** The shared probe file still contained a run loop entry point, which is valid for `swiftc` but invalid inside a macOS application target.
- **Resolution:** Moved the executable entry point into `main.swift`, kept `esc_app.swift` as shared BLE logic, and added a SwiftUI window that streams logs from the monitor.
- **Validation:** `xcodebuild -project ESCScanner.xcodeproj -scheme ESCScanner -configuration Debug build` succeeds; `swiftc -framework CoreBluetooth -framework Foundation prototypes/esc_telemetry/esc_app.swift prototypes/esc_telemetry/main.swift -o /tmp/esc_app_probe` also succeeds.
- **Follow-up:** Launch the built `ESCScanner.app` from Xcode or Finder and test the ESC handshake families on hardware.

### 2026-03-24 - ESC Scanner Stable Output Folder

- **Context:** Making the macOS app easy to launch from Finder after each build.
- **What we built/tested:** Added `prototypes/esc_telemetry/build.sh` plus a local `.gitignore` so the app bundle is copied into `prototypes/esc_telemetry/Build/ESCScanner.app`.
- **Issue observed:** Xcode's default build output lives in DerivedData and is not convenient for repeated Finder launches.
- **Root cause:** The product bundle path changes with build configuration and DerivedData state.
- **Resolution:** The helper script now builds with a fixed derived-data path, copies the finished app bundle into a visible `Build/` directory, and exposes `launch` and `open` commands.
- **Validation:** Running `prototypes/esc_telemetry/build.sh build` succeeds and prints `Copied app to .../prototypes/esc_telemetry/Build/ESCScanner.app`.
- **Follow-up:** Use `prototypes/esc_telemetry/build.sh launch` when you want an automatic build-and-open workflow.

### 2026-03-24 - Per-Speed Telemetry Log Labeling

- **Context:** Preparing repeated motor-speed capture runs for payload decoding.
- **What we built/tested:** Added session-label parsing to the shared ESC probe and wired `build.sh` to pass `--session-label` into the app launch.
- **Issue observed:** A single fixed log file makes it hard to compare telemetry across different commanded motor speeds.
- **Root cause:** The logger previously wrote only to one global path and did not distinguish capture sessions.
- **Resolution:** Logger now writes labeled runs into `~/esc_telemetry_runs/<timestamp>_<label>.log`, with `build.sh launch --session-label <label>` as the repeatable entry point.
- **Validation:** Both `swiftc -framework CoreBluetooth -framework Foundation prototypes/esc_telemetry/esc_app.swift prototypes/esc_telemetry/main.swift -o /tmp/esc_app_probe` and `xcodebuild -project ESCScanner.xcodeproj -scheme ESCScanner -configuration Debug build` succeed after the update.
- **Follow-up:** Capture one labeled log per motor speed step so the frame fields can be correlated with speed.

### 2026-03-24 - Session Label Argument Parsing Fix

- **Context:** Verifying the per-speed logging workflow after noticing unlabeled runs were still being written to the default file.
- **What we built/tested:** Fixed `prototypes/esc_telemetry/build.sh` so `--session-label` is parsed regardless of whether it appears before or after the command (`launch`, `build`, etc.).
- **Issue observed:** `build.sh launch --session-label speed_1000` did not forward the label because the parser stopped once it hit the command token.
- **Root cause:** The command parser broke out of option scanning too early, so post-command options were ignored.
- **Resolution:** Kept scanning after the command token and added a missing-value guard for `--session-label`.
- **Validation:** `bash -n prototypes/esc_telemetry/build.sh` succeeds after the change.
- **Follow-up:** Use either `build.sh --session-label speed_1000 launch` or `build.sh launch --session-label speed_1000`; both are now accepted.

### 2026-03-24 - Logger Startup Timing Fix

- **Context:** The labeled runs directory existed but remained empty after launch.
- **What we built/tested:** Moved `Logger.configure(sessionLabel:)` into `ESCScannerApp.init()` so the session file is created before SwiftUI constructs the first view.
- **Issue observed:** The old setup depended on `ESCScannerViewModel.init()`, which was too late to guarantee the session file existed when the app launched.
- **Root cause:** Launch order made the logger initialization path ambiguous, and the labeled app process could start before the view model had a chance to configure file output.
- **Resolution:** Centralized session-file setup at app startup, kept the direct executable launcher, and verified the app now creates `~/esc_telemetry_runs/<timestamp>_<label>.log` on launch.
- **Validation:** A fresh `rpm_762` run created `~/esc_telemetry_runs/20260324_224427_rpm_762.log`.
- **Follow-up:** Use one run per motor-speed step and keep the label matched to the commanded speed.

### 2026-03-23 - MVP1 Step 6: ARKit World Map Management and Accuracy Tuning

- **Context:** Enhancing ARKit pose stability with persistence and drift correction.
- **What we built/tested:** Implemented `MapManagerView` and metadata storage for named ARWorldMaps. Refined `ARKitPoseViewModel` with a dedicated high-priority delegate queue and gimbal-safe yaw extraction (using `atan2`).
- **Issue observed:** (1) Gimbal lock and ±π discontinuity in previous Euler-angle yaw extraction caused trajectory "snaps". (2) UI contention periodically caused `session(_:didUpdate:)` to drop frames.
- **Root cause:** (1) Improper use of Euler angles instead of quaternion-derived or matrix-based orientation extraction. (2) Heavy rendering tasks on the main thread blocked the ARSession delegate callbacks.
- **Resolution:** (1) Rewrote yaw extraction to use `atan2(-R.31, R.33)` from the transform matrix, plus a π offset correction for gimbal-safe behavior. (2) Moved ARKit processing to a high-priority background serial queue.
- **Validation:** Trajectory visualization is perfectly smooth during full 360-degree rotations. World map save/load successfully relocalizes the robot within 1-2cm of previous start points.
- **Follow-up:** Begin integration of ESC Bluetooth telemetry on the Raspberry Pi.

### 2026-03-23 - MVP1 Step 5: Architectural Refactoring for Testability (SRP/DIP)

- **Context:** Improving the maintainability and testability of the legacy Raspberry Pi WiFi bridge and iPhone network layers.
- **What we built/tested:** Decomposed monolithic ViewModels into transport (`MCPConnection`), protocol logic (`MCPProtocol`), and state management. Implemented full unit test coverage for the network protocol on both iOS (XCTest) and MCP (GoogleTest).
- **Issue observed:** Protocol bugs were hard to debug across the Wi-Fi link without a hardware-in-the-loop setup.
- **Root cause:** Protocol parsing logic was tightly coupled to networking and UI code.
- **Resolution:** Applied the Dependency Inversion Principle (DIP). Moved pure parsing logic into isolated, side-effect-free modules that can be tested in isolation.
- **Validation:** 18 new GoogleTest cases and comprehensive XCTest suite passing on local development machines (macOS).
- **Follow-up:** Keep protocol logic isolated as new telemetry fields (ESC speed) are added.

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
  - **Velocity**: Use the legacy Raspberry Pi WiFi bridge to connect to the ESC via Bluetooth for direct RPM/speed telemetry.
  - **New Task**: Add `ARKitPoseView` to the iOS app to validate tracking stability before planner integration.
- **Validation:** N/A (Research and Plan update).
- **Follow-up:** Implement `ARKitPoseView` and establish legacy Raspberry Pi WiFi <-> ESC Bluetooth communication.

### 2026-03-20 - MVP1 Step 3: Pi serial bridge + Arduino actuation path

- **Context:** Legacy Raspberry Pi WiFi bridge and Arduino firmware for low-level actuation.
- **What we built/tested:** Implemented USB serial forwarding from the Pi to the Arduino with automatic reconnect, 3.5-second boot sync, serial buffer flushing, and ACK feedback in the dashboard. The Arduino firmware accepts normalized steering/motor commands and maps them to servo and ESC outputs.
- **Issue observed:** The firmware README described timeout neutralization, but the sketch only logs a warning when no command arrives.
- **Root cause:** `neutralize()` is intentionally commented out in the sketch for debugging.
- **Resolution:** Updated the firmware README to match the current warning-only timeout behavior.
- **Validation:** The implemented protocol and timeout behavior are reflected in `firmware/raspberry-pi-mcp/README.md` and `firmware/openotter-arduino/openotter-arduino.ino`.
- **Follow-up:** Revisit timeout neutralization before vehicle-level driving tests.

### 2026-03-19 - MVP1 Step 2: Raspberry Pi MCP Bridge and iOS Diagnostics UI

- **Context:** Transition from STM32 direct-control work to the legacy Raspberry Pi 4B + Arduino architecture for motor control.
- **What we built/tested:**
  - Developed `raspberry-pi-mcp`: a C++17 application on Raspberry Pi using `Asio` for event-driven UDP networking and `FTXUI` for a TUI dashboard.
  - Implemented bi-directional UDP heartbeats (1Hz) between iPhone and Pi with a synchronized 1.5-second connection timeout.
  - Built a car-style TUI on the Pi with stationary, bi-directional meters for steering/motor power (Blue/Left for negative, Green/Right for positive).
  - Added "Raspberry Pi WiFi" view on iOS with real-time status, network metrics (Sent/Received counts/times), and manual sliders for remote control.
  - Fixed iOS IP discovery and macOS-specific API build issues.
- **Issue observed:** (1) Layout jitter in TUI when meters were growing dynamically. (2) Heartbeat RX counter on Pi was erroneously counting control commands. (3) iOS build error on `Host.current().localizedName`.
- **Root cause:** (1) Flexible-width elements caused the center point to shift; fixed with explicit container sizing. (2) Packet parsing didn't distinguish by prefix; fixed with `hb_iphone:`/`cmd:` separation. (3) `Host` API is macOS-only; replaced with `UIDevice`.
- **Resolution:** Refined TUI layout for absolute stability, hardened packet parsing, and implemented iOS device discovery using UIKit.
- **Validation:** Smooth, jitter-free dashboard on Pi; iPhone shows "Connected" status based on Pi heartbeats; 1.5s timeout works bi-directionally.
- **Follow-up:** Next is vehicle validation of the Pi serial bridge, Arduino timeout policy, and planner/control integration.

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
