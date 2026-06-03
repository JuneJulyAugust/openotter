# Changelog

All notable changes to this project will be documented in this file.
<!-- markdownlint-disable MD024 -->

## [Unreleased]

### Added
- **Adaptive VL53L8 safety slots**: Firmware now supports rear and front VL53L8 runtime slots. A single rear sensor still enables reverse ToF safety, a single front sensor can enable forward ToF safety, and two sensors can run independently when both are available.
- **Directional safety projection tests**: Added host coverage for mapping front-sensor forward motion into the existing reverse-safety model without changing the core stopping-distance invariant.
- **VL53L8 debug role metadata**: FE61 now accepts a front/rear debug role byte, FE63 reports selected role plus available-slot mask, and host tests cover the packed status metadata.

### Changed
- **VL53L8 runtime driver**: Refactored the single VL53L8 runtime into rear/front slots. Rear probes I2C3 first, then SPI1 with D8 `NCS`; front probes SPI1 with D10 `NCS`.
- **Drive throttle arbitration**: Drive mode now clamps reverse throttle only when the rear safety context is braking, and clamps forward throttle only when the front safety context is braking.
- **ToF debug frame selection**: FE62 now streams the selected rear or front VL53L8 slot instead of always using the default available slot.

## [1.2.0] - 2026-06-02

### Added
- **SATEL-VL53L8 deployment path**: Added firmware design, implementation plan, and bring-up documentation for one SATEL-VL53L8 on B-L475E-IOT01A1 I2C3.
- **Two-sensor wiring plan**: Documented the future front/rear SATEL-VL53L8 topology with rear I2C3, front I2C1, shared power/mode wiring, and dedicated `LPn` lines for deterministic reset and recovery.
- **VL53L8 bring-up diagnostics**: Added UART frame summaries with measured frame cadence and compact 4x4 zone grids for hardware bring-up.
- **Firmware version file**: Added `VERSION` so STM32 release metadata has an explicit local source alongside the changelog.
- **Firmware test strategy**: Added a host-test and coverage workflow, an end-to-end VL53L8 verification checklist, and a pure two-sensor topology test; current HAL-free host coverage is 99.3% line coverage.

### Changed
- **Active ToF firmware path**: Migrated the active multizone driver, reverse-safety selector, BLE ToF config path, and host tests from VL53L5-facing names to VL53L8-facing names.
- **VL53L8 result payload**: Limited the ST driver output list to target count, distance, and target status so the 4x4 safety stream sustains about 30 Hz on I2C.
- **Vendor dependency import**: `fetch-deps.sh` now expects STSW-IMG040 via `--vl53l8cx-path` and no longer installs the deprecated VL53L1 driver.
- **Deployment deprecation**: VL53L0X, VL53L1CB, and VL53L5CX are now historical/deprecated for the deployment path; active target firmware uses SATEL-VL53L8.

### Fixed
- **SATEL Connector Pinout**: Corrected the bring-up documentation so `J2 pin 1 EXT_SPI_I2C_N` is tied to GND for I2C mode, `J2 pin 11 EXT_5V0` receives 5V, `J2 pin 7 EXT_PWR_EN` receives 3V3, and SDA uses `J2 pin 5 EXT_MOSI_SDA`.
- **BLE ToF health status**: `TOF_STATUS_IO` and `TOF_STATUS_DRIVER_MISSING` now map consistently to FE63 error state during VL53L8 config and safety-config enforcement.

## [1.1.0] - 2026-04-25

### Added
- **VL53L5CX Reverse Safety Supervisor**: VL53L5CX row-3 center zones (indices 9 and 10 of the 4×4 grid) now serve as the primary rear collision sensor in Drive mode; the supervisor computes a speed-dependent critical distance and latches BRAKE with cause, depth, and velocity snapshot.
- **BLE GATT Diagnostic Logging**: Explicit UART failure message on each `aci_gatt_add_char` call so slot-exhaustion errors are never silently swallowed. Restored 1 Hz `L5 dbg:` UART status line reporting frames-seen, snapshots, pushed/failed chunk counters, operating mode, and current scan rate.

