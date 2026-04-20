# 06 — VL53L1CB Multi-Zone Time-of-Flight

A longer-range ToF sensor — the **VL53L1CB** on the ST **VL53L1-Satel**
breakout — supplements the on-board VL53L0X. It supports 1×1, 3×3, and
4×4 zone layouts up to ~3.6 m and is exposed over a dedicated BLE GATT
service (`0xFE60`) that the iOS app renders as a live heat-map grid.

This doc covers hardware wiring, the bare-driver import, ROI math, the
GATT wire format, and the iOS consumer. Prior reading: `03-architecture.md`
(scheduler / IRQ map), `04-ble-integration.md` (GATT flow), and
`05-extending-the-firmware.md` §1 (subsystem pattern).

Topics:
1. Hardware & wiring
2. Bare-driver layout
3. I²C3 platform bring-up
4. Wrapper (`tof_l1.{h,c}`)
5. Zone layouts, distance modes, and scan rate
6. ROI math
7. BLE service 0xFE60 — wire format
8. iOS client
9. Troubleshooting
10. References

---

## 1. Hardware & wiring

| Board signal | MCU pin | Function        | Satel label |
|--------------|---------|-----------------|-------------|
| Arduino A4   | **PC1** | I²C3_SDA (AF4)  | SDA         |
| Arduino A5   | **PC0** | I²C3_SCL (AF4)  | SCL         |
| 3V3          | 3V3     | Power           | AVDD / IOVDD|
| GND          | GND     | Ground          | GND         |

PC0/PC1 are the Discovery Kit's Arduino A4/A5 pads. The factory wiring
feeds the on-board VL53L0X on **I²C1 (PB8/PB9)**, which remains held in
reset via PC6 `XSHUT` LOW — the L1 sits on its own bus, so the two do
not conflict. `AVDDVCSEL` and `IOVDD` are tied to 3V3 on the Satel.

I²C3 runs at 400 kHz fast-mode. Timing word `0x10D19CE4` is reused from
the existing I²C2 bring-up (same APB1 at 80 MHz). External pull-ups on
the Satel are **not** populated; we enable MCU-side pulls in
`HAL_I2C_MspInit`.

---

## 2. Bare-driver layout

The project embeds ST's **VL53L1CB_BareDriver 6.6.19.2686**
(STSW-IMG019) verbatim, with only the platform shim replaced:

```
firmware/stm32-mcp/Drivers/VL53L1CB/
  core/
    inc/       (vl53l1_api*.h, vl53l1_error_codes.h, ...)
    src/       (vl53l1_api_*.c, vl53l1_core.c, ...)
  platform/
    inc/       (vl53l1_platform.h, vl53l1_types.h)
    src/
      vl53l1_platform.c           ← custom (HAL_I2C on hi2c3)
      vl53l1_platform_init.c      ← verbatim (ST stub)
      vl53l1_platform_ipp.c       ← verbatim
      vl53l1_platform_log.c       ← verbatim
```

Only `vl53l1_platform.c` diverges from upstream — everything else is a
literal copy so future driver updates can be dropped in by re-copying.

CMake pulls every `.c` under both `core/src` and `platform/src` via a
glob in `cmake/stm32cubemx/CMakeLists.txt` (`set(VL53L1CB_Src ...)`).
`-ffunction-sections -fdata-sections -Wl,--gc-sections` strip modes we
never call; the observed flash delta is ≈50 KB over the pre-L1 baseline.

---

## 3. I²C3 platform bring-up

Three files cooperate to stand the bus up:

1. **`Core/Src/main.c`** declares `I2C_HandleTypeDef hi2c3;`,
   implements `MX_I2C3_Init()` mirroring `MX_I2C2_Init`, and calls it
   from `main()` after `MX_I2C2_Init`.
2. **`Core/Src/stm32l4xx_hal_msp.c`** handles `I2C3` inside
   `HAL_I2C_MspInit` / `MspDeInit`: enables `__HAL_RCC_I2C3_CLK_ENABLE`
   and `__HAL_RCC_GPIOC_CLK_ENABLE`, configures PC0/PC1 as
   `GPIO_MODE_AF_OD` with `GPIO_PULLUP`, `GPIO_SPEED_FREQ_HIGH`, and
   `Alternate = GPIO_AF4_I2C3`.
