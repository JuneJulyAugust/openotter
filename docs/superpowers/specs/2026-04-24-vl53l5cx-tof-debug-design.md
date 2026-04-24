# VL53L5CX ToF Debug Integration Design

Date: 2026-04-24
Status: Approved for implementation planning

## Goal

Add VL53L5CX support for the X-STM32MP-MSP01 expansion board connected to the
B-L475E-IOT01A1, stream 4x4 or 8x8 depth maps to the iOS app for debug and
mode tuning, and keep the existing VL53L1CB firmware code available. Reverse
safety remains on the existing VL53L1CB path until VL53L5CX data has been
validated in real scenes.

## Hardware Decision

UM3076 Table 3 and Figure 30 define the MSP01 40-pin GPIO connector and the
VL53L5CX wiring:

| IOT01A1 signal | MSP01 signal | Firmware pin | Decision |
|---|---|---|---|
| 3V3 | 3V3, pin 1 or 17 | power | Use 3.3 V only. Do not connect IOT01A1 5V to MSP01 3V3. |
| GND | GND, any connector ground | ground | Required. |
| A5 | SCL, pin 5 | PC0 / I2C3_SCL | Use existing I2C3 SCL. |
| A4 | SDA, pin 3 | PC1 / I2C3_SDA | Use existing I2C3 SDA. |
| A2 | GPIO_VL53L_INT, pin 35 | PC3 | Configure as input first; leave EXTI-ready for later. |
| A1 | GPIO_VL53L_I2C_RST, pin 38 | PC4 | Configure as push-pull output and toggle during boot/recovery. |

The MSP01 shifts all sensor-side 1.8 V signals to the 40-pin connector through
ST2378E level translators. The IOT01A1 side can use 3.3 V I2C/GPIO logic.

VL53L5CX uses 8-bit I2C address 0x52, the same 7-bit address 0x29 as many ST
ToF parts. Only one ToF sensor should be physically connected to I2C3 at a time
unless reset/address sequencing is added later.

## Constraints

- Keep `tof_l1.*`, `tof_l1_roi.*`, and the VL53L1CB driver in-tree.
- Make VL53L5CX the active debug ToF backend for this hardware.
- Do not route VL53L5CX into reverse safety yet.
- Preserve the current Debug-mode gate: depth frames stream only in Debug mode.
- Avoid large refactors outside ToF transport, driver selection, and iOS ToF
  debug UI.
- Use chunked BLE notifications because BlueNRG-MS is effectively constrained
  to 20-byte notification values in this project.

## Architecture

The existing FE60 ToF service becomes sensor-generic. Firmware owns one active
debug backend selected at build time:

```
MSP01 VL53L5CX
  -> I2C3 PC0/PC1 + reset PC4 + optional INT PC3
  -> tof_l5.c wrapper
  -> tof_debug.c generic frame/config API
  -> ble_tof.c FE60 chunk stream
  -> STM32TofService.swift
  -> TofGridView 4x4/8x8
```

The VL53L1CB backend remains available as legacy code, but FE60 debug streaming
uses VL53L5CX by default for this feature. Later reverse-safety migration will
read from the same generic frame representation after field validation.

## Firmware Components

| Component | Responsibility |
|---|---|
| `Drivers/VL53L5CX/` | ST VL53L5CX Ultra Lite Driver source plus STM32 HAL platform port. |
| `tof_l5.h/.c` | Owns VL53L5CX device object, reset sequence, init, config, polling, latest frame buffer. |
| `tof_types.h` | Shared sensor-agnostic frame/config/status structs for BLE and tests. |
| `tof_frame_codec.h/.c` | Pure chunk encoder for variable-size ToF frames. Host-testable. |
| `ble_tof.c` | Keeps FE60 UUIDs but updates config parsing and frame chunking for generic frames. |
| `main.c` | Initializes MSP01 reset/INT pins, starts active backend, calls process functions. |
| `stm32l4xx_hal_msp.c` | Keeps I2C3 on PC0/PC1 with pull-ups. |

## VL53L5CX Driver Model

Use STSW-IMG023 Ultra Lite Driver APIs:

- `vl53l5cx_init`
- `vl53l5cx_set_resolution`
- `vl53l5cx_set_ranging_frequency_hz`
- `vl53l5cx_set_integration_time_ms`
- `vl53l5cx_start_ranging`
- `vl53l5cx_check_data_ready`
- `vl53l5cx_get_ranging_data`
- `vl53l5cx_stop_ranging`

