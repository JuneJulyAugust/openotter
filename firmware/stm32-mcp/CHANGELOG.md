# Changelog

All notable changes to this project will be documented in this file.
<!-- markdownlint-disable MD024 -->

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
