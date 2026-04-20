# 04 — BLE Integration

This document describes how the OpenOtter firmware integrates the
BlueNRG-MS BLE stack, how GATT is wired to the PWM actuators, how
connection events flow between the module and the iOS app, and — most
importantly — **where this code came from** so future contributors can
trace it back to upstream sources.

Cross-references:
- High-level code layout and the `main` loop: `03-architecture.md`
- Board-level BLE smoke test: `02-board-bringup.md`

---

## 1. Hardware stack

```
  ┌───────────────────┐                        ┌──────────────────┐
  │                   │    SPI3 @ 8 MHz       │                  │
  │  STM32L475 (M4)   │ ◀───── MOSI/MISO ─────▶│  SPBTLE-RF       │
  │                   │    GPIO reset, IRQ     │  (BlueNRG-MS)    │
  │   application +   │                        │   network proc.  │
  │   BLE middleware  │                        │                  │
  └───────────────────┘                        └──────────────────┘
          ▲                                             ▲
          │ 1 ms SysTick, RTC wakeup                    │ BT 4.0 LE radio
          │                                             │
          └──────── main loop (cooperative sched) ──────┘
                                                        │
                                                        ▼
                                                  iOS "OpenOtter" app
```

BlueNRG-MS is a **network processor**: it runs the full BLE controller +
host stack internally, exposes a vendor-specific HCI (Host Controller
Interface) over SPI, and accepts ACI (Application Command Interface)
commands from the MCU to configure GAP/GATT at runtime. The MCU never
sees raw radio packets.

### 1.1 SPI3 pinout for BlueNRG-MS

Source: `BLE/hw/hw_spi.c` and `Core/Inc/main.h`.

| Signal             | MCU pin | Alt function | Notes                           |
| ------------------ | ------- | ------------ | ------------------------------- |
| SCK                | PC10    | AF6 (SPI3)   | 8 MHz (PCLK/2, prescaler = 2)   |
| MISO               | PC11    | AF6 (SPI3)   |                                 |
| MOSI               | PC12    | AF6 (SPI3)   |                                 |
| CSN (chip select)  | PD13    | GPIO out     | Software NSS (`SPI_NSS_SOFT`)   |
| RESET (active low) | PA8     | GPIO out     | Asserted for ≥ 28 ticks at boot |
| IRQ / DRDY         | PE6     | EXTI rising  | Module-to-host data-ready       |

Critical detail: `MX_SPI3_Init` is **deliberately not generated** by
CubeMX for this project. SPI3 ownership is transferred to the BLE
middleware — `BLE/hw/hw_spi.c` configures the peripheral with the exact
clock polarity/phase/baud rate the BlueNRG-MS module expects. A comment
in `main.c:127` reminds future editors not to reintroduce `MX_SPI3_Init`.

---

## 2. Software stack

The BLE middleware is organized in layers. Each arrow shows a "depends
on" relationship.

```
  ┌────────────────────────────────────────────────────────────────┐
  │  Core/Src/ble_app.c    (application — hand-written)            │
  │    • BLE_App_Init / Process / GATT event handler               │
  │    • Custom service 0xFE40 / chars 0xFE41, 0xFE42              │
  │    • Applies pulses to TIM3                                    │
  └───────────────────────────────┬────────────────────────────────┘
                                  │
  ┌───────────────────────────────▼────────────────────────────────┐
  │  BLE/ble_services/svc_ctl.c   (service controller / dispatcher)│
  │    • SVCCTL_Init() sets GAP device name = "OPENOTTER-MCP"      │
  │    • SVCCTL_RegisterSvcHandler — app attaches its callback     │
  │    • Calls SVCCTL_App_Notification on conn/disconnect          │
  └───────────────────────────────┬────────────────────────────────┘
                                  │
  ┌───────────────────────────────▼────────────────────────────────┐
  │  BLE/ble_core/*.c   (ACI command builders: GAP, GATT, HAL, L2) │
  │    • aci_gap_set_discoverable, aci_gatt_add_serv, …            │
  │    • Each function packs an HCI command and blocks on response │
  └───────────────────────────────┬────────────────────────────────┘
                                  │
  ┌───────────────────────────────▼────────────────────────────────┐
  │  BLE/tl/tl_ble_*.c   (HCI transport over SPI, reassembly)      │
  │    • TL_BLE_HCI_Init — resets module, waits for READY event    │
  │    • TL_BLE_R_EvtProc, TL_BLE_HCI_UserEvtProc                  │
  └───────────────────────────────┬────────────────────────────────┘
                                  │
  ┌───────────────────────────────▼────────────────────────────────┐
  │  BLE/hw/hw_spi.c, hw_timerserver.c, hw_lpm.c                   │
  │    • Low-level SPI transfer, RTC-wakeup-based timer server     │
  └────────────────────────────────────────────────────────────────┘
                                  │
  ┌───────────────────────────────▼────────────────────────────────┐
  │  BLE/utilities/scheduler.c + queue.c + memory_manager.c        │
  │    • Cooperative "set task" scheduler used by every layer      │
  └────────────────────────────────────────────────────────────────┘
```

