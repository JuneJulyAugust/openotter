# 11 — Firmware Test Strategy

This document describes how to verify the STM32 firmware while the deployment
sensor path moves to SATEL-VL53L8. The quality goal is high confidence in the
logic that can be tested deterministically on a host, plus explicit
hardware-in-the-loop checks for the parts that depend on the IOT01A1, BLE
timing, and the physical VL53L8 sensor.

## Test Scope

The firmware has two very different kinds of code:

| Layer | Example files | Best test type |
| --- | --- | --- |
| Pure firmware logic | `rev_safety_l8.c`, `tof_frame_codec.c`, `tof_l8_config.c`, `ble_tof_policy.c`, `tof_l8_topology.c`, `tof_l8_transport.c` | Host unit tests and coverage |
| Thin hardware shell | `main.c`, HAL init, BlueNRG-MS calls, VL53L8 platform callbacks | Hardware-in-the-loop and serial/BLE checks |
| Vendor/generated code | STM32 HAL, ST Ultra Lite Driver, BlueNRG middleware | Smoke and integration checks only |

The practical coverage target is therefore:

- aim for very high coverage, preferably near or above 99%, on HAL-free project
  modules that encode safety, wire-format, configuration, and topology rules;
- do not treat whole-firmware coverage as meaningful while HAL, generated code,
  and vendor drivers are part of the denominator;
- use hardware-in-the-loop tests for startup sequencing, I2C electrical
  behavior, BLE notification pacing, and sensor frame acquisition.

## Host Unit Tests

Run the host suite from the feature worktree:

```bash
cd /Users/fang/projects/openotter/.worktrees/vl53l8-satel-firmware/firmware/stm32-mcp/tests/host
make test
```

Important SATEL-VL53L8 tests:

| Test | Invariant |
| --- | --- |
| `test_tof_l8_config` | Only valid VL53L8 continuous 4x4/8x8 timing can reach the driver |
| `test_tof_frame_codec` | FE62 frame payloads and 20-byte chunks are deterministic and bounded |
| `test_ble_tof_policy` | BLE ToF status mapping reports hardware-health failures as error state |
| `test_rev_safety_l8` | Reverse safety consumes only valid VL53L8 range-status zones |
| `test_tof_l8_topology` | Future front/rear sensors use safe transports, buses, addresses, chip selects, and control pins |
| `test_tof_l8_transport` | Boot probe choice and SPI register header bits match the VL53L8 protocol |

## Coverage

Use the project virtualenv for Python tools. If `gcovr` is not installed yet:

```bash
/Users/fang/projects/openotter/.venv/bin/python -m pip install gcovr
```

Then run:

```bash
cd /Users/fang/projects/openotter/.worktrees/vl53l8-satel-firmware/firmware/stm32-mcp/tests/host
PATH=/Users/fang/projects/openotter/.venv/bin:$PATH \
  make coverage GCOVR=/Users/fang/projects/openotter/.venv/bin/gcovr
```

The Makefile writes coverage counters under `tests/host/build/`. If `gcovr` is
available, it also writes an HTML report at:

```text
/Users/fang/projects/openotter/.worktrees/vl53l8-satel-firmware/firmware/stm32-mcp/tests/host/build/coverage.html
```

Read coverage as a branch-discovery tool, not as a release certificate. A line
that handles a HAL failure, a missing ST-LINK probe, or a broken sensor cable
still needs a hardware check even if a host test can exercise nearby policy.

Current release-candidate evidence from 2026-06-02:

```text
lines:     99.3% (450 out of 453)
functions: 98.0% (48 out of 49)
branches:  90.7% (294 out of 324)
```

Every filtered module except `firmware_panic.c` reached 100% line coverage.
The remaining uncovered lines are the `HOST_TEST` `Firmware_Panic()` stub, which
spins forever by design and is not called from host tests.

## One-Sensor End-To-End Test

The one-sensor release candidate must pass this bench flow before merging:

1. Power off the IOT01A1 before changing SATEL wiring.
2. Wire one SATEL-VL53L8 exactly as described in
   `10-vl53l8-satel-bringup.md`.
