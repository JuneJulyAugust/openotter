# 10 — SATEL-VL53L8 Firmware Bring-Up

This deployment uses SATEL-VL53L8 on the B-L475E-IOT01A1 over I2C3. VL53L0X,
VL53L1CB, and VL53L5CX are deprecated for this deployment path.

## Source Documents

- `docs/hardware/sensors/satel-vl53l8-schematic.pdf`
- `docs/hardware/sensors/satel-vl53l8.pdf`
- `docs/hardware/sensors/an5945-how-to-connect-the-satelvl53l8-to-an-stm32-nucleo64-board-stmicroelectronics.pdf`

## Current Wiring Check

If your SATEL pin numbers mean schematic connector pins, the current wiring is
not fully correct.

| Current connection | Check | Required correction |
| --- | --- | --- |
| IOT01A1 3V3 -> pin 11 `SPI_I2C_n` | Incorrect. SATEL J2 pin 11 is `EXT_1V8`. | Use J2 pin 1 `EXT_SPI_I2C_N`. |
| IOT01A1 5V -> pin 1 | Incorrect. J2 pin 1 is `EXT_SPI_I2C_N`. | Use J2 pin 10 `EXT_5V0`. |
| IOT01A1 A5 -> pin 6 `MCLK_SCL` | Correct. | Keep J2 pin 6 `EXT_MCLK_SCL`. |
| IOT01A1 A4 -> pin 7 `MOSI_SDA` | Incorrect. J2 pin 7 is `EXT_PWR_EN`. | Use J2 pin 5 `EXT_MOSI_SDA`. |
| IOT01A1 GND -> pin 14 GND | Likely correct if combined numbering maps J1 bottom to GND. | Keep common ground. |
| IOT01A1 A2 -> pin 12 `GPIO1 / INT` | Likely correct if combined numbering maps J1 top to GPIO1. | Keep for data-ready interrupt input. |
| IOT01A1 A1 -> pin 13 `GPIO2` | GPIO2 is not the reset/enable line. | Prefer A1 / PC4 -> J2 pin 2 `EXT_LPn`. |

## Correct One-Sensor Wiring

| IOT01A1 | MCU pin | SATEL-VL53L8 | Purpose |
| --- | --- | --- | --- |
| 5V | board 5V | J2 pin 10 `EXT_5V0` | SATEL regulator input |
| 3V3 | board 3V3 | J2 pin 1 `EXT_SPI_I2C_N` | Select I2C mode |
| 3V3 | board 3V3 | J2 pin 7 `EXT_PWR_EN` | Enable SATEL regulators |
| A5 | PC0 / I2C3_SCL | J2 pin 6 `EXT_MCLK_SCL` | I2C clock |
| A4 | PC1 / I2C3_SDA | J2 pin 5 `EXT_MOSI_SDA` | I2C data |
| A2 | PC3 | J1 `EXT_GPIO1` | Data-ready interrupt input; firmware can poll first |
| A1 | PC4 | J2 pin 2 `EXT_LPn` | Sensor low-power/reset control |
| GND | GND | J1 GND or SATEL GND | Common ground |

`SPI_I2C_N` must be high for I2C mode. `PWR_EN` should be high for the full
SATEL board regulators unless the board assembly already straps it high.

## Firmware Expectations

The active firmware path is:

```text
I2C3 on A5/A4
  -> VL53L8CX Ultra Lite Driver
  -> Tof_Frame_t 4x4/8x8 frame
  -> reverse safety selector using 4x4 row-3 center zones
  -> BLE ToF diagnostic stream
```

The STM32 HAL uses 8-bit I2C addresses. The VL53L8 default 7-bit address is
`0x29`, represented as `0x52` in HAL calls.

## Two-Sensor Wiring Plan

Two VL53L8 sensors cannot both be active at the default I2C address. They must
share SCL/SDA only while each has an independently controlled `LPn` line so the
firmware can boot and re-address them one at a time.

| Signal | Rear SATEL | Front SATEL |
| --- | --- | --- |
| `EXT_MCLK_SCL` | Shared A5 / PC0 | Shared A5 / PC0 |
| `EXT_MOSI_SDA` | Shared A4 / PC1 | Shared A4 / PC1 |
| `EXT_5V0` | Shared 5V | Shared 5V |
| `EXT_SPI_I2C_N` | Shared 3V3 | Shared 3V3 |
| `EXT_PWR_EN` | Shared 3V3 | Shared 3V3 |
| GND | Shared GND | Shared GND |
| `EXT_LPn` | Dedicated A1 / PC4 | Dedicated A0 / PC5 or D8 / PB2 |
| `EXT_GPIO1` | Dedicated A2 / PC3 | Dedicated A3 / PC2 |

Future boot sequence:

1. Hold both `LPn` lines low.
2. Release rear `LPn`.
3. Initialize rear at default address and assign the rear address.
4. Release front `LPn`.
5. Initialize front at default address and assign the front address.
6. Poll or interrupt each sensor independently.

Do not wire two SATEL boards with shared `LPn` unless only one is populated or
only one is powered.

## Bring-Up Checklist

1. Power off the IOT01A1 before changing wires.
2. Wire according to the corrected one-sensor table.
3. Confirm SATEL J2 pin 10 has 5V relative to GND.
4. Confirm J2 pin 1 and J2 pin 7 are high at 3V3.
5. Confirm A5/SCL and A4/SDA are not swapped.
6. Flash firmware.
7. Watch UART1 for a `VL53L8` probe line.
8. If the probe fails, check `PWR_EN`, ground, SCL/SDA order, and whether
   `LPn` is held low.
