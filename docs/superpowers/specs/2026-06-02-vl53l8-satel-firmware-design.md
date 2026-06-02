# VL53L8 SATEL Firmware Design

## Goal

Move STM32 firmware development from the older VL53L1/VL53L5 prototype stack to
one deployed SATEL-VL53L8 sensor on the B-L475E-IOT01A1, while making the
firmware structure ready for a second SATEL-VL53L8 sensor later.

This phase is firmware-only. iOS changes are explicitly out of scope.

## Hardware Findings

The current SATEL-VL53L8 wiring is not fully correct if the pin numbers are
the schematic connector numbers:

| User connection | Result | Correction |
| --- | --- | --- |
| IOT01A1 3V3 -> SATEL pin 11 `SPI_I2C_n` | Incorrect. J2 pin 11 is `EXT_5V0`, not `SPI_I2C_N`. 3V3 there is not the intended 5V regulator input and does not select I2C mode. | Connect IOT01A1 3V3 to J2 pin 1 `EXT_SPI_I2C_N` for I2C mode and J2 pin 7 `EXT_PWR_EN`; connect IOT01A1 5V to J2 pin 11 `EXT_5V0`. |
| IOT01A1 5V -> SATEL pin 1 | Dangerous. J2 pin 1 is `EXT_SPI_I2C_N`, a logic input, not a 5V power input. | Connect IOT01A1 5V to J2 pin 11 `EXT_5V0`. |
| IOT01A1 A5 -> SATEL pin 6 `MCLK_SCL` | Correct. | Keep A5 / PC0 on J2 pin 6 `EXT_MCLK_SCL`. |
| IOT01A1 A4 -> SATEL pin 7 `MOSI_SDA` | Incorrect. J2 pin 7 is `EXT_PWR_EN`; `EXT_MOSI_SDA` is J2 pin 5. | Connect A4 / PC1 to J2 pin 5 `EXT_MOSI_SDA`; tie J2 pin 7 high to 3V3. |
| IOT01A1 GND -> SATEL pin 14 GND | Correct only if pin 14 means the bottom square pad of `J1`. | Keep common ground on SATEL GND. |
| IOT01A1 A2 -> SATEL pin 12 `GPIO1 / INT` | Correct only if pin 12 means the top pad of `J1`. | Keep for data-ready interrupt input. Firmware will poll first. |
| IOT01A1 A1 -> SATEL pin 13 `GPIO2` | The middle pad of `J1` is GPIO2, but GPIO2 is not the reset/enable line. | For single-sensor bring-up, prefer A1 / PC4 -> J2 pin 2 `EXT_LPn` if you want host reset/enable control. GPIO2 can be left for future sync. |

AN5945 also shows `PWR_EN` in the I2C wiring. For the full SATEL board, tie
J2 pin 7 `EXT_PWR_EN` high to 3V3 unless the assembled board or jumper
configuration already holds it high. Without enabled regulators, the sensor can
look like an I2C failure even when SCL/SDA are correct.

`J1` and `J2` are separate connector reference designators on the SATEL
schematic. They are not one continuous 14-pin connector. `J2` is the 11-pin
expansion header carrying mode, reset, I2C/SPI, power-enable, and supply
signals. `J1` is the 3-pad expansion header carrying top pad `EXT_GPIO1`,
middle pad `EXT_GPIO2`, and bottom square pad GND. If a drawing says SATEL
pin 12, pin 13, or pin 14, treat that as combined shorthand for the `J1` pads
after `J2` pins 1-11:

| Combined shorthand | J1 physical pad | Signal |
| --- | --- | --- |
| pin 12 | top round pad | `EXT_GPIO1` |
| pin 13 | middle round pad | `EXT_GPIO2` |
| pin 14 | bottom square pad | GND |

The yellow pads on the snap-off mini-PCB are not the `J1`/`J2` expansion
headers. They expose the tiny sensor board directly and require separate
1.8 V power and level-shifting assumptions. This design uses the full SATEL
carrier board so the on-board regulators and level translators remain in the
signal path.

## Firmware Invariant

The deployed ToF path has one source of truth:

```text
SATEL-VL53L8 hardware
  -> VL53L8CX Ultra Lite Driver
  -> generic Tof_Frame_t stream
  -> reverse-safety selector
  -> BLE ToF diagnostic service
```

VL53L1CB and on-board VL53L0X are deprecated for this deployment. VL53L5CX is
also deprecated as a firmware-facing sensor name. The only acceptable remaining
VL53L5 references are historical docs and compatibility notes.

## Driver Package

ST lists STSW-IMG040 as the Ultra Lite Driver API for VL53L8CX. The firmware
must import that package under:

```text
firmware/stm32-mcp/Drivers/VL53L8CX/
  modules/
  platform/
```

The project should not pretend that the STSW-IMG023 VL53L5CX package is the
VL53L8 deployment driver. `fetch-deps.sh` will gain a `--vl53l8cx-path`
argument for the manually downloaded STSW-IMG040 package.

## Architecture

Create a firmware-facing VL53L8 wrapper by migrating the current VL53L5 wrapper
shape:

