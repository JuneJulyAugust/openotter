# stm32-mcp — Developer Documentation

This directory holds the long-form development documentation for the
`stm32-mcp` firmware on the **B-L475E-IOT01A** Discovery Kit. The project-
level `README.md` covers the high-level feature set and memory footprint;
these documents cover *how to work on the code*.

Read them in order the first time; after that each is self-contained.

| #  | Document                                                         | What it covers                                                                                              |
|----|------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------|
| 01 | [Toolchain and Build](01-toolchain-and-build.md)                 | Installing STM32CubeCLT on macOS, PATH setup, `build.sh` subcommands and environment variables.             |
| 02 | [Board Bringup](02-board-bringup.md)                             | Verifying the ST-Link probe, reading the on-board LEDs, BLE advertising check without the iOS app.          |
| 03 | [Architecture](03-architecture.md)                               | Source tree layout, boot sequence, cooperative scheduler, IRQ priorities, TIM3 / PWM pin map.               |
| 04 | [BLE Integration](04-ble-integration.md)                         | BlueNRG-MS stack on SPI3, GATT service definition, full connection flow, STM32CubeL4 source lineage.        |
| 05 | [Extending the Firmware](05-extending-the-firmware.md)           | Adding IMU / magnetometer / ToF drivers, pose estimation pipeline, adding a second GATT service.            |
| 06 | [VL53L1CB Multi-Zone ToF](06-vl53l1cb-multizone-tof.md)          | Historical/deprecated VL53L1-Satel wiring on I2C3, bare-driver layout, ROI math, GATT service 0xFE60.       |
| 07 | [Reverse Safety Bringup](07-reverse-safety-bringup.md)           | Step-by-step checklist: mode writes, Drive/Debug switching, obstacle test, blind test, BLE watchdog.        |
| 08 | [VL53L5CX ToF Debug](08-vl53l5cx-tof-debug.md)                  | Historical/deprecated MSP01 wiring, PC3/PC4 pins, V2 BLE chunk protocol, 4x4/8x8 streaming.                |
| 09 | [BLE GATT Slot Bug Postmortem](09-ble-gatt-slot-bug-postmortem.md) | Root cause: FE44 undiscoverable due to Max_Attribute_Records=10; fix; VL53L5CX status code bug.           |
| 10 | [SATEL-VL53L8 Firmware Bring-Up](10-vl53l8-satel-bringup.md)    | Active SATEL-VL53L8 I2C/SPI wiring, one-sensor bring-up evidence, and two-sensor wiring plan.             |
| 11 | [Firmware Test Strategy](11-firmware-test-strategy.md)          | Host tests, coverage workflow, hardware-in-the-loop checks, and two-sensor verification plan.             |
| 13 | [Firmware Deploy And UART Log Playbook](13-firmware-deploy-and-uart.md) | Remote-safe flash paths, ST-LINK mass-storage fallback, and live UART logging with `read_uart.py`. |

---

## Typical reader paths

**First flash on a fresh machine**
01 → 02. You will have a blinking LD1 and a BLE advertisement at the end.

**"Where does `<thing>` live?"**
03 (directory layout and IRQ map) → jump to the referenced source file.

**"Why does BLE do X?"**
04 — connection flow and STM32CubeL4 provenance are both there.

**"I want to add a sensor / telemetry channel"**
03 (scheduler pattern) → 05 (sensor-specific recipes and GATT extension).

**"How does the active deployment ToF wiring work?"**
10 — SATEL-VL53L8 I2C/SPI wiring, bring-up checks, and two-sensor plan.

**"How do I prove the firmware is ready?"**
11 — host unit tests, coverage, and serial/BLE end-to-end checks.

**"How do I flash and watch UART from a remote session?"**
13 — build in the worktree, flash through host-approved ST-LINK paths, and use
the reusable live UART reader.

---

## External references

- Board user manual — `../hardware/mcu/um2153-discovery-kit-for-iot-node-...pdf` (this
  repo, under `docs/`).
- MCU reference manual — RM0351 (STM32L4x5/L4x6), from st.com.
- BlueNRG-MS programming guide — PM0257, from st.com.
- Upstream sample code — <https://github.com/STMicroelectronics/STM32CubeL4>
  (see 04-ble-integration.md §5 for the exact example and commit we derived
  from).
