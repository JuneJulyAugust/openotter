# VL53L1CB Multi-Zone ToF Integration — Design Spec

Date: 2026-04-19
Author: Fang Xu
Status: Approved for implementation planning

## 1. Goal

Replace the VL53L0X short-range ToF usage with a VL53L1CB long-range ToF
on a VL53L1-Satel breakout, expose 1×1 / 3×3 / 4×4 multi-zone depth
readings over BLE for debug purposes, and visualize the depth grid in
the iOS STM32 debug view. The VL53L1CB must be runtime-configurable
from the iOS app (layout, distance mode, timing budget).

## 2. Hardware

| Signal | Breakout pin | Board pin | STM32 pin | Function |
|--------|--------------|-----------|-----------|----------|
| SDA    | SDA          | ARD A4    | PC1       | I²C3_SDA (AF4) |
| SCL    | SCL          | ARD A5    | PC0       | I²C3_SCL (AF4) |
| VDD    | 3V3          | 3V3       | —         | 2.6–3.5 V |
| GND    | GND          | GND       | —         | — |
| XSHUT  | (not wired)  | —         | —         | Sensor auto-boots at power-up |
| GPIO1  | (not wired)  | —         | —         | No IRQ — use polled ranging |

- Default I²C address: `0x52` (8-bit write) / `0x29` (7-bit).
- On-board VL53L0X (I²C1, PC6 XSHUT) stays disabled: XSHUT held LOW by
  `MX_GPIO_Init`; I²C1 left uninitialized.
- I²C3 adds no bus collision with I²C2 (internal MEMS) or I²C1 (VL53L0X,
  unused).

## 3. Software architecture

### 3.1 Subsystems

```
┌───────────────────────────────────────────────────────────────┐
│ B-L475E-IOT01A                                                │
│                                                               │
│  VL53L1-Satel ──I2C3(PC1/PC0)── STM32L475 ──SPI3── BlueNRG-MS │
│                                   │                           │
│                                   ├── tof_l1.c (wrapper)      │
│                                   ├── Drivers/VL53L1CB/       │
│                                   │   (ST bare driver,        │
│                                   │    black-box HAL)         │
│                                   ├── ble_app.c (existing)    │
│                                   └── ble_tof.c (new svc)     │
└───────────────────────────────────────────────────────────────┘
                                     │ BLE GATT
                                     ▼
┌───────────────────────────────────────────────────────────────┐
│ iPhone (openotter-ios)                                        │
│                                                               │
│  STM32ControlView ── TofGridView ── TofDebugViewModel         │
│                                         │                     │
│                                         └── STM32BleManager   │
│                                             (extend: discover │
│                                              + parse 0xFE60)  │
└───────────────────────────────────────────────────────────────┘
```

### 3.2 Firmware files

| File | Purpose |
|------|---------|
| `firmware/stm32-mcp/Drivers/VL53L1CB/core/**` | ST bare driver, copied verbatim from `docs/STSW-IMG019/VL53L1CB_BareDriver_6.6.19.2686/BareDriver/core/`. Do not edit. |
| `firmware/stm32-mcp/Drivers/VL53L1CB/platform/**` | ST platform layer. `vl53l1_platform.c` is replaced with our I²C3-backed implementation; the other files (`vl53l1_platform_init.c`, `vl53l1_platform_ipp.c`, `vl53l1_platform_log.c`) copied verbatim. |
| `firmware/stm32-mcp/Core/Inc/tof_l1.h` | Public interface of the wrapper. |
| `firmware/stm32-mcp/Core/Src/tof_l1.c` | Wrapper: owns `VL53L1_Dev_t`, builds ROI tables, runs lifecycle, exposes frame to the rest of the firmware. |
| `firmware/stm32-mcp/Core/Inc/ble_tof.h` / `.c` | New GATT service 0xFE60 (config write + frame notify + status). |
| `firmware/stm32-mcp/Core/Src/main.c` | Patch: add `hi2c3`, call `MX_I2C3_Init`, call `TofL1_Init` + `BLE_Tof_Init` + `TofL1_Process` + `BLE_Tof_Process`. |
| `firmware/stm32-mcp/cmake/stm32cubemx/CMakeLists.txt` | Patch: add new `.c` files + bare-driver include dirs; add `-ffunction-sections -fdata-sections` C flags and `-Wl,--gc-sections` linker flag if not already present. |
| `firmware/stm32-mcp/Core/Inc/ble_config.h` | Patch: `BLE_CFG_SVC_MAX_NBR_CB` 2→3. |