### Fixed
- **FE40 GATT Slot Under-allocation (Critical)**: `Max_Attribute_Records` for the FE40 control service corrected from 10 → 11. The omitted slot caused `aci_gatt_add_char` for FE44 to fail silently, leaving the mode characteristic undiscoverable. iOS could not write the operating mode, firmware stayed in Drive mode, `BLE_Tof_FrameStreamAllowed` returned false, and no FE62 frame chunks were sent — depth map showed `chunks rx 0`. See `docs/dev/09-ble-gatt-slot-bug-postmortem.md`.
- **VL53L5CX target_status Whitelist (Critical)**: `rev_safety_l5.c` was copy-pasted from the VL53L1 path and reused the L1 valid-status whitelist `{0, 3, 6, 11}`. VL53L5CX assigns completely different semantics to those codes (0 = data not updated, 11 = consistency failed — both invalid). The actual valid statuses on L5 per ST UM2884 §5.5.6 are 5 (range valid) and 9 (range valid with large pulse), with 6 and 10 as valid-range variants. Every normal status=5 frame was counted as invalid, triggering `REV_SAFETY_CAUSE_TOF_BLIND` after 4 frames and producing a spurious rear emergency brake with no obstacle present.
- **VL53L5CX Boot Blocking BLE**: VL53L5CX initialization no longer stalls the BLE main loop during firmware startup.
- **VL53L5CX Config Re-apply on BLE Attach**: Safety config is resent to the sensor after STM32TofService attaches on reconnection.
- **ToF Debug Notifications Restored**: FE62 / FE63 notifications are re-enabled correctly after a debug-mode transition.

## [1.0.0] - 2026-04-24

### Added
- **Park Operating Mode**: Added a Park mode on 0xFE44 so the app can intentionally idle the vehicle and clear reverse safety state without leaving the firmware armed for reverse BRAKE evaluation.
- **Reverse Safety Notification Recovery**: Firmware safety notifications now support the app's Self Driving emergency panel with state, cause, distance, speed, critical distance, and timing details.

### Changed
- **Reverse Safety Margin Increased**: Increased the reverse stopping margin by 8 cm for a more conservative bumper gap during rear obstacle approaches.
- **Reset and Release Paths Hardened**: Reverse safety state now clears consistently when leaving BRAKE through explicit safe modes, forward escape motion, disconnect, and board reset paths.

### Fixed
- **Stationary BRAKE Re-triggering**: Reverse safety no longer treats an intentionally parked or zero-speed command as a reason to keep reasserting BRAKE from stale distance readings.
- **Late BRAKE Notifications**: Firmware/app state transitions now prevent stale reverse BRAKE notifications from keeping the iOS app in emergency state after Park.

## [0.4.0] - 2026-04-23

### Added
- **Reverse Safety Supervisor**: New HAL-free `rev_safety` module. Critical-distance policy mirrors the iOS forward supervisor (see `openotter-ios/Sources/Planner/Safety/DESIGN.md` §4). Center-zone 3×3 LONG 30 ms ToF feeds the supervisor; invalid-frame (2 consecutive) and frame-gap (500 ms) watchdogs fail-safe to BRAKE.
- **BLE Protocol**:
  - 0xFE41 command extended to 6 B (added `int16_t velocity_mm_per_s`).
  - 0xFE43 safety notify characteristic, 20 B payload with state, cause and trigger snapshot.
  - 0xFE44 mode characteristic (0 = Drive, 1 = Debug).
- **Operating Modes**: Drive (default, supervisor armed, ToF config locked, 0xFE62 suppressed) and Debug (supervisor disarmed, ToF config writable, 0xFE62 streamed).

