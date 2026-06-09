# VL53L8 SATEL Firmware Design

## Goal

Move STM32 firmware development from the older VL53L1/VL53L5 prototype stack to
one deployed SATEL-VL53L8 sensor on the B-L475E-IOT01A1, while making the
firmware structure ready for a second SATEL-VL53L8 sensor later.

This document describes the firmware/hardware phase. The matching iOS debug and
autonomy plan is tracked separately in
`docs/superpowers/specs/2026-06-02-ios-vl53l8-tof-debug-autonomy-design.md`.

## Release-Candidate Status

As of 2026-06-08, the one-sensor SATEL-VL53L8 firmware path is implemented and
prepared as `stm32-mcp` `1.2.0`. The branch is intentionally not merged or
tagged yet pending final PR CI/release hygiene, but one-rear-sensor hardware
end-to-end validation has passed.

Final validation and resolved-bug evidence is tracked in:

```text
docs/superpowers/specs/2026-06-08-vl53l8-v1.2-validation-and-bugs.md
```

Bench evidence from ST-LINK serial after the sensor was moved off the table:

```text
VL53L8 frame layout=4 zones=16 seq=3338 fps=31 targetZones=16 min=177 max=321 center=315,293,307,284 cst=5,5,5,5
```

The invariant proven by that log is:

```text
correct SATEL wiring
  -> VL53L8CX boot and firmware download
  -> continuous 4x4 depth frames
  -> valid-status center-zone data available to reverse safety
```

## Dual-Transport Update

The firmware will support both SATEL-VL53L8 wiring modes in one image:

- I2C mode: `J2 pin 1 EXT_SPI_I2C_N` tied to GND.
- SPI mode: `J2 pin 1 EXT_SPI_I2C_N` tied to 3V3.

The firmware does not hot-swap modes. The user powers off the IOT01A1 and SATEL
board before changing wiring. At the next boot, firmware probes the configured
transports and uses whichever one responds. The mode pin is not treated as a
runtime software switch because it is a SATEL input, not a guaranteed MCU-readable
signal in the current wiring.

The transport invariant is:

```text
SATEL wiring selects I2C or SPI
  -> firmware probes I2C3, then SPI1
  -> exactly one transport should answer for a single populated sensor
  -> VL53L8CX ULD receives transport callbacks through one platform object
  -> ranging, safety, BLE, and iOS-facing frame semantics stay unchanged
```

If no transport answers, firmware reports `TOF_STATUS_NO_SENSOR` and logs both
probe attempts. If both transports answer for the same single-sensor slot, that
is treated as a wiring/configuration fault rather than a feature: the expected
SATEL mode wiring should make only one protocol usable.

The ST VL53L8CX ULD already exposes the right seam: `VL53L8CX_Platform` contains
`Write`, `Read`, `Wait`, and `handle` fields. The project wrapper should move raw
I2C access out of `tof_l8.c` into a narrow transport module, then add SPI1 access
behind the same callback contract. The rest of `tof_l8.c` should keep owning
sensor boot, configuration, polling, frame conversion, and logging.

For SPI, use SPI1 on the Arduino header. Do not use SPI3; SPI3 is owned by the
BlueNRG-MS BLE middleware and must remain isolated from ToF.

| SATEL SPI signal | IOT01A1 pin | MCU pin | Notes |
| --- | --- | --- | --- |
| `EXT_SPI_I2C_N` / J2 pin 1 | 3V3 | board 3V3 | Select SPI mode. |
| `EXT_MCLK_SCL` / J2 pin 6 | D13 | PA5 / SPI1_SCK | Shared clock for one or two SPI sensors. |
| `EXT_MOSI_SDA` / J2 pin 5 | D11 | PA7 / SPI1_MOSI | Shared MOSI. |
| `EXT_MISO` / J2 pin 4 | D12 | PA6 / SPI1_MISO | Shared MISO; only selected sensor may drive it. |
| `EXT_NCS` / J2 pin 3 | D8 for rear | PB2 GPIO output | Dedicated chip-select, idle high. |
| `EXT_LPn` / J2 pin 2 | A1 for rear | PC4 GPIO output | Dedicated reset/recovery control. |
| `EXT_GPIO1` / J1 top pad | A2 for rear | PC3 GPIO input | Optional interrupt; polling remains valid. |
| `EXT_PWR_EN` / J2 pin 7 | D9 or 3V3 | PA15 or board 3V3 | GPIO is better for recovery; 3V3 is simpler. |
| `EXT_5V0` / J2 pin 11 | 5V | board 5V | SATEL regulator input. |
| GND | GND | board GND | Common ground. |

