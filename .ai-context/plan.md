# openotter Plan

This file defines the stable system contract. `task.md` tracks unfinished work, and `walkthrough.md` records implementation evidence.

## 1. Architecture Snapshot

- Primary path: iPhone app -> STM32 control board -> vehicle hardware.
- The iPhone owns perception, estimation, planning, the operator UI, and the agent runtime.
- The STM32 owns low-latency command intake, watchdog behavior, and PWM actuation.
- ESC telemetry returns directly to the iPhone over BLE.
- Agent path: Telegram Bot API -> Agent Runtime -> PlannerOrchestrator -> SafetySupervisor -> STM32.
- The Agent Runtime is a new input source, not a new control path. All commands flow through the safety stack.
- Legacy path: Raspberry Pi WiFi bridge -> Arduino actuation path.
- The legacy bridge stays in the repo for compatibility, bench testing, and transition support.

## 2. MVP1

### 2.1 Goal

- Drive straight, hold target speed, and stop safely when the path is blocked or the control link becomes stale.
- Accept remote commands from Telegram and respond with voice and text, laying the foundation for a physical AI agent.

### 2.2 System Shape

- Perception runs on the iPhone and uses LiDAR plus RGB to understand the environment.
- Pose and telemetry stay on the iPhone side so the planner sees one coherent state snapshot.
- The STM32 acts as the primary low-level controller and should remain simple, deterministic, and easy to recover.
- Safety overrides motion: stop signals and estop always outrank normal drive commands.
- The Agent Runtime receives commands from Telegram, interprets them, and dispatches through the existing planner/safety stack. It is a new input source, not a new control path.
- The legacy Raspberry Pi WiFi bridge remains available while the STM32 path is validated on vehicle hardware.

### 2.3 Operating Assumptions

- Indoor flat floor.
- Repeatable launch and reconnect behavior.
- Minimal operator intervention during a run.
- Safe stop behavior when sensor data or link health becomes stale.
- Both phones (operator and car) have internet connectivity (WiFi or cellular).
- The openotter app is always running in the foreground on the car's iPhone.

### 2.4 MVP1 Success Definition

#### 2.4.1 Autonomous Driving (Achieved: v0.8.0)

- The vehicle can hold a target speed on a flat indoor floor. (Done)
- The vehicle can stay approximately straight using heading hold. (Done)
- The vehicle stops before obstacles under a configurable policy. (Done)
- The system performs a safe stop on stale LiDAR data or control-link timeout. (Done)

#### 2.4.2 Agent Runtime & Telegram Control (Achieved: v1.0.0)

- The app receives commands from a Telegram bot via long polling.
- Fixed command set (forward, backward, stop, status) dispatches through the planner/safety stack.
- The app speaks command confirmations and status aloud via TTS.
- The app replies to Telegram with the result text.
- A standalone AgentDebugView allows isolated testing of the agent subsystem.
- Bot token is stored securely in the iOS Keychain.
- Stub interfaces exist for future LLM interpreter, skill registry, and memory store.

### 2.5 Current Release Candidate (v1.2.0)

- The project was formally rebranded to OpenOtter on 2026-04-16.
- Version 1.0.0 established the first complete iPhone + STM32 safety milestone: forward LiDAR safety, rear ToF firmware safety, Telegram Park/Drive control, Self Driving emergency UI parity, and repeatable simulator test workflow.
- Version 1.2.0 is prepared as a release candidate, not yet merged or tagged. It migrates the active STM32 ToF deployment path to SATEL-VL53L8, fixes the SATEL wiring contract, verifies live 4x4 firmware frames from one rear sensor on IOT01A1, updates iOS diagnostics plus rear ToF health presentation, implements adaptive rear/front runtime slots for a future second sensor on shared SPI1, and lets STM32 Control select the rear or front FE62 debug depth stream.
- The v1.2.0 hardware validation scope is now explicitly one rear SATEL-VL53L8. Two-sensor front/rear support remains code-ready, documented, and host/iOS tested where hardware-free, but physical front/two-SATEL verification is deferred until another SATEL board is available.
- User hardware E2E validation passed on 2026-06-08 after the VL53L8 range-trust fix. A later STM32-reset/iOS-reconnect case showed STM32 Control stuck in `Scanning` with `ToF BLE detached`; the 2026-06-09 fix adds firmware advertising refresh while disconnected and makes iOS wait for a fresh advertisement instead of a stale remembered peripheral. Live recheck showed the iOS STM32 Control view reconnecting and UART streaming FE62 frames with `fail=0`.
- The remaining release gating is PR CI/final smoke testing, then merge/tag `ios-v1.2.0` and `stm32-mcp-v1.2.0` when accepted.
- Final validation and resolved-bug details live in `docs/superpowers/specs/2026-06-08-vl53l8-v1.2-validation-and-bugs.md`.