### 3.3 iOS files

| File | Purpose |
|------|---------|
| `openotter-ios/Sources/Capture/STM32TofService.swift` (new) | GATT client for 0xFE60; publishes `TofFrame`. |
| `openotter-ios/Sources/Capture/STM32BleManager.swift` (patch) | Discover 0xFE60 in addition to 0xFE40; hand off chars to `STM32TofService`. |
| `openotter-ios/Sources/Capture/STM32ControlViewModel.swift` (patch) | Forward frames + config setters. |
| `openotter-ios/Sources/Views/TofGridView.swift` (new) | Pure SwiftUI view renders N×N depth grid. |
| `openotter-ios/Sources/Views/STM32ControlView.swift` (patch) | Add "TOF DEBUG" `GroupBox` hosting config controls + `TofGridView`. |

### 3.4 Documentation deliverable

`firmware/stm32-mcp/docs/dev/06-vl53l1cb-multizone-tof.md` — sections listed in §9.

## 4. Firmware wrapper — `tof_l1`

### 4.1 Public interface

```c
typedef enum { TOF_LAYOUT_1x1 = 1, TOF_LAYOUT_3x3 = 3, TOF_LAYOUT_4x4 = 4 } TofL1_Layout_t;
typedef enum { TOF_DIST_SHORT = 1, TOF_DIST_MEDIUM = 2, TOF_DIST_LONG = 3 } TofL1_DistMode_t;

typedef struct __attribute__((packed)) {
    uint32_t seq;                   /* monotonic frame counter                 */
    uint16_t budget_us_per_zone;    /* echoes latest applied budget            */
    uint8_t  layout;                /* 1, 3, or 4                              */
    uint8_t  dist_mode;             /* 1=SHORT 2=MEDIUM 3=LONG                 */
    uint8_t  num_zones;             /* 1, 9, or 16                             */
    uint8_t  _pad[3];
    struct {
        uint16_t range_mm;          /* 0 if invalid                            */
        uint8_t  status;            /* VL53L1 RangeStatus (0 = valid)          */
        uint8_t  _pad;
    } zones[16];                    /* always 16 slots; unused slots zeroed    */
} TofL1_Frame_t;                    /* sizeof == 12 + 16*4 = 76                */

int   TofL1_Init(void);
int   TofL1_Configure(TofL1_Layout_t layout, TofL1_DistMode_t dist, uint32_t budget_us);
void  TofL1_Process(void);
const TofL1_Frame_t *TofL1_GetLatestFrame(void);
uint8_t TofL1_HasNewFrame(void);            /* latches; cleared on read        */
```

### 4.2 Lifecycle

1. `TofL1_Init()` — runs `MX_I2C3_Init`; calls `VL53L1_WaitDeviceBooted`,
   `VL53L1_DataInit`, `VL53L1_StaticInit`; applies a default config
   (`TOF_LAYOUT_1x1`, `TOF_DIST_LONG`, 33 ms) via `TofL1_Configure`.
2. `TofL1_Configure(...)` — validates inputs; runs
   `VL53L1_StopMeasurement` (idempotent on first call);
   `VL53L1_SetPresetMode(RANGING or MULTIZONES_SCANNING)`;
   `VL53L1_SetDistanceMode(...)`;
   `VL53L1_SetMeasurementTimingBudgetMicroSeconds(...)`;
   builds `VL53L1_RoiConfig_t` via `TofL1_BuildRoi(layout, &roiConfig)`
   and calls `VL53L1_SetROI` (skipped for 1×1);
   `VL53L1_StartMeasurement`.