Everything under `BLE/` except `ble_app.c` and the two config headers
(`ble_config.h`, `config.h`) is **vendor code imported from
STM32CubeL4**. See section 6 for the provenance table.

---

## 3. Configuration knobs

All tunables live in **`Core/Inc/ble_config.h`** — the middleware always
includes `"config.h"`, which is a one-line wrapper (`Core/Inc/config.h`)
that redirects to `ble_config.h`. This indirection lets the middleware
stay unmodified while we manage our own configuration.

Key settings:

| Macro                                    | Value          | Effect                                 |
| ---------------------------------------- | -------------- | -------------------------------------- |
| `BLE_CFG_PERIPHERAL` / `_CENTRAL`        | `1`/`0`        | Operate as peripheral only             |
| `BLE_CFG_MAX_CONNECTION`                 | `1`            | Single central at a time               |
| `CFG_ADV_BD_ADDRESS`                     | 0xAABBCCDDEE01 | Factory-programmed BD_ADDR override    |
| `CFG_FAST_CONN_ADV_INTERVAL_MIN/MAX`     | 80/100 ms      | Advertising interval range             |
| `CFG_IO_CAPABILITY`                      | `0x03`         | `NoInputNoOutput` — no pairing prompts |
| `CFG_MITM_PROTECTION`                    | `0`            | Open GATT access (no passkey)          |
| `CFG_TLBLE_EVT_QUEUE_LENGTH`             | `5`            | HCI event reassembly queue depth       |
| `CFG_DEBUG_TRACE`                        | `0`            | Disable `PRINT_MESG_DBG` output        |
| `BLE_SAFETY_TIMEOUT_MS` (in `ble_app.h`) | `1500`         | Safety watchdog window in ms           |

The `ble_config.h` file also sets up the RTC-based timer server (used by
the stack for its own internal timeouts) and the LPM (low-power manager).
LPM is present but disabled at runtime — `BLE_InitLPM` explicitly
requests `LPM_OffMode_Dis` so the MCU never enters stop/standby. Keeping
the MCU awake is a deliberate choice: BLE latency matters more than
battery life for a tethered-use robotics project.

---

## 4. GATT service

### 4.1 Service definition

Defined in `ble_app.h:24` and registered in `BLE_InitGATTService`
(`ble_app.c:152`).

```
Primary service  0xFE40     OpenOtter Control Service
├── Characteristic  0xFE41  "Command"
│      properties: WRITE | WRITE_WITHOUT_RESP
│      payload:    4 bytes  [int16_t steering_us, int16_t throttle_us]
│                  little-endian, clamped to [1000, 2000] µs
└── Characteristic  0xFE42  "Status"
       properties: NOTIFY | READ
       payload:    4 bytes (reserved — used for future heartbeat /
                            telemetry; currently never written by firmware)
```

The GAP device name is separately set by `SVCCTL_Init` to
**`OPENOTTER-MCP`** (`BLE/ble_services/svc_ctl.c:149`), 13 characters
long. The same name is also placed in the advertising packet so the iOS
app can match either the cached GAP name or the live advertisement.



### 4.2 Command payload

```c
typedef struct __attribute__((packed)) {
    int16_t steering_us;   // 1000 .. 2000 — maps to TIM3_CH4 on PB1
    int16_t throttle_us;   // 1000 .. 2000 — maps to TIM3_CH1 on PB4
} BLE_CommandPayload_t;   // 4 bytes, little-endian
```

On every write, `BLE_EventHandler` (`ble_app.c:247`):

1. Matches the written attribute against `cmdCharHandle + 1` (the value
   handle, as opposed to the declaration handle).
2. `memcpy`s the payload into `BLE_CommandPayload_t`.
3. Clamps each pulse to `[PWM_MIN_US, PWM_MAX_US]`.
4. Writes `CCR1` / `CCR4` directly via `__HAL_TIM_SET_COMPARE`.
5. Updates `lastCommandTick` and clears `safetyTriggered`.

No command queueing, no interpolation. The iOS app is responsible for
sending at whatever rate it considers smooth (20–50 Hz typically).

---

## 5. Connection flowchart