## 3. Product Direction

- MVP1: LiDAR-first closed loop on the STM32 path + Telegram-based agent runtime.
- MVP2: RGB-to-mono-depth prototype on iPhone.
- MVP3: sparse LiDAR + RGB depth completion.
- Long-term: OpenClaw-inspired physical AI agent with LLM intent parsing, skill subsystem, and persistent memory. The user provides cloud LLM inference; no heavy on-device inference.

## 4. Naming

- Use `STM32 control board` and `STM32 direct BLE control` for the primary path.
- Use `Raspberry Pi WiFi bridge` for the legacy bridge.
- Use `legacy Pi + Arduino path` when the historical serial bridge is the point of the note.
- Reserve `MCP` for code namespaces, BLE device names, and historical log entries.

## 5. Invariants

- Sensor, command, and telemetry timestamps are monotonic.
- Safety overrides performance.
- SATEL-VL53L8 wiring is safety-critical: `EXT_5V0` receives 5V, `EXT_PWR_EN` receives 3V3, and `SPI_I2C_N` is tied low for I2C or high for SPI.
- Dual SATEL-VL53L8 wiring should share 5V, GND, SPI1 SCK/MOSI/MISO, and `SPI_I2C_N=3V3`, but use separate `NCS` and separate `LPn` lines. Firmware now probes rear/front runtime slots adaptively; shared I2C SCL/SDA remains only a fallback that requires deterministic address sequencing.
- Two-sensor SPI support is code-ready, not release-proven, until the second physical SATEL board is verified on shared SPI1 with independent `NCS`, `LPn`, and `GPIO1` wiring.
- Front/rear convention: `rear` is the backward-facing safety sensor and current one-sensor bench role; `front` is the forward-facing future second SATEL. FE61 byte 8 selects the debug stream role, and FE63 byte 3 reports selected role plus available-role mask.
- VL53L8 safety trusts only selected-zone statuses `5`, `6`, `9`, and `10` in `1..3800 mm`. Valid farther readings become capped clear space; non-OK statuses such as `2`, `4`, or `255` are degraded live data and must not feed the safety EMA or blind-frame counter.
- STM32 BLE event callbacks must remain bounded during reset/reconnect. FE61 writes may enqueue config, but VL53L8 init/config must run from the main loop after boot grace, mode checks, and any fresh FE41/FE44 app-handshake window.
- STM32 reset/reconnect debugging should separate firmware liveness from RF visibility. `BLE adv_active` plus VL53L8 frame logs means the firmware is alive and believes it is advertising; `BLE adv_refresh stop ok` / `BLE adv_reassert ok` plus an external scan seeing `OPENOTTER-MCP` FE40/FE60 is the stronger proof that iOS should be able to discover it.
- Firmware builds may run in a worktree sandbox, but flashing and UART log reads are host-device operations. In remote Codex sessions, do not keep retrying `./build.sh flash` after probe/permission failures; use explicit approval, a normal terminal, or the `/Volumes/DIS_L4IOT` mass-storage copy path documented in `firmware/stm32-mcp/docs/dev/13-firmware-deploy-and-uart.md`.
- Core math stays deterministic and testable.
- Transport, protocol, and UI stay separated.
- Coordinate transforms are explicit and validated.
- MVP scope stays narrow until the current milestone is closed.

## 6. Current Interfaces

- iPhone -> STM32 BLE: primary drive and telemetry path.
- iPhone -> Raspberry Pi WiFi -> Arduino serial: compatibility bridge.
- ESC -> iPhone BLE: direct telemetry feed.
- Telegram Bot API -> iPhone (HTTPS long poll): remote command input.
- iPhone -> Telegram Bot API (HTTPS): command response output.
- iPhone speaker (AVSpeechSynthesizer): voice feedback output.