### Changed
- **`0xFE41` Command Payload 4 → 6 bytes (breaking wire change)**: Added `int16_t velocity_mm_per_s` field (bytes 4-5, signed little-endian). The firmware now requires `data_length >= 6`; legacy 4-byte writes are silently dropped. Ship with iOS ≥ 0.12.0 together.
- `BLE_App_Process` now drives PWM after running the supervisor and applying the per-direction reverse clamp (§3.5 of the reverse-safety design doc).
- `ble_tof.c` rejects 0xFE61 writes in Drive mode with `TOF_L1_ERR_LOCKED_IN_DRIVE`.
- **`BLE_Tof_Process` Mode-Gated**: Frame notifications (0xFE62) are now suppressed in Drive mode to avoid saturating the BlueNRG-MS TX buffer and starving motor command writes. The ToF sensor continues scanning for the supervisor.
- **`apply_config_write` Mode-Gated**: Config writes (0xFE61) in Drive mode are now rejected with `TOF_L1_ERR_LOCKED_IN_DRIVE` to prevent accidental reconfiguration of the safety-critical sensor parameters.
- **`BLE_Tof_EnforceSafetyConfig` Added**: Applies the safety-critical config (3×3 LONG 30 ms) when the MCU transitions from Debug back to Drive.

## [0.3.1] - 2026-04-22

### Added
- **VL53L1CB Multi-Zone ToF**: Implemented native driver and scan engine for the VL53L1CB Time-of-Flight sensor.
- **ToF BLE GATT Service**: Added new 0xFE60 service to stream 8x8 multi-zone depth data over BLE to the host.
- **ATT MTU Chunking**: Implemented frame chunking for the 0xFE62 characteristic to support BlueNRG-MS's 23-byte ATT_MTU limit.
- **Robustness**: Added configuration validation and driver failure survival modes for the ToF sensor.

### Changed
- **Testing**: Added pure C host unit tests for the ROI builder (`TofL1_BuildRoi`).

## [0.3.0] - 2026-04-16


### Changed
- **Project Rename**: Updated BLE GAP name and advertising data to reflect OpenOtter branding.

## [0.2.1] - 2026-03-28

### Fixed

- Renamed the GAP device from `BlueNRG` to `OPENOTTER-MCP` and expanded the GAP name length so iOS caches the correct peripheral name.
- Kept BLE advertising and reconnect flow aligned with the iOS scanner so the direct-control screen can reconnect after the first session.

## [0.2.0] - 2026-03-28

### Added

- **BlueNRG-MS BLE middleware** integration via SPI3 (SPBTLE-RF module)
- Custom GATT Control Service (`0xFE40`) with command (`0xFE41`) and status (`0xFE42`) characteristics
- `ble_app.c` / `ble_app.h` — BLE application layer: stack init, GATT registration, command parsing, PWM actuation
- `ble_config.h` — Centralized BLE middleware configuration (scheduler, timer server, LPM, transport layer)
- `config.h` wrapper — Redirects middleware `#include "config.h"` to `ble_config.h`
- Compatibility shims: `BLE/ble_core/hal.h`, `BLE/ble_core/hal_types.h`
- Safety watchdog: 1.5s timeout resets steering/throttle to neutral on BLE disconnect
- `BLUENRG_MS=1` compile define for correct API selection

### Changed

- `CMakeLists.txt` — Added BLE_Middleware static library target with all middleware sources
- `stm32l4xx_hal_conf.h` — Enabled `HAL_RTC_MODULE_ENABLED` for BLE timer server
- `stm32l4xx_hal_msp.c` — Disabled CubeMX `HAL_SPI_MspInit` (superceded by `hw_spi.c`)

## [0.1.0] - 2026-03-27

### Added

- Initial creation of `stm32-mcp` firmware target using STM32CubeMX and STM32CubeCLT.
- Target device: STM32L475 (Cortex-M4 with FPU).
- `build.sh` script for unified configure, compile, and flash on macOS with `arm-none-eabi-gcc` toolchain.
- Debug and Release CMakePresets configuration.
- PWM output on TIM3: PB1 (CH4, steering), PB4 (CH1, throttle).
