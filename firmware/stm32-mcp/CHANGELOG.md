# Changelog

All notable changes to this project will be documented in this file.
<!-- markdownlint-disable MD024 -->

## [0.4.0] - 2026-04-23

### Added
- **Reverse Safety Supervisor (`rev_safety`)**: HAL-free C11 module implementing the speed-dependent critical-distance formula (exact stopping-distance integral with linear-drag model), EMA depth smoothing, invalid-frame / ToF-blind policy (2 consecutive invalid frames → BRAKE), frame-gap watchdog (500 ms), operator forward-command release, and debounced clearance release (300 ms hold). Full host-unit-test suite (`tests/host/test_rev_safety.c`).
- **0xFE43 Safety Characteristic**: New 20-byte notify + read GATT characteristic under the existing 0xFE40 service. Pushes state transitions and 1 Hz refresh while braking.
- **0xFE44 Mode Characteristic**: New 1-byte write + read characteristic for Drive (0) / Debug (1) mode selection. Defaults to Drive on power-on and reverts to Drive on BLE disconnect.
- **Deferred PWM Arbitration**: PWM is now computed in `BLE_App_Process` (main-loop tick) rather than the BLE event handler, enabling the supervisor to intercept reverse commands before they reach the ESC.
- **`TOF_L1_ERR_LOCKED_IN_DRIVE` Status Code**: Added to `TofL1_Status_t` (value 11); returned when a 0xFE61 config write is rejected because Drive mode is active.
- **Bringup Checklist**: `docs/dev/07-reverse-safety-bringup.md` documents 8 on-target HIL verification steps.

### Changed
- **`0xFE41` Command Payload 4 → 6 bytes**: Added `int16_t velocity_mm_per_s` field (bytes 4-5, signed little-endian). iOS clients using the old 4-byte form continue to work (firmware accepts `data_length >= 6`; shorter writes are silently ignored by the 6-byte guard).
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