3. `TofL1_Process()` — per main-loop iteration:
   - `VL53L1_GetMeasurementDataReady(&ready)`; if `!ready`, return.
   - `VL53L1_GetMultiRangingData(&raw)` → copy each
     `RangeData[i].{RangeMilliMeter, RangeStatus}` into
     `frame.zones[i]`; set `frame.seq++`; set `has_new_frame = 1`.
   - `VL53L1_ClearInterruptAndStartMeasurement`.

### 4.3 ROI table (pure function, host-testable)

`TofL1_BuildRoi(layout, &out)` fills `NumberOfRoi` and `UserRois[]`.
VL53L1 SPAD array is 16×16. Minimum ROI side = 4 SPADs.
Coordinate convention: (0,0) = bottom-left in the API, (15,15) = top-right.
`TopLeftX ≤ BotRightX`, `TopLeftY ≥ BotRightY`.

| Layout | Zones | Zone SPADs | Tile coverage (x, y) |
|--------|-------|------------|----------------------|
| 1×1    | 1     | 16×16      | (0..15, 0..15)       |
| 3×3    | 9     | 5×5        | x-tiles: 0..4, 5..9, 10..14 (pixel 15 col unused) ; y-tiles: 10..14 (top), 5..9, 0..4 |
| 4×4    | 16    | 4×4        | x-tiles: 0..3, 4..7, 8..11, 12..15 ; y-tiles (row order top→bottom): 12..15, 8..11, 4..7, 0..3 |

Zone emission order is row-major **top-to-bottom, left-to-right** — matches how the iOS grid view iterates cells, so `zones[i]` maps 1:1 to SwiftUI grid index `i` with no remapping.

### 4.4 Platform port (`vl53l1_platform.c`)

Only the thin I/O shim is ours; everything else (core algorithms, ROI
scheduling, register tables) comes from the bare driver.

```c
extern I2C_HandleTypeDef hi2c3;

VL53L1_Error VL53L1_WriteMulti(VL53L1_DEV dev, uint16_t idx, uint8_t *buf, uint32_t count) {
    uint8_t tx[2 + VL53L1_I2C_WRITE_MAX];   /* idx(2 BE) + payload */
    tx[0] = idx >> 8; tx[1] = idx & 0xFF;
    memcpy(&tx[2], buf, count);
    return (HAL_I2C_Master_Transmit(&hi2c3, dev->I2cDevAddr, tx, count + 2, HAL_MAX_DELAY) == HAL_OK)
           ? VL53L1_ERROR_NONE : VL53L1_ERROR_CONTROL_INTERFACE;
}

VL53L1_Error VL53L1_ReadMulti(VL53L1_DEV dev, uint16_t idx, uint8_t *buf, uint32_t count) {
    uint8_t addr[2] = { idx >> 8, idx & 0xFF };
    if (HAL_I2C_Master_Transmit(&hi2c3, dev->I2cDevAddr, addr, 2, HAL_MAX_DELAY) != HAL_OK)
        return VL53L1_ERROR_CONTROL_INTERFACE;
    return (HAL_I2C_Master_Receive(&hi2c3, dev->I2cDevAddr, buf, count, HAL_MAX_DELAY) == HAL_OK)
           ? VL53L1_ERROR_NONE : VL53L1_ERROR_CONTROL_INTERFACE;
}
```

`WrByte`/`WrWord`/`WrDWord` and their `Rd*` counterparts compose on top.
`WaitMs → HAL_Delay`, `WaitUs → DWT cycle-counter busy-wait`,
`GetTickCount → HAL_GetTick`.

`VL53L1_I2C_WRITE_MAX` set to 256 in `vl53l1_platform_user_defines.h`
(matches what the bare driver assumes). All calls are blocking; the
longest single transfer in normal operation is the boot-time preset
upload (~135 bytes).

## 5. BLE protocol — new service 0xFE60