```
  ┌──────────────────────────────────────────────────────────────────────┐
  │  boot                                                                │
  │    BLE_App_Init                                                      │
  │      ├─ BLE_InitLPM (standby disabled)                               │
  │      ├─ BLE_InitRTC (LSI 32 kHz for the timer server)                │
  │      ├─ HW_TS_Init                                                   │
  │      ├─ SCH_RegTask x3 (HciAsynchEvt, TlEvt, StartAdv)               │
  │      ├─ BLE_InitStack → TL_BLE_HCI_Init → SVCCTL_Init                │
  │      │   │ hardware reset of BlueNRG-MS (~1 ms pulse)                │
  │      │   │ wait for HCI "hardware error" / "READY" event             │
  │      │   │ SVCCTL_Init sets GAP name = "OPENOTTER-MCP"               │
  │      ├─ BLE_InitGATTService (adds 0xFE40 / 0xFE41 / 0xFE42)          │
  │      ├─ BLE_ApplyPWM(neutral, neutral)                               │
  │      └─ BLE_StartAdvertising (ADV_IND, 80–100 ms interval)           │
  └──────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
  ┌──────────────────────────────────────────────────────────────────────┐
  │  idle: SCH_Run + LD1 toggle + safety watchdog                        │
  │    (iOS central scans → sees "OPENOTTER-MCP")                        │
  └──────────────────────────────────────────────────────────────────────┘
                                 │
                     iOS taps Connect
                                 ▼
  ┌──────────────────────────────────────────────────────────────────────┐
  │  controller event EVT_LE_CONN_COMPLETE                               │
  │    → SVCCTL_App_Notification (ble_app.c:298)                         │
  │        bleCtx.isConnected = 1                                        │
  │        bleCtx.connectionHandle = conn->handle                        │
  │        bleCtx.lastCommandTick = now                                  │
  │        bleCtx.safetyTriggered = 0                                    │
  └──────────────────────────────────────────────────────────────────────┘
                                 │
                iOS writes 4 bytes to 0xFE41 at ~50 Hz
                                 ▼
  ┌──────────────────────────────────────────────────────────────────────┐
  │  EVT_VENDOR / EVT_BLUE_GATT_ATTRIBUTE_MODIFIED                       │
  │    → BLE_EventHandler                                                │
  │        clamp pulses                                                  │
  │        __HAL_TIM_SET_COMPARE (CH1 = throttle, CH4 = steering)        │
  │        update lastCommandTick                                        │
  └──────────────────────────────────────────────────────────────────────┘
                                 │
                  no write for > 1500 ms?
                                 ▼
  ┌──────────────────────────────────────────────────────────────────────┐
  │  BLE_App_Process sees elapsed > BLE_SAFETY_TIMEOUT_MS                │
  │    → BLE_ApplyPWM(neutral, neutral)                                  │
  │    → safetyTriggered = 1                                             │
  └──────────────────────────────────────────────────────────────────────┘
                                 │
                   iOS disconnects (or link loss)
                                 ▼
  ┌──────────────────────────────────────────────────────────────────────┐
  │  EVT_DISCONN_COMPLETE                                                │
  │    → SVCCTL_App_Notification                                         │
  │        isConnected = 0                                               │
  │        BLE_ApplyPWM(neutral, neutral)                                │
  │        SCH_SetTask(CFG_IdleTask_StartAdv)                            │
  │          (deferred: cannot call aci_* from inside HCI callback)      │
  └──────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
                       back to "idle" state above
```

### 5.1 Why advertising re-start is deferred

Calling `aci_gap_set_discoverable` from inside the HCI event callback
deadlocks the transport layer — the command channel is still owned by
the current event. The fix is to schedule `BLE_AdvTask` via
`SCH_SetTask(CFG_IdleTask_StartAdv)`; the next `SCH_Run()` iteration
picks it up when the channel is idle. Without this, the device becomes
undiscoverable after the first disconnect.

### 5.2 Why the backup-domain reset at boot

`main.c:105` force-resets the RTC backup domain on pin reset. The BLE
timer server uses the RTC wakeup timer, and stale state from a previous
run can make `HW_TS_Init` spin forever. This is copied behavior from
the `P2P_LedButton` reference.

---

## 6. Code provenance — where things came from