SPI timing starts conservatively: SPI mode 3, MSB first, 8-bit words, no hardware
NSS, and an SPI1 baud rate at or below the VL53L8CX 3 MHz limit. Higher clocking
can be considered only after one-sensor SPI bring-up is stable.

## Hardware Findings

The current SATEL-VL53L8 wiring is not fully correct if the pin numbers are
the schematic connector numbers:

| User connection | Result | Correction |
| --- | --- | --- |
| IOT01A1 3V3 -> SATEL pin 11 `SPI_I2C_n` | Incorrect. J2 pin 11 is `EXT_5V0`, not `SPI_I2C_N`. 3V3 there is not the intended 5V regulator input and does not select I2C mode. | Connect IOT01A1 GND to J2 pin 1 `EXT_SPI_I2C_N` for I2C mode, 3V3 to J2 pin 7 `EXT_PWR_EN`, and 5V to J2 pin 11 `EXT_5V0`. |
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
| `tof_l8.{h,c}` | Own one active VL53L8CX ULD instance, transport probing, sensor boot, config, polling, and latest-frame buffering. |
| `tof_l8_transport.{h,c}` | Own the narrow VL53L8CX platform callback bridge for I2C3 or SPI1. |
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
| GND | board GND | J2 pin 1 `EXT_SPI_I2C_N` |
| 3V3 | board 3V3 | J2 pin 7 `EXT_PWR_EN` |
| A5 | PC0 / I2C3_SCL | J2 pin 6 `EXT_MCLK_SCL` |
| A4 | PC1 / I2C3_SDA | J2 pin 5 `EXT_MOSI_SDA` |
| A2 | PC3 input | J1 top pad `EXT_GPIO1` / INT |
| A1 | PC4 output | J2 pin 2 `EXT_LPn` |
| GND | GND | J1 bottom square pad GND or SATEL GND |

The initial firmware can poll for data readiness and keep GPIO1 as a future
interrupt input. That avoids coupling correctness to EXTI timing during first
bring-up.

## Two-Sensor Ready Design

The preferred two-sensor deployment topology is now shared SPI1 with independent
chip-select and reset lines. This matches ST's multi-sensor SPI guidance and
avoids I2C default-address sequencing for the production front/rear pair:

- rear SATEL-VL53L8 on SPI1 `D13/D12/D11`, rear `NCS` on D8, rear `LPn` on A1;
- front SATEL-VL53L8 on the same SPI1 pins, front `NCS` on D10, front `LPn` on
  A0;
- both sensors keep separate optional `GPIO1` interrupt inputs.

The SPI topology lets both sensors remain online and ranging without assigning
runtime I2C addresses. The firmware still reads them sequentially, because one
SPI controller talks to one selected sensor at a time, but the protocol no
longer has an address collision at boot.

The previous separate-I2C topology remains a supported fallback:

- rear SATEL-VL53L8 on I2C3 (`A5/PC0` SCL, `A4/PC1` SDA);
- front SATEL-VL53L8 on I2C1 (`D15/PB8` SCL, `D14/PB9` SDA).

This lets both sensors remain online and ranging at the VL53L8 default address
`0x29` 7-bit (`0x52` in STM32 HAL 8-bit form), because each bus has only one
active SATEL at that address. The firmware still reads them sequentially, but
bus bandwidth and fault isolation are much better than putting both sensors on
one 100 kHz I2C3 bus.

The I2C1 caveat is the on-board VL53L0X. It also uses default address `0x29`,
so firmware must keep `VL53L0X_XSHUT` / PC6 low whenever the front SATEL lives
on I2C1 at its default address.