The platform layer maps ULD reads/writes to blocking HAL I2C on `hi2c3`.
Default bus speed stays compatible with current I2C3 timing first; increasing
toward VL53L5CX's 1 Mbit/s maximum is a later optimization after basic bring-up.

## Config Model

FE61 remains an 8-byte write to avoid changing characteristic length:

```
offset 0  u8  sensor_type       1=VL53L1CB legacy, 2=VL53L5CX
offset 1  u8  layout            1,3,4 for L1; 4 or 8 for L5
offset 2  u8  profile           L1 distance mode or L5 ranging profile
offset 3  u8  frequency_hz      L5 target ranging frequency; 0 means default
offset 4  u16 integration_ms    L5 integration time; L1 ignores
offset 6  u16 budget_ms         L1 timing budget or reserved for L5
```

For this feature, iOS sends `sensor_type=2`, `layout=4 or 8`, profile `1`
for normal continuous mode, and conservative defaults for frequency and
integration. Firmware rejects unsupported combinations without stopping the
currently running stream.

## Frame Model

`TofFrameV2` is not sent as one packed struct. It is serialized into a compact
byte stream and split into 20-byte BLE notifications:

```
Frame header:
  u8  version          = 2
  u8  sensor_type      = 1 L1, 2 L5
  u8  layout           = zones per side
  u8  zone_count       = layout * layout
  u32 seq
  u32 tick_ms
  u16 frame_len        = bytes after chunk header
  u8  profile
  u8  reserved

Zone entry, repeated zone_count:
  u16 range_mm
  u8  status
  u8  flags
```

BLE chunk notification:

```
offset 0  u8 chunk_index, high bit set on final chunk
offset 1  u8 frame_seq_low
offset 2..19 payload bytes
```

The first payload byte of chunk 0 is the frame header version. iOS drops any
out-of-order chunks or sequence mismatch and waits for the next chunk 0.

## iOS Components

| Component | Responsibility |
|---|---|
| `TofTypes.swift` | Add sensor type, V2 config, V2 frame parser, generic zone status. |
| `STM32TofService.swift` | Reassemble variable-length chunk stream and parse V2 frames. |
| `STM32ControlViewModel.swift` | Hold selected resolution/frequency/integration and send FE61 config. |
| `STM32ControlView.swift` | Expose controls for 4x4/8x8, frequency, integration, status counters. |
| `TofGridView.swift` | Render 8x8 without layout shifts; keep 4x4 support. |

The existing L1 V1 parser can remain for compatibility during transition, but
the debug card should prefer V2 frames when present.

## Error Handling

- Missing sensor: firmware status moves to error and reports `NO_SENSOR`.
- Bad config: status reports the error; current stream continues.
- Driver I/O failure: stop ranging, toggle reset PC4, reinitialize once, then
  report recovered or driver-dead.
- BLE chunk overflow: skip current frame and try the next one; do not block the
  control service.
- iOS parse failure: increment dropped-frame counter and keep last good frame.

## Testing

Firmware host tests:

- V2 frame serialization for 4x4 and 8x8.
- Chunk boundaries with 18-byte payload chunks.
- Config validation for supported and rejected VL53L5CX modes.
- Existing L1 ROI and reverse-safety tests must keep passing.

iOS tests:

- Parse a V2 4x4 frame.
- Parse a V2 8x8 frame.
- Drop out-of-order chunks.
- Encode VL53L5CX FE61 config bytes.

Hardware validation:

- UART boot log shows VL53L5CX probe/init success.
- Reset pin PC4 toggles low/high during boot.
- 4x4 frames arrive in iOS debug UI.
- 8x8 frames arrive without stale layout or broken cell count.
- Observed Hz is stable enough for later reverse-safety evaluation.

## References

- `firmware/stm32-mcp/docs/hardware/sensors/um3076-getting-started-with-the-xstm32mpmsp01-expansion-board-for-the-stm32mp157fdk2-discovery-kit-stmicroelectronics.pdf`
- ST VL53L5CX product page: https://www.st.com/content/st_com/en/products/imaging-and-photonics-solutions/time-of-flight-sensors/vl53l5cx.html
- ST VL53L5CX datasheet: https://www.st.com/resource/en/datasheet/vl53l5cx.pdf
- STSW-IMG023 Ultra Lite Driver: https://www.st.com/en/embedded-software/stsw-img023.html

## Self-Review

- No placeholders remain.
- Scope is limited to debug streaming; reverse-safety migration is explicitly
  out of scope.
- Wiring warning is explicit: 5 V must not feed MSP01 3V3.
- Protocol keeps FE60 service while making frame size variable for 8x8.