| UUID   | Kind    | Property       | Fixed length | Payload |
|--------|---------|----------------|--------------|---------|
| 0xFE60 | Service | —              | —            | ToF debug service |
| 0xFE61 | Char    | Write          | 8 B          | `[u8 layout][u8 dist_mode][u8 rsvd][u8 rsvd][u32 budget_us LE]` |
| 0xFE62 | Char    | Notify         | 76 B         | `TofL1_Frame_t` packed LE (§4.1) |
| 0xFE63 | Char    | Notify + Read  | 4 B          | `[u8 state][u8 last_error][u8 scan_hz][u8 rsvd]` |

### 5.1 Config write validation (firmware)

| Field | Accepted | `last_error` on reject |
|-------|----------|------------------------|
| `layout` | 1, 3, 4 | 1 |
| `dist_mode` | 1 (SHORT), 2 (MEDIUM), 3 (LONG) | 2 |
| `budget_us` | clamped to `[min_per_mode, 1 000 000]` where min = 8000 (SHORT), 16000 (MEDIUM), 33000 (LONG) | 0 (clamped silently; not an error) |

On accept, call `TofL1_Configure(...)`; on first successful frame after
reconfig, `scan_hz` in 0xFE63 updates.

### 5.2 Frame notify

Sent from `BLE_Tof_Process` only when `TofL1_HasNewFrame() == 1`:

```c
void BLE_Tof_Process(void) {
    if (!BLE_App_IsConnected()) return;
    if (!TofL1_HasNewFrame())   return;
    const TofL1_Frame_t *f = TofL1_GetLatestFrame();
    aci_gatt_update_char_value(bleTofCtx.svcHandle,
                               bleTofCtx.frameCharHandle,
                               0, sizeof(*f), (uint8_t *)f);
}
```

### 5.3 ATT MTU requirement

76-byte payload + 3-byte ATT notification header = 79 B → requires
ATT_MTU ≥ 79. BlueNRG-MS default MTU is 23. Client (iOS) triggers MTU
exchange automatically by calling
`peripheral.maximumWriteValueLength(for: .withoutResponse)` during
`didDiscoverCharacteristicsFor`; CoreBluetooth negotiates up to 158 B
with BlueNRG-MS. If negotiation fails (log-visible as MTU=23), frame
notify falls back to a firmware error — no chunking is implemented
(YAGNI; iOS negotiation is reliable on iOS 10+).

### 5.4 `BLE_CFG_SVC_MAX_NBR_CB`

Currently 2. Bump to 3 since `BLE_Tof_Init` registers its own
`SVCCTL_RegisterSvcHandler`.

## 6. iOS side

### 6.1 `STM32TofService` (new, `Sources/Capture/STM32TofService.swift`)

```swift
final class STM32TofService: NSObject, ObservableObject {
    @Published private(set) var latestFrame: TofFrame?
    @Published private(set) var state: TofState = .idle   // idle / running / error
    @Published private(set) var scanHz: UInt8 = 0

    /// Called by STM32BleManager once the 0xFE60 service and its three
    /// characteristics have been discovered.
    func attach(peripheral: CBPeripheral, frameChar: CBCharacteristic,
                configChar: CBCharacteristic, statusChar: CBCharacteristic)

    /// Sends an 8-byte config packet to 0xFE61.
    func sendConfig(layout: UInt8, distMode: UInt8, budgetUs: UInt32)

    /// Called by the BLE manager when a notify arrives for 0xFE62.
    func handleFrameNotification(_ data: Data)
}

struct TofFrame: Equatable {
    let seq: UInt32
    let budgetUsPerZone: UInt16
    let layout: UInt8
    let distMode: UInt8
    let zones: [ZoneReading]        // count == layout * layout
    let arrivalTime: Date
}
struct ZoneReading: Equatable {
    let rangeMm: UInt16
    let status: UInt8
    var isValid: Bool { status == 0 }
}
```

Frame parsing is a pure function on `Data` → `TofFrame?` that returns
nil if size ≠ 76 or if `layout ∉ {1,3,4}`. Unit-testable.

### 6.2 `STM32BleManager` patch

