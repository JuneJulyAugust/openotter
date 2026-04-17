# stm32-mcp — Developer Documentation

This directory holds the long-form development documentation for the
`stm32-mcp` firmware on the **B-L475E-IOT01A** Discovery Kit. The project-
level `README.md` covers the high-level feature set and memory footprint;
these documents cover *how to work on the code*.

Read them in order the first time; after that each is self-contained.

| #  | Document                                                 | What it covers                                                                                        |
|----|----------------------------------------------------------|-------------------------------------------------------------------------------------------------------|
| 01 | [Toolchain and Build](01-toolchain-and-build.md)         | Installing STM32CubeCLT on macOS, PATH setup, `build.sh` subcommands and environment variables.       |
| 02 | [Board Bringup](02-board-bringup.md)                     | Verifying the ST-Link probe, reading the on-board LEDs, BLE advertising check without the iOS app.    |
| 03 | [Architecture](03-architecture.md)                       | Source tree layout, boot sequence, cooperative scheduler, IRQ priorities, TIM3 / PWM pin map.         |
| 04 | [BLE Integration](04-ble-integration.md)                 | BlueNRG-MS stack on SPI3, GATT service definition, full connection flow, STM32CubeL4 source lineage.  |
| 05 | [Extending the Firmware](05-extending-the-firmware.md)   | Adding IMU / magnetometer / ToF drivers, pose estimation pipeline, adding a second GATT service.      |

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

---

## External references

- Board user manual — `../um2153-discovery-kit-for-iot-node-...pdf` (this
  repo, under `docs/`).
- MCU reference manual — RM0351 (STM32L4x5/L4x6), from st.com.
- BlueNRG-MS programming guide — PM0257, from st.com.
- Upstream sample code — <https://github.com/STMicroelectronics/STM32CubeL4>
  (see 04-ble-integration.md §5 for the exact example and commit we derived
  from).
