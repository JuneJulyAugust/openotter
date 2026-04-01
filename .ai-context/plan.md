# metalbot Plan

This file defines the stable system contract. `task.md` tracks unfinished work, and `walkthrough.md` records implementation evidence.

## 1. Architecture Snapshot

- Primary path: iPhone app -> STM32 control board -> vehicle hardware.
- The iPhone owns perception, estimation, planning, and the operator UI.
- The STM32 owns low-latency command intake, watchdog behavior, and PWM actuation.
- ESC telemetry returns directly to the iPhone over BLE.
- Legacy path: Raspberry Pi WiFi bridge -> Arduino actuation path.
- The legacy bridge stays in the repo for compatibility, bench testing, and transition support.

## 2. MVP1

### 2.1 Goal

- Drive straight, hold target speed, and stop safely when the path is blocked or the control link becomes stale.

### 2.2 System Shape

- Perception runs on the iPhone and uses LiDAR plus RGB to understand the environment.
- Pose and telemetry stay on the iPhone side so the planner sees one coherent state snapshot.
- The STM32 acts as the primary low-level controller and should remain simple, deterministic, and easy to recover.
- Safety overrides motion: stop signals and estop always outrank normal drive commands.
- The legacy Raspberry Pi WiFi bridge remains available while the STM32 path is validated on vehicle hardware.

### 2.3 Operating Assumptions

- Indoor flat floor.
- Repeatable launch and reconnect behavior.
- Minimal operator intervention during a run.
- Safe stop behavior when sensor data or link health becomes stale.

### 2.4 MVP1 Success Definition (Achieved: v0.8.0)

- The vehicle can hold a target speed on a flat indoor floor. (Done)
- The vehicle can stay approximately straight using heading hold. (Done)
- The vehicle stops before obstacles under a configurable policy. (Done)
- The system performs a safe stop on stale LiDAR data or control-link timeout. (Done)

## 3. Product Direction

- MVP1: LiDAR-first closed loop on the STM32 path.
- MVP2: RGB-to-mono-depth prototype on iPhone.
- MVP3: sparse LiDAR + RGB depth completion.

## 4. Naming

- Use `STM32 control board` and `STM32 direct BLE control` for the primary path.
- Use `Raspberry Pi WiFi bridge` for the legacy bridge.
- Use `legacy Pi + Arduino path` when the historical serial bridge is the point of the note.
- Reserve `MCP` for code namespaces, BLE device names, and historical log entries.

## 5. Invariants

- Sensor, command, and telemetry timestamps are monotonic.
- Safety overrides performance.
- Core math stays deterministic and testable.
- Transport, protocol, and UI stay separated.
- Coordinate transforms are explicit and validated.
- MVP scope stays narrow until the current milestone is closed.

## 6. Current Interfaces

- iPhone -> STM32 BLE: primary drive and telemetry path.
- iPhone -> Raspberry Pi WiFi -> Arduino serial: compatibility bridge.
- ESC -> iPhone BLE: direct telemetry feed.
