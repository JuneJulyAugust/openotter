# 10 — SATEL-VL53L8 Firmware Bring-Up

This deployment uses SATEL-VL53L8 on the B-L475E-IOT01A1 over I2C3. VL53L0X,
VL53L1CB, and VL53L5CX are deprecated for this deployment path.

## Source Documents

- `docs/hardware/sensors/satel-vl53l8-schematic.pdf`
- `docs/hardware/sensors/satel-vl53l8.pdf`
- `docs/hardware/sensors/an5945-how-to-connect-the-satelvl53l8-to-an-stm32-nucleo64-board-stmicroelectronics.pdf`

## Finding J1 And J2 On The SATEL Board

`J1` and `J2` are schematic connector reference names, not one continuous
14-pin connector. The SATEL schematic calls them:

| Connector | Schematic part | What it carries |
| --- | --- | --- |
| `J1` | 3-pin, 2.54 mm male header | top pad `EXT_GPIO1`, middle pad `EXT_GPIO2`, bottom square pad GND |
| `J2` | 11-pin, 2.54 mm male header | mode, reset, I2C/SPI, power-enable, and supply pins |

With the SATEL board oriented like Figure 1 in `satel-vl53l8.pdf`:

- the snap-off mini-PCB is on the left of the red perforation line;
- the larger carrier board is on the right of the red perforation line;
- `J1` is the short 3-hole expansion header footprint near the perforation;
- `J2` is the longer 11-hole expansion header footprint on the carrier board;
- `J3` is the I/O-voltage select jumper and is not part of the IOT01A1 wiring.

Do not treat the board as a single 14-pin header. If a diagram says SATEL
pin 12, pin 13, or pin 14, that is usually shorthand for the three `J1` pads
after counting the 11 pins of `J2`. In the ST connector image, those signals
are the `J1` pads by physical position:

| Combined shorthand | J1 physical pad | Signal |
| --- | --- | --- |
| pin 12 | top round pad | `EXT_GPIO1` |
| pin 13 | middle round pad | `EXT_GPIO2` |
| pin 14 | bottom square pad | GND |

`J2` is numbered separately:

| J2 pin | Signal | Use in this project |
| --- | --- | --- |
| 1 | `EXT_SPI_I2C_N` | Tie high to 3V3 for I2C mode |
| 2 | `EXT_LPn` | Optional host reset/enable control |
| 3 | `EXT_NCS` | SPI chip-select; unused for I2C |
| 4 | `EXT_MISO` | SPI MISO; unused for I2C |
| 5 | `EXT_MOSI_SDA` | I2C3 SDA from IOT01A1 A4 / PC1 |
| 6 | `EXT_MCLK_SCL` | I2C3 SCL from IOT01A1 A5 / PC0 |
| 7 | `EXT_PWR_EN` | Tie high to 3V3 to enable SATEL regulators |
| 8 | `EXT_IOVDD` | Do not wire for this bring-up |
| 9 | `EXT_3V3` | Do not wire for this bring-up |
| 10 | `EXT_1V8` | Do not wire; low-voltage rail |
| 11 | `EXT_5V0` | 5V input to the SATEL regulators |

The yellow pads on the snap-off mini-PCB expose the tiny sensor board directly.
Those pads are useful only if the mini-PCB is broken off and powered/level-shifted
as a separate 1.8 V design. The wiring below assumes the full SATEL carrier board
is used, because the carrier provides the required regulators and level shifters.

## Electrical Safety Notes

The full SATEL carrier board expects two different kinds of connections:

- one power input: IOT01A1 5V to `J2` pin 11 `EXT_5V0`;
- 3.3 V logic highs: IOT01A1 3V3 to `J2` pin 1 `EXT_SPI_I2C_N`
  and `J2` pin 7 `EXT_PWR_EN`;
- 3.3 V open-drain I2C signals: A5/SCL and A4/SDA;
- common ground.

Do not move these rails around:

- 5V on `J2` pin 1 `EXT_SPI_I2C_N` is a logic over-voltage risk.
- 3V3 or 5V on `J2` pin 10 `EXT_1V8` can over-voltage a low-voltage rail.
- 3V3 or 5V on `J2` pin 8 `EXT_IOVDD` can over-voltage the sensor I/O rail.
- 3V3 on `J2` pin 11 `EXT_5V0` is not the intended regulator input and can
  create brown-out symptoms that look like firmware or I2C bugs.
- `J2` pin 9 `EXT_3V3` is not needed when using the 5V regulator-input path;
  do not tie it to IOT01A1 3V3 for this bring-up.