3. Connect the IOT01A1 ST-LINK USB port to the Mac.
4. Flash firmware:

   ```bash
   cd /Users/fang/projects/openotter/.worktrees/vl53l8-satel-firmware/firmware/stm32-mcp
   ./build.sh all
   ```

5. Open serial at 115200 baud:

   ```bash
   screen /dev/cu.usbmodemXXXX 115200
   ```

6. Confirm boot and driver logs:

   ```text
   BLE_Tof ready
   BLE_Tof safety_config fire mode=0
   VL53L8 probe transport=i2c3 phase=is_alive
   VL53L8 probe transport=spi1 phase=is_alive
   VL53L8 selected transport=i2c3
   VL53L8 init phase=fw_download
   VL53L8 stream start layout=4 zones=16 hz=30
   VL53L8 frame layout=4 zones=16
   ```

   If the sensor is wired for SPI, the selected transport should be `spi1`.

7. Point the sensor at open space and then at a flat object about 20-80 cm away.
   The 4x4 grid ranges should change, and valid center statuses should be one
   of `5`, `6`, `9`, or `10`.
8. Connect the iOS diagnostics view, switch to Debug, and request an 8x8 stream
   at 10-15 Hz. Serial should show `layout=8 zones=64`; iOS should render an
   8x8 depth map and the FE62 chunk counter should advance.
9. Return to Drive mode. External FE61 writes should be locked, FE63 should
   report running state with `last_error=0`, and the safety config should return
   to 4x4 30 Hz.
10. With the robot safely immobilized, test reverse safety against a near
    obstacle and then clear the obstacle. The firmware should brake only when
    the speed/distance rule requires it.

## Failure Injection Checks

Run these checks after the happy path, because they prove the firmware fails
observably instead of silently:

| Fault | Expected behavior |
| --- | --- |
| SATEL unpowered or unplugged | UART logs both I2C3 and SPI1 probe attempts, then `VL53L8 probe: no sensor ...`; FE63 reports error state after retry |
| `LPn` held low | Probe fails; retry cadence is visible in UART |
| SCL/SDA swapped | Probe fails; no frame logs appear |
| Debug config with invalid timing | FE63 keeps running state and reports `TOF_STATUS_BAD_CONFIG` |
| Drive-mode FE61 write | FE63 keeps running state and reports `TOF_STATUS_LOCKED_IN_DRIVE` |

## Two-Sensor Test Plan

Two sensors are not active in firmware yet, but the topology is already captured
in `tof_l8_topology.c` and `test_tof_l8_topology.c`.

Before enabling two-sensor runtime code, verify the hardware in this order:

1. Rear sensor alone on I2C3: A5/A4, `SPI_I2C_N=GND`, A1 `LPn`, A2 `GPIO1`.
2. Rear sensor alone on SPI1: D13/D11/D12, `SPI_I2C_N=3V3`, D8 `NCS`,
   A1 `LPn`, A2 `GPIO1`.
3. Front sensor alone on SPI1: D13/D11/D12, `SPI_I2C_N=3V3`, D10 `NCS`,
   A0 `LPn`, A3 `GPIO1`.
4. Both sensors wired with shared 5V, GND, SPI1 clock/MOSI/MISO, and
   `SPI_I2C_N=3V3`, but separate `NCS` and separate `LPn` lines.
5. Both sensors ranging continuously at conservative rates.
6. Safety policy chooses the front sensor while moving forward and the rear
   sensor while reversing, while both frame streams remain alive.

Expected two-sensor logs once firmware support is added:

```text
VL53L8 rear stream start transport=spi1 ncs=D8 layout=4 zones=16
VL53L8 front stream start transport=spi1 ncs=D10 layout=4 zones=16
VL53L8 rear frame seq=...
VL53L8 front frame seq=...
```

Fallback I2C plan: rear on I2C3 and front on I2C1 can work if SPI1 brings up
poorly. If both sensors ever share one I2C bus, the boot sequence must hold both
`LPn` lines low and wake/address one sensor at a time. The preferred design
avoids that fragile address-assignment sequence by using shared SPI1 with
dedicated chip selects.