3. **`Drivers/VL53L1CB/platform/src/vl53l1_platform.c`** wraps every
   read/write primitive the bare driver needs onto `HAL_I2C_Master_*`
   on `hi2c3`. `WaitMs` maps to `HAL_Delay`; `WaitUs` uses a DWT
   busy-wait.

The driver addresses the chip as 7-bit `0x29`; HAL's 8-bit API gets
`0x52` (shifted left by 1). Every multi-byte transfer is big-endian on
the wire — the platform shim handles byte-swapping.

---

## 4. Wrapper (`tof_l1.{h,c}`)

Following `05-extending-the-firmware.md §1`, the bare driver is fronted
by a narrow pair of files under `Core/`:

| Entry point              | Role                                                        |
|--------------------------|-------------------------------------------------------------|
| `TofL1_Init`             | `WaitDeviceBooted → DataInit → StaticInit`, one-shot probe. Installs a default Configure (1×1 / LONG / 33 ms). |
| `TofL1_Configure`        | `Stop → SetPresetMode → SetDistanceMode → SetMeasurementTimingBudget → (SetROI) → StartMeasurement`. Invalidates both frame buffers. |
| `TofL1_Process`          | Polls `GetMeasurementDataReady` once. On a ready zone, stashes `RangeData[0]` into the scratch buffer at `RoiNumber`. On `VL53L1_ROISTATUS_VALID_LAST` it swaps scratch → latest, bumps `seq`, sets `has_new_frame`, and re-arms with `ClearInterruptAndStartMeasurement`. |
| `TofL1_GetLatestFrame`   | Returns `const TofL1_Frame_t *` — zero-init until the first scan. |
| `TofL1_HasNewFrame` / `_ClearNewFrame` | Double-buffer flag used by `BLE_Tof_Process`. |
| `TofL1_BuildRoi`         | Pure function over plain `TofL1_Roi_t` — see §6. |

The scratch buffer rule is load-bearing: the bare driver returns one
zone per `GetMultiRangingData` call, and we must not publish a partial
grid. Invalid re-configures clear the flag so the first post-reconfig
frame always reflects the new layout.

`TofL1_BuildRoi` is kept in its own file (`Core/Src/tof_l1_roi.c`) with
no HAL includes so the host unit test in `tests/host/test_tof_l1_roi.c`
can link against it with vanilla `gcc`.

---

## 5. Zone layouts, distance modes, and scan rate

### 5.1 Layout table (`TofL1_Layout_t`)

| Layout | Zones | Preset mode                       | Typical use                        |
|--------|-------|-----------------------------------|------------------------------------|
| 1×1    | 1     | `VL53L1_PRESETMODE_RANGING`       | Single-beam, fastest (up to 50 Hz) |
| 3×3    | 9     | `VL53L1_PRESETMODE_MULTIZONES_SCANNING` | Coarse obstacle mapping       |
| 4×4    | 16    | `VL53L1_PRESETMODE_MULTIZONES_SCANNING` | Finest available grid         |

### 5.2 Distance modes (`TofL1_DistMode_t`)

| Mode   | Value | Nominal range | Notes                                   |
|--------|-------|---------------|-----------------------------------------|
| SHORT  | 1     | ≤ 1.3 m       | Best immunity to ambient light          |
| MEDIUM | 2     | ≤ 2.9 m       | Balanced, default for mixed scenes      |
| LONG   | 3     | ≤ 3.6 m       | Indoor default; weaker in bright sun    |

### 5.3 Scan rate

Approximate scan rate:

```
scan_hz  ≈  1 / (num_zones × budget_s)
```

With `num_zones = layout²` and `budget_s = budget_us / 1e6`. Measured
values on the B-L475E-IOT01A (firmware flashed on 2026-04-19):

| Layout | Budget | Observed |
|--------|--------|----------|
| 1×1    | 100 ms | ~10 Hz   |
| 3×3    | 8 ms   | ~13 Hz   |
| 4×4    | 33 ms  | ~1.9 Hz  |
| 4×4    | 8 ms   | ~7.5 Hz  |

The iOS app shows both a predicted Hz (from the formula above) and the
observed Hz (reported via `0xFE63`). Divergence > ±10 % usually means
the BLE pipeline is the bottleneck, not the sensor.

---

## 6. ROI math