Before powering the board, identify `J2` pin 1 by the square pad at the bottom
of the 11-pin connector image, then count upward to pin 11. Identify `J1` by
signal position: top is `EXT_GPIO1`, middle is `EXT_GPIO2`, bottom square pad
is GND.

Do not hot-plug these wires. If the board has already been powered with the
wrong wiring, power it off, remove every flying lead, identify the connector
pins again, then reconnect from the corrected table. If anything is uncertain,
connect only 5V, 3V3 mode/enable, and GND first, then measure the rails before
adding SCL/SDA or GPIO wires.

## Current Wiring Check

If your SATEL pin numbers mean schematic connector pins, the current wiring is
not fully correct.

| Current connection | Check | Required correction |
| --- | --- | --- |
| IOT01A1 3V3 -> pin 11 `SPI_I2C_n` | Incorrect. J2 pin 11 is `EXT_5V0`, not `SPI_I2C_N`. 3V3 there is not the intended 5V regulator input and does not select I2C mode. | Move 3V3 to J2 pin 1 `EXT_SPI_I2C_N` and J2 pin 7 `EXT_PWR_EN`; move 5V to J2 pin 11 `EXT_5V0`. |
| IOT01A1 5V -> pin 1 | Dangerous. J2 pin 1 is `EXT_SPI_I2C_N`, a logic input, not a 5V power input. | Move 5V to J2 pin 11 `EXT_5V0`. |
| IOT01A1 A5 -> pin 6 `MCLK_SCL` | Correct. | Keep J2 pin 6 `EXT_MCLK_SCL`. |
| IOT01A1 A4 -> pin 7 `MOSI_SDA` | Incorrect. J2 pin 7 is `EXT_PWR_EN`, not SDA. | Move A4 / PC1 to J2 pin 5 `EXT_MOSI_SDA`; tie J2 pin 7 high to 3V3. |
| IOT01A1 GND -> pin 14 GND | Correct only if pin 14 means the bottom square pad of `J1`. | Keep common ground. |
| IOT01A1 A2 -> pin 12 `GPIO1 / INT` | Correct only if pin 12 means the top pad of `J1`. | Keep for optional data-ready interrupt input. Firmware can poll first. |
| IOT01A1 A1 -> pin 13 `GPIO2` | The middle pad of `J1` is GPIO2, but GPIO2 is not the reset/enable line. | Prefer A1 / PC4 -> J2 pin 2 `EXT_LPn`. Leave GPIO2 unconnected unless using sync later. |

## Correct One-Sensor Wiring

| IOT01A1 | MCU pin | SATEL-VL53L8 | Purpose |
| --- | --- | --- | --- |
| 5V | board 5V | J2 pin 11 `EXT_5V0` | SATEL regulator input |
| 3V3 | board 3V3 | J2 pin 1 `EXT_SPI_I2C_N` | Select I2C mode |
| 3V3 | board 3V3 | J2 pin 7 `EXT_PWR_EN` | Enable SATEL regulators |
| A5 | PC0 / I2C3_SCL | J2 pin 6 `EXT_MCLK_SCL` | I2C clock |
| A4 | PC1 / I2C3_SDA | J2 pin 5 `EXT_MOSI_SDA` | I2C data |
| A2 | PC3 | J1 top pad `EXT_GPIO1` | Data-ready interrupt input; firmware can poll first |
| A1 | PC4 | J2 pin 2 `EXT_LPn` | Sensor low-power/reset control |
| GND | GND | J1 bottom square pad GND or SATEL GND | Common ground |

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
| `EXT_5V0` | Shared 5V -> J2 pin 11 | Shared 5V -> J2 pin 11 |
| `EXT_SPI_I2C_N` | Shared 3V3 | Shared 3V3 |
| `EXT_PWR_EN` | Shared 3V3 | Shared 3V3 |
| GND | Shared GND | Shared GND |
| `EXT_LPn` | Dedicated A1 / PC4 | Dedicated A0 / PC5 or D8 / PB2 |
| `EXT_GPIO1` | Dedicated A2 / PC3 -> J1 top pad | Dedicated A3 / PC2 -> J1 top pad |

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
3. Confirm SATEL J2 pin 11 has 5V relative to GND.
4. Confirm J2 pin 1 and J2 pin 7 are high at 3V3.
5. Confirm J2 pin 10 `EXT_1V8` and J2 pin 8 `EXT_IOVDD` have no external
   IOT01A1 wire attached.
6. Confirm A5/SCL and A4/SDA are not swapped.
7. Flash firmware.
8. Watch UART1 for a `VL53L8` probe line.
9. If the probe fails, check `PWR_EN`, ground, SCL/SDA order, and whether
   `LPn` is held low.