| Unit | Responsibility |
| --- | --- |
| `tof_l8.{h,c}` | Own one active VL53L8CX ULD instance, I2C platform callbacks, sensor boot, config, polling, and latest-frame buffering. |
| `tof_l8_config.c` | Pure config validation for 4x4/8x8, frequency, and integration-time invariants. |
| `tof_l8_debounce.{h,c}` | Preserve the existing stop/start debounce invariant. |
| `rev_safety_l8.{h,c}` | Select the rear safety reading from a 4x4 VL53L8 frame. |
| `tof_types.h` | Rename the multizone sensor type to `TOF_SENSOR_VL53L8CX`; keep old numeric value if needed for BLE compatibility. |
| `ble_tof.{h,c}` | Prefer VL53L8 V2 frames and configs. Deprecated VL53L1/VL53L5 config writes are rejected so the firmware has one active ToF path. |

The wrapper will be designed around one active slot now:

```c
typedef enum {
  TOF_L8_SENSOR_REAR = 0,
  TOF_L8_SENSOR_FRONT = 1,
} TofL8SensorId_t;
```

Only the rear slot is enabled in this phase. The second slot exists in docs and
types so later work can add address sequencing without reshaping the public
logic.

## One-Sensor Bring-Up

Use the corrected SATEL wiring on I2C3:

| IOT01A1 | MCU pin | SATEL signal |
| --- | --- | --- |
| 5V | board 5V | J2 pin 11 `EXT_5V0` |
| 3V3 | board 3V3 | J2 pin 1 `EXT_SPI_I2C_N`; J2 pin 7 `EXT_PWR_EN` |
| A5 | PC0 / I2C3_SCL | J2 pin 6 `EXT_MCLK_SCL` |
| A4 | PC1 / I2C3_SDA | J2 pin 5 `EXT_MOSI_SDA` |
| A2 | PC3 input | J1 top pad `EXT_GPIO1` / INT |
| A1 | PC4 output | J2 pin 2 `EXT_LPn` |
| GND | GND | J1 bottom square pad GND or SATEL GND |

The initial firmware can poll for data readiness and keep GPIO1 as a future
interrupt input. That avoids coupling correctness to EXTI timing during first
bring-up.

## Two-Sensor Ready Design

Two VL53L8 sensors share I2C SCL/SDA only after they have unique addresses. The
VL53L8 default I2C address is `0x29` 7-bit (`0x52` in STM32 HAL 8-bit form).
Two sensors at the default address cannot be online together.

The future two-sensor topology is:

| Signal | Rear sensor | Front sensor |
| --- | --- | --- |
| I2C3 SCL | Shared A5 / PC0 -> both J2 pin 6 | Shared A5 / PC0 -> both J2 pin 6 |
| I2C3 SDA | Shared A4 / PC1 -> both J2 pin 5 | Shared A4 / PC1 -> both J2 pin 5 |
| 5V, 3V3, GND | Shared rails; 5V to J2 pin 11 | Shared rails; 5V to J2 pin 11 |
| `SPI_I2C_N` | Tied high to 3V3 | Tied high to 3V3 |
| `PWR_EN` | Tied high to 3V3 | Tied high to 3V3 |
| `LPn` | Dedicated GPIO, suggested A1 / PC4 | Dedicated GPIO, suggested A0 / PC5 or D8 / PB2 |
| `GPIO1 / INT` | Dedicated GPIO, suggested A2 / PC3 to J1 top pad | Dedicated GPIO, suggested A3 / PC2 to J1 top pad |
| I2C address | Default during isolated boot, then assigned rear address | Default during isolated boot, then assigned front address |

Future sequencing:

1. Hold both `LPn` lines low.
2. Release rear `LPn`.
3. Boot rear at default address and change it to the rear address.
4. Release front `LPn`.
5. Boot front at default address and change it to the front address.
6. Poll/process each slot independently.

This sequence is the invariant that makes shared I2C safe.

## Deprecation

Deprecated for deployment:

- VL53L0X on-board sensor.
- VL53L1CB SATEL path.
- VL53L5CX as a current firmware-facing sensor name.

Do not delete historical docs or tests only to make the tree look clean. Rename
or replace active firmware paths that would otherwise mislead future work.

## Verification

Required checks for this phase:

- Host tests before and after edits: `make test` in
  `firmware/stm32-mcp/tests/host`.
- New/renamed host tests for VL53L8 config and reverse-safety selection.
- Firmware build if STSW-IMG040 and STM32CubeCLT dependencies are available.
- Manual wiring check against
  `firmware/stm32-mcp/docs/dev/10-vl53l8-satel-bringup.md`.

## References

- `firmware/stm32-mcp/docs/hardware/sensors/satel-vl53l8-schematic.pdf`
- `firmware/stm32-mcp/docs/hardware/sensors/satel-vl53l8.pdf`
- `firmware/stm32-mcp/docs/hardware/sensors/an5945-how-to-connect-the-satelvl53l8-to-an-stm32-nucleo64-board-stmicroelectronics.pdf`
- ST product page for STSW-IMG040, the VL53L8CX Ultra Lite Driver.
- ST UM3109, VL53L8CX ULD user manual.