- Add `private let tofServiceUUID = CBUUID(string: "FE60")`, `tofFrameCharUUID = FE62`, `tofConfigCharUUID = FE61`, `tofStatusCharUUID = FE63`.
- In `didDiscoverServices`: discover both 0xFE40 and 0xFE60.
- In `didDiscoverCharacteristicsFor service`: dispatch on service UUID; when 0xFE60, call `STM32TofService.shared.attach(...)` and subscribe to notify for 0xFE62/0xFE63.
- In `didUpdateValueFor`: route 0xFE62/0xFE63 to `STM32TofService.shared.handleFrameNotification(_:)`.

### 6.3 `STM32ControlViewModel` patch

Add:
- `@Published var tofFrame: TofFrame?`
- `@Published var tofConfig = TofConfig(layout: 1, distMode: 3, budgetUs: 33_000)`
- `@Published var tofScanHz: UInt8 = 0`
- `func setTofLayout(_ layout: UInt8)` / `setTofDistMode(_ mode: UInt8)` / `setTofBudgetMs(_ ms: Int)` — each debounces (250 ms, same as steering) before calling `STM32TofService.shared.sendConfig`.

### 6.4 `TofGridView` (new, `Sources/Views/TofGridView.swift`)

Pure `View`:

```swift
struct TofGridView: View {
    let frame: TofFrame
    let maxRangeMm: UInt16        // from distMode: 1300 / 3000 / 4000
    var body: some View { /* LazyVGrid of N×N cells, zone row-major top→bottom */ }
}

struct TofCell: View {
    let reading: ZoneReading
    let maxRangeMm: UInt16
    var body: some View { /* background color, range label, status label */ }
}
```

Cell visuals (per Q4/C):
- Background: HSB gradient. `hue = clamped(range_mm / maxRange) * 0.66` (red → blue). Out-of-range or `!isValid` → `Color.gray` with diagonal stripe pattern.
- Label: `"\(range_mm)\nmm"` in monospaced caption; abbreviated status below (`OK` / `SIG` / `SAT` / `OOB` / `FAIL`).
- Border: 2 pt, color by status (`green` valid, `yellow` degraded 2/4/7, `red` fail).

### 6.5 `STM32ControlView` patch

New `GroupBox` card **after** ESC telemetry, **before** DIRECT CONTROL:

- Header: `Label("TOF DEBUG", systemImage: "square.grid.3x3.fill")`.
- Content:
  1. Layout picker: `Picker` segmented `1×1` / `3×3` / `4×4`.
  2. Distance mode picker: segmented `Short` / `Medium` / `Long`.
  3. Budget slider: 8–200 ms (step 1), displays predicted frame rate
     `1000 / (budget_ms × num_zones)` Hz.
  4. `TofGridView(frame: viewModel.tofFrame ?? .empty(for: layout), maxRangeMm: …)`.
  5. Footer: `seq={} | {} Hz | last: {hh:mm:ss.SSS}`.
- Whole card disabled + greyed when `viewModel.status != .connected`,
  matching DIRECT CONTROL styling.

## 7. Testing

| Layer | Test |
|-------|------|
| Firmware build | `./build.sh` succeeds; report flash/RAM delta (target < 40 KB flash over baseline after GC). |
| Firmware host-unit | Compile `tof_l1_roi.c` (pure `TofL1_BuildRoi`) + gtest/cmocka on macOS. Assert exact SPAD coords for all 3 layouts. |
| Firmware bringup | One-shot boot message via UART1 printing `VL53L1_GetSensorId() == 0xEACC`. Removed after bringup. |
| BLE wire | With `nRF Connect`: connect to `OPENOTTER-MCP`, write `01 03 00 00 A0 86 01 00` (layout=1, LONG, 100 000 µs) to 0xFE61, enable notify on 0xFE62; expect 76-B frames ~10 Hz. Then write `03 01 00 00 40 1F 00 00` (layout=3, SHORT, 8 000 µs); expect ~13 Hz, 9 zones populated. |
| iOS preview | SwiftUI preview of `TofGridView` with canned 4×4 random-depth frame. No device required. |
| iOS E2E | Flash firmware, open app, open STM32 Control tab, verify grid updates as hand is waved in front of sensor; verify layout/mode/budget writes reconfigure the grid dimensions. |