SPAD coordinates run X ∈ [0, 15], Y ∈ [0, 15] with **Y growing upward**
(top-left corner = 0, 15; bottom-right = 15, 0). The driver requires
`TopLeftY ≥ BotRightY` and `TopLeftX ≤ BotRightX`.

Zones are emitted **top-to-bottom, left-to-right** so zone index `i`
maps 1:1 to the iOS grid cell `i`. `TofL1_BuildRoi` returns `TofL1_Roi_t`
tuples (not `VL53L1_UserRoi_t`) so the builder is decoupled from the
driver headers; `TofL1_Configure` translates them before calling
`VL53L1_SetROI`.

### 6.1 1×1

One ROI spanning the full array: `(0, 15, 15, 0)`.

### 6.2 3×3

Nine 6×6 ROIs with stride 5, overlapping by one SPAD on each axis. Top
row: `(0, 15, 5, 10)`, `(5, 15, 10, 10)`, `(10, 15, 15, 10)`.

### 6.3 4×4

Sixteen 4×4 ROIs, no overlap. Top-left zone: `(0, 15, 3, 12)`; next to
the right: `(4, 15, 7, 12)`; etc.

Exact tables live in `Core/Src/tof_l1_roi.c` and are asserted by the
host test in `tests/host/test_tof_l1_roi.c`.

---

## 7. BLE service 0xFE60 — wire format

### 7.1 Attribute layout

| Char | UUID  | Properties              | Size | Direction |
|------|-------|-------------------------|------|-----------|
| Config | `0xFE61` | write + write-w/o-resp  | 8 B  | iOS → MCU |
| Frame  | `0xFE62` | notify                  | 76 B | MCU → iOS |
| Status | `0xFE63` | notify + read           | 4 B  | MCU → iOS |

`BLE_CFG_SVC_MAX_NBR_CB` in `Core/Inc/ble_config.h` is bumped from 2 to
3 so `SVCCTL_RegisterSvcHandler` has room for the new service alongside
`FE40`. Requires ATT MTU ≥ 79; iOS CoreBluetooth negotiates this
automatically with BlueNRG-MS.

### 7.2 Config payload (FE61 — 8 B, little-endian)

```
offset 0  uint8_t  layout      (1, 3, or 4)
offset 1  uint8_t  dist_mode   (1=SHORT, 2=MEDIUM, 3=LONG)
offset 2  uint8_t  _reserved   (must be 0)
offset 3  uint8_t  _reserved   (must be 0)
offset 4  uint32_t budget_us   (clamped [8000, 1000000])
```

Validation errors surface in `FE63.last_error` as a `TofL1_Status_t`
code (e.g. `TOF_L1_ERR_BAD_LAYOUT = 6`). The sensor keeps running the
previous config on error.

### 7.3 Frame payload (FE62 — 76 B, little-endian)

```
offset  size  field
   0    u32   seq                   (monotonic scan counter)
   4    u16   budget_us_per_zone    (echo of last Configure)
   6    u8    layout                (1, 3, 4)
   7    u8    dist_mode             (1, 2, 3)
   8    u8    num_zones             (layout²)
   9    u8[3] _pad                  (0)
  12    Zone[16] zones              (unused slots zero)

where Zone = { u16 range_mm; u8 status; u8 _pad }    (4 B)
```

Zone order is **top-to-bottom, left-to-right**, matching the ROI table.
Unused zones are zero — iOS reads only `numZones` entries.

### 7.4 Status payload (FE63 — 4 B)

```
offset 0  uint8_t state       (0=idle, 1=running, 2=error)
offset 1  uint8_t last_error  (TofL1_Status_t; 0 = none)
offset 2  uint8_t scan_hz     (observed, integer Hz)
offset 3  uint8_t _pad
```

`BLE_Tof_Process` recomputes `scan_hz` over a sliding 1 s window and
refreshes the status characteristic once per second.

### 7.5 Zone range-status codes (from `VL53L1_RangeStatus`)