Every non-trivial BLE source file in this project has an upstream origin.
The table below maps the files we ship to their counterparts in
[STM32CubeL4](https://github.com/STMicroelectronics/STM32CubeL4), so
future engineers can diff against upstream when the middleware behaves
unexpectedly.

| Local path                     | Upstream origin (STM32CubeL4)                                                | Notes                                                       |
| ------------------------------ | ---------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `BLE/ble_core/*.{c,h}`         | `Middlewares/ST/BlueNRG-MS/hci/…` and `bluenrg1_*` headers                   | ACI command builders                                        |
| `BLE/tl/tl_ble_*.{c,h}`        | `Projects/B-L475E-IOT01A/Applications/BLE/P2P_LedButton/BLE_Application/TL/` | HCI transport over SPI                                      |
| `BLE/hw/hw_spi.c`              | same project, `BLE_Application/HW/hw_spi.c`                                  | SPI driver, unmodified                                      |
| `BLE/hw/hw_timerserver.c`      | same project, `BLE_Application/HW/hw_timerserver.c`                          | RTC-wakeup timer server                                     |
| `BLE/hw/hw_lpm.c`              | same project, `BLE_Application/HW/hw_lpm.c`                                  |                                                             |
| `BLE/ble_services/svc_ctl.*`   | same project, `BLE_Application/Core/svc_ctl.*`                               | Local edit: GAP name set to `OPENOTTER-MCP`                 |
| `BLE/ble_services/lbs_stm.*`   | same project, `LedButtonService/lbs_stm.*`                                   | Kept for reference; unused at runtime                       |
| `BLE/ble_services/{dis,hrs}.*` | `Middlewares/ST/BlueNRG-MS/Profile_Framework/Src/`                           | Device-info / heart-rate; not compiled into our service set |
| `BLE/utilities/*.{c,h}`        | `Middlewares/ST/BlueNRG-MS/utilities/`                                       | Scheduler, queue, list, memory manager, LPM                 |
| `BLE/debug/debug.h`            | same project, `BLE_Application/Debug/debug.h`                                | Trace macros (disabled)                                     |
| `BLE/_reference/*`             | verbatim copies of `main.c`, `lb_client_app.c`, etc. from `P2P_LedButton`    | Not compiled; historical reference only                     |
| `Core/Inc/ble_config.h`        | derived from `P2P_LedButton/Core/Inc/app_conf.h` + `config.h`                | Trimmed to peripheral-only, hand-tuned                      |
| `Core/Inc/config.h`            | new; one-line wrapper so middleware `#include "config.h"` still resolves     | Hand-written                                                |
| `Core/Src/ble_app.c`           | **hand-written** (inspired by `lb_server_app.c`)                             | OpenOtter-specific                                          |

**Which files are compiled?** Exactly the sources listed in
`cmake/stm32cubemx/CMakeLists.txt` under `BLE_Middleware_Src`.  Anything
in `BLE/_reference/` or `BLE/*_template.h` is **not** compiled — deleting
those is safe, but they are kept around as provenance / inspiration.

### 6.1 Licensing

All ST-authored files carry the SLA0094/SLA0055 license headers
(permissive, allows redistribution in binary form). New hand-written
files in `Core/` are the project's own work under the top-level project
license. Do not strip copyright headers when touching ST files.

---

## 7. How we got BLE working — chronological summary

For context on why the current structure exists, here is the short
history (also visible in git log / CHANGELOG):

1. **Start from the STM32CubeL4 P2P_LedButton example** — chosen because
   it targets the same B-L475E-IOT01A board and the same SPBTLE-RF
   module, so SPI pin mux and BlueNRG reset timing are known-good.
2. **Port to CMake/Ninja/STM32CubeCLT** — the original example ships
   IAR/Keil/Makefile projects; we replaced them with the CubeCLT-friendly
   CMake preset setup.
3. **Reorganize into `BLE/{ble_core, ble_services, tl, hw, utilities}`**
   — flattening the deep `Middlewares/...` path cut include lists in
   half and made the search tree clear.
4. **Replace `config.h`** with a project-owned `ble_config.h` plus a
   one-line wrapper — lets us tune the middleware without editing any
   upstream files.
5. **Hand-write `ble_app.c`** modelled on `lb_server_app.c`, replacing
   the LED/button service with a control service (`0xFE40`) whose sole
   purpose is to receive PWM pulse widths.
6. **Add the deferred re-advertise path** via the scheduler so the
   peripheral recovers after a disconnect.
7. **Rename** the GAP device (and, in progress, the advertising name) to
   `OPENOTTER-MCP`.

If you are adding a second service (e.g. IMU telemetry), follow the same
pattern as `ble_app.c`:
1. Allocate UUIDs.
2. Call `aci_gatt_add_serv` + `aci_gatt_add_char` inside your init.
3. Register an event handler via `SVCCTL_RegisterSvcHandler` — note that
   `BLE_CFG_SVC_MAX_NBR_CB` in `ble_config.h` must be ≥ the number of
   handlers you register (currently 2, bump it if needed).

Continuing guidance on feature extension is in
`05-extending-the-firmware.md`.