The preferred future two-sensor SPI topology is:

| Signal | Rear sensor | Front sensor |
| --- | --- | --- |
| `EXT_SPI_I2C_N` | Tie to 3V3 for SPI mode | Tie to 3V3 for SPI mode |
| `EXT_MCLK_SCL` / SPI clock | Shared D13 / PA5 / SPI1_SCK -> J2 pin 6 | Shared D13 / PA5 / SPI1_SCK -> J2 pin 6 |
| `EXT_MOSI_SDA` / MOSI | Shared D11 / PA7 / SPI1_MOSI -> J2 pin 5 | Shared D11 / PA7 / SPI1_MOSI -> J2 pin 5 |
| `EXT_MISO` / MISO | Shared D12 / PA6 / SPI1_MISO -> J2 pin 4 | Shared D12 / PA6 / SPI1_MISO -> J2 pin 4 |
| `EXT_NCS` | Dedicated D8 / PB2 -> J2 pin 3 | Dedicated D10 / PA2 -> J2 pin 3 |
| `EXT_LPn` | Dedicated A1 / PC4 -> J2 pin 2 | Dedicated A0 / PC5 -> J2 pin 2 |
| `EXT_GPIO1` / INT | Dedicated A2 / PC3 -> J1 top pad | Dedicated A3 / PC2 -> J1 top pad |
| `EXT_PWR_EN` | D9 / PA15, or tied high to 3V3 | Separate GPIO preferred, or tied high to 3V3 |
| `EXT_5V0`, GND | Shared 5V to J2 pin 11 and common ground | Shared 5V to J2 pin 11 and common ground |

The fallback separate-I2C topology is:

| Signal | Rear sensor | Front sensor |
| --- | --- | --- |
| I2C SCL | A5 / PC0 / I2C3 -> J2 pin 6 | D15 / PB8 / I2C1 -> J2 pin 6 |
| I2C SDA | A4 / PC1 / I2C3 -> J2 pin 5 | D14 / PB9 / I2C1 -> J2 pin 5 |
| 5V, 3V3, GND | Shared rails; 5V to J2 pin 11 | Shared rails; 5V to J2 pin 11 |
| `SPI_I2C_N` | Tied low to GND | Tied low to GND |
| `PWR_EN` | D9 / PA15, or tied high to 3V3 | D10 / PA2, or tied high to 3V3 |
| `LPn` | Dedicated A1 / PC4 -> J2 pin 2 | Dedicated A0 / PC5 -> J2 pin 2 |
| `GPIO1 / INT` | Dedicated A2 / PC3 to J1 top pad | Dedicated A3 / PC2 to J1 top pad |
| I2C address | Default `0x29` is acceptable on I2C3 | Default `0x29` is acceptable on I2C1 while PC6 holds the on-board VL53L0X off |

Future sequencing:

1. Hold both SATEL `LPn` lines low.
2. Keep both SPI `NCS` lines high.
3. Probe and initialize one rear SATEL over the selected transport first.
4. After one-sensor SPI is verified, enable and initialize the front SATEL using
   the same transport family and a separate slot descriptor.
5. Start both sensors ranging.
6. Poll/process each slot independently. Forward safety consumes the front
   slot; reverse safety consumes the rear slot.

This sequence is the invariant that makes two always-online sensors safe
without runtime address reassignment.

A shared-bus fallback is still possible if I2C1 cannot be used, but then
independent `LPn` is mandatory and the first sensor must be reassigned before
the second sensor is released. Two awake sensors must never share address
`0x29` on the same I2C bus.

For the separate-I2C fallback, hold PC6 `VL53L0X_XSHUT` low while the front
SATEL uses I2C1 at the default address.

### Shared SCL/SDA Answer

Yes, two SATEL-VL53L8 boards can share SCL and SDA on one I2C bus. I2C is a
shared open-drain bus, so multiple devices can sit on the same SCL/SDA pair as
long as every awake device has a unique bus address and the bus capacitance stays
reasonable. For this robot, that means short wiring and the same 3.3 V logic
domain through the SATEL carrier level shifters.