| Code | Name                    | iOS label | Usable? |
|------|-------------------------|-----------|---------|
| 0    | RANGE_VALID             | `OK`      | yes     |
| 1    | SIGMA_FAIL              | `SIG`     | yes     |
| 2    | SIGNAL_FAIL             | `SIG`     | no      |
| 4    | OUTOFBOUNDS_FAIL        | `OOB`     | no      |
| 5    | HARDWARE_FAIL           | `HW`      | no      |
| 7    | WRAP_TARGET_FAIL        | `WRP`     | no      |
| 8    | PROCESSING_FAIL         | `PROC`    | no      |
| 12   | RANGE_INVALID           | `INV`     | no      |
| 13   | MIN_RANGE_FAIL          | `MIN`     | yes     |
| 14   | NO_WRAP_CHECK_FAIL      | `NOWC`    | yes     |
| 255  | NONE                    | `—`       | no      |

---

## 8. iOS client

Files added in `openotter-ios/Sources/`:

| File                                | Role                                                      |
|-------------------------------------|-----------------------------------------------------------|
| `Capture/TofTypes.swift`            | `TofFrame`, `ZoneReading`, `TofConfig`, `TofState`, `VL53L1RangeStatus`. |
| `Capture/STM32TofService.swift`     | `ObservableObject` singleton. Static `parseFrame(_:Data)` validator, `sendConfig`, frame/status notification handlers. |
| `Views/TofGridView.swift`           | `LazyVGrid` heat map; hue ramps red → blue across `maxRangeMm`, invalid cells grey with dashed border. |

Wiring touched:

- `Capture/STM32BleManager.swift` — discovers `FE60`, attaches the
  three chars to `STM32TofService.shared`, routes `FE62`/`FE63`
  notifications.
- `Capture/STM32ControlViewModel.swift` — exposes `@Published tofFrame`,
  `tofConfig`, `tofScanHz`; debounces (250 ms) layout / distMode /
  budget setters before calling `sendConfig`.
- `Views/STM32ControlView.swift` — inserts a `TOF DEBUG` `GroupBox`
  between the ESC telemetry and direct-control cards.

`maxRangeMm` in the grid is pinned to the current distance mode
(SHORT → 1300, MEDIUM → 2900, LONG → 3600). Far-range data would
otherwise compress into a single hue once the sensor reads a distant
target.

---

## 9. Troubleshooting

**`VL53L1 sensor id = 0xFFFFFFFF` on boot**
I²C NACK. Check: 3V3 present, PC0/PC1 wiring, internal pull-ups in
`HAL_I2C_MspInit`, Satel has no competing pull-ups populated, I²C3
clock enabled.

**Sensor probes OK but no frames ever arrive**
Confirm `TofL1_Init` is called *after* `MX_I2C3_Init`. `TofL1_Process`
must tick every main-loop iteration. The first scan can take > 1 s for
large budgets on 4×4.

**Frames have `status = 255` for every zone**
The bare driver returned `NumberOfObjectsFound == 0`. Target may be
beyond the selected distance mode, or reflective surface is too dim.
Raise the timing budget or switch to LONG mode.

**BLE connects but nRF Connect sees only FE40**
`BLE_CFG_SVC_MAX_NBR_CB` still 2 — bump it to 3. Also check the main
loop actually calls `BLE_Tof_Init()` after `BLE_App_Init`.

**FE62 notifications arrive but grid stays blank on iOS**
Grid needs notify enabled on both FE62 and FE63. `STM32TofService.attach`
calls `setNotifyValue(true, for:)` for both — if one of the chars was
missed in discovery, `STM32BleManager.didDiscoverCharacteristicsFor`
never ran `attach`, so no subscription happened.

**Config writes silently drop**
`FE63.last_error` reports the exact `TofL1_Status_t`. `BAD_LAYOUT` and
`BAD_MODE` come from the `_reserved` bytes being nonzero or an
out-of-range value — re-check the iOS `sendConfig` payload.

---

## 10. References

- [STSW-IMG019 VL53L1CB Bare Driver](https://www.st.com/en/embedded-software/stsw-img019.html)
- [UM2133 — VL53L1 datasheet](https://www.st.com/resource/en/user_manual/um2133-*.pdf)
- [UM2978 — X-CUBE-TOF1 integration guide](https://www.st.com/resource/en/user_manual/um2978-*.pdf)
- VL53L1-Satel breakout schematic — `docs/hardware/sensors/vl53l1-satel.pdf`.
- Design spec — `docs/superpowers/specs/2026-04-19-vl53l1cb-multizone-tof-design.md`.
- Implementation plan — `~/.claude/plans/steady-jumping-toast.md`.