## 8. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Bare driver bloats flash past STM32L475's 1 MB | `-Wl,--gc-sections` + only link used histogram/xtalk modules. Expect ~40–80 KB. Verify build. |
| I²C3 timing word wrong for SYSCLK 80 MHz | Use same 0x10D19CE4 as I²C2 (documented in reference manual for 80 MHz APB1). Confirm with `HAL_I2C_GetState` + one read of `VL53L1_GetSensorId`. |
| Multi-zone ranges degrade in LONG mode (< 3 zones useful beyond ~1.5 m) | Document in §5 of dev doc; not a bug. |
| 76-B notify fails on 23-B MTU | Trigger MTU exchange client-side via `peripheral.maximumWriteValueLength(for:)`. Negotiation is automatic on iOS 10+ with BlueNRG-MS. |
| Bare-driver `#include` paths collide with `config.h` used by BLE middleware | Place bare-driver includes *after* BLE include dirs in CMakeLists; bare driver uses `vl53l1_platform_user_config.h`, not `config.h`. |
| I²C3 pins (PC0/PC1) conflict with `ARD_A0..A5` in `MX_GPIO_Init` (all 6 pins currently set to `GPIO_MODE_ANALOG_ADC_CONTROL`) | `MX_I2C3_Init` reconfigures PC0/PC1 as `GPIO_MODE_AF_OD` AF4 + pull-up via `HAL_I2C_MspInit`. MX_GPIO_Init runs first and is overridden — acceptable and mirrors how BLE middleware reconfigures SPI3 pins. |

## 9. Documentation — `docs/dev/06-vl53l1cb-multizone-tof.md`

Sections:
1. **Hardware & pinout** — breakout photo, I²C3 wiring (PC0/PC1), default address 0x52, no XSHUT/IRQ wired (polled ranging), 2.6–3.5 V supply.
2. **I²C protocol** — 16-bit BE register addressing, 8-bit device address 0x52, 400 kHz fast-mode, pull-up requirement (on-breakout 10 kΩ).
3. **Sensor modes** — preset modes (RANGING, MULTIZONES_SCANNING, AUTONOMOUS, LITE_RANGING, LOWPOWER_AUTONOMOUS, PROXY — we use the first two), distance modes (SHORT/MEDIUM/LONG), timing budget ranges, effective max range per combo (dark and bright, from UM2133 Table 7). Mode summary table repeats in §8 of this spec.
4. **Zone configuration** — SPAD geometry (16×16), `VL53L1_UserRoi_t` layout, Y-axis convention, min 4×4 SPADs, when `MULTIZONES_SCANNING` is required (any layout > 1×1), emission order.
5. **Data rate math** — `scan_period_ms ≈ num_zones × (budget_ms + 1)` + inter-measurement gap. Table of observed rates by layout/budget.
6. **API lifecycle** — canonical sequence: `WaitDeviceBooted → DataInit → StaticInit → SetPresetMode → SetDistanceMode → SetMeasurementTimingBudget → SetROI → StartMeasurement`; loop: `GetMeasurementDataReady → GetMultiRangingData → ClearInterruptAndStartMeasurement`.
7. **BLE wire format** — char table, 76-byte frame layout (byte-level).
8. **Mode summary table** — copy of §8 preview in this spec with the multi-zone entries.
9. **iOS rendering** — `TofGridView` contract, zone-to-cell mapping, color + border semantics.
10. **Troubleshooting** — typical errors (`VL53L1_ERROR_CONTROL_INTERFACE` = NACK: check wiring + pull-ups; `RangeStatus 4` = signal fail: budget too small / reflectivity low; `RangeStatus 7` = wrap-around: target beyond max range).

## 10. Out of scope

- Sensor calibration (ref-SPAD, offset, xtalk) — use factory defaults. Add later if needed.
- Using ToF data in the control loop (collision avoidance). This is debug-only for v1.
- Fusing ToF with VL53L0X. VL53L0X is disabled.
- Android client. iOS only.