The VL53L8CX complication is address collision at boot. Every VL53L8CX starts at
default address `0x29` 7-bit (`0x52` HAL 8-bit). If two SATEL boards are awake on
the same SCL/SDA pair at that address, the STM32 cannot talk to either device
reliably. The ST ULD provides `vl53l8cx_set_i2c_address()`, and its own API
comment says that when multiple sensors are connected to the same I2C line, all
other `LPn` pins need to be held low while changing one sensor address.

Shared-bus wiring is therefore allowed only with this invariant:

| Signal | Can be shared by both SATEL boards? | Requirement |
| --- | --- | --- |
| `EXT_MCLK_SCL` | Yes | Both boards connect to the same MCU I2C SCL pin. |
| `EXT_MOSI_SDA` | Yes | Both boards connect to the same MCU I2C SDA pin. |
| `EXT_5V0` | Yes | Both boards may share the IOT01A1 5V rail. |
| GND | Yes | Common ground is mandatory. |
| `EXT_SPI_I2C_N` | Yes | Tie both boards to GND for I2C mode. |
| `EXT_PWR_EN` | Yes, but less recoverable | Tie both to 3V3 or one shared GPIO. Dedicated GPIOs are better for hard recovery. |
| `EXT_LPn` | No | Each board needs its own GPIO-controlled `LPn`. |
| `EXT_GPIO1` / INT | Prefer no | Dedicated inputs make per-sensor data-ready debug possible. Polling can work without INT. |

Shared-bus boot sequence:

1. Hold both SATEL `LPn` lines low so neither sensor responds at `0x52`.
2. Release only the rear sensor `LPn`.
3. Probe/init rear at default `0x52`, then call `vl53l8cx_set_i2c_address()` to
   move it to a non-default 8-bit address, for example `0x54`.
4. Confirm the rear sensor responds at `0x54`.
5. Release the front sensor `LPn`.
6. Probe/init front at default `0x52`. It may stay at `0x52`, or firmware may
   move it to another unique address such as `0x56`.
7. Keep one `VL53L8CX_Configuration` and platform address per sensor slot, then
   poll/read the two slots sequentially.

Implementation status: the current firmware implements one active rear VL53L8CX
with boot-time probing for I2C3 first and SPI1 second. The selected transport is
installed into the VL53L8CX platform callbacks before firmware download and
ranging. The topology module and host tests encode the production preference:
shared SPI1 with unique chip-selects, unique `LPn`, and unique `GPIO1` inputs.
The I2C shared-bus rule is also preserved for fallback work: same bus plus same
runtime address is rejected; same bus plus unique runtime addresses is accepted;
missing or shared `LPn` is rejected. Runtime shared-bus I2C address sequencing is
not implemented yet.

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
- Host tests for VL53L8 config, frame encoding, BLE ToF status policy,
  reverse-safety selection, and future two-sensor topology.
- Coverage workflow in
  `firmware/stm32-mcp/docs/dev/11-firmware-test-strategy.md`.
- Firmware build if STSW-IMG040 and STM32CubeCLT dependencies are available.
- Manual wiring check against
  `firmware/stm32-mcp/docs/dev/10-vl53l8-satel-bringup.md`.
- One-rear-sensor app/firmware E2E validation for Park clearing, forward iPhone
  LiDAR BRAKE reverse escape, rear STM32 ToF BRAKE behavior, and far-range
  VL53L8 non-OK status handling.

## References

- `firmware/stm32-mcp/docs/hardware/sensors/satel-vl53l8-schematic.pdf`
- `firmware/stm32-mcp/docs/hardware/sensors/satel-vl53l8.pdf`
- `firmware/stm32-mcp/docs/hardware/sensors/an5945-how-to-connect-the-satelvl53l8-to-an-stm32-nucleo64-board-stmicroelectronics.pdf`
- ST product page for STSW-IMG040, the VL53L8CX Ultra Lite Driver.
- ST UM3109, VL53L8CX ULD user manual.
