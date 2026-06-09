# 02 — Board Bringup and Connection Verification

This document describes how to confirm the **B-L475E-IOT01A** Discovery Kit
is connected correctly to the host, how to read the board's on-board LEDs
for live status, and how to verify the running firmware end-to-end without
the rest of the OpenOtter hardware (servo, ESC, iOS app) being present.

Use this checklist in order. Each step isolates a different failure domain:
USB cable → ST-Link probe → MCU JTAG/SWD → firmware → BLE radio.

---

## 1. The board at a glance

The B-L475E-IOT01A is a single PCB with two USB-C micro-B connectors:

```
┌────────────────────────────────────────────────────────────────────┐
│                                                                    │
│   [CN7  ST-LINK USB]  ◀── host Mac (power + SWD + ST-LINK VCP)     │
│                                                                    │
│      LED  LD1  (green, PA5)     ← SPI1 SCK in VL53L8 SPI mode      │
│      LED  LD2  (green, PB14)    ← main-loop heartbeat              │
│      LED  LD3  (orange, PC9)    ← WiFi/BLE combo status (unused)   │
│      LED  LD4  (blue)           ← power indicator on ST-LINK       │
│      LED  LD6  (red)            ← ST-LINK communication activity   │
│                                                                    │
│   [JP4 Power Selection Jumper]  ← MUST be on 5V_ST_LINK for dev    │
│                                                                    │
│   B1 (USER) button on PC13                                         │
│                                                                    │
│   [CN8  USB-OTG]      (not used by this firmware)                  │
│                                                                    │
│   SPBTLE-RF BLE module (Murata, U9) on SPI3 — advertises as        │
│   "OPENOTTER-MCP" once firmware is running.                        │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

For the full silkscreen map and reference designator list see the User
Manual PDF in `docs/hardware/mcu/um2153-discovery-kit-for-iot-node-...pdf`.

> [!CAUTION]
> **Check your Power Selection Jumper (JP4)**
> Ensure the **JP4** jumper is in the **`5V_ST_LINK`** position for standard debugging off a USB cable. 
> The *5V_ARD* position is meant to draw power from the Arduino headers (e.g. from an RC car battery or shield), and the board will not power on from USB if left in the wrong position.

---

## 2. Host-side: is the probe visible?

### 2.1 Plug in the CN7 USB-C port (the one labelled "ST-LINK")

The LD4 (blue) power LED on the ST-Link side of the board should turn
solid. If it does not light, verify JP4 is on `5V_ST_LINK`. If still off,
the cable is either charge-only or the port
is dead — try a different known-good data cable first.

### 2.2 macOS USB enumeration

The board exposes **three** USB interfaces when enumerated correctly:

| Interface         | Visible as                                  |
|-------------------|---------------------------------------------|
| ST-LINK debug     | USB HID (seen by `STM32_Programmer_CLI`)    |
| ST-LINK VCP       | `/dev/tty.usbmodem*` serial port            |
| ST-LINK Mass Stor.| A `DIS_L4IOT` drive in Finder (drag-n-drop) |

Quick checks:

```bash
# Serial port for the virtual COM port (may appear as usbmodem1103 or similar)
ls /dev/tty.usbmodem*

# Mass-storage drive
ls /Volumes | grep -i DIS_L4IOT
```

If **none** of the three show up:
- LD4 is off → cable/power issue (see 2.1).
- LD4 is on → probe firmware may be corrupted; upgrade it (see 2.4).

### 2.3 Probe query via the STM32 Programmer

This is the authoritative test — it talks to the ST-Link and asks the MCU
to identify itself:

```bash
/opt/ST/STM32CubeCLT_1.21.0/STM32CubeProgrammer/bin/STM32_Programmer_CLI \
    --list
```

Expected output:

```
ST-LINK SN  : 003400xxxxxxxxxxxxxxxxxx
ST-LINK FW  : V2Jxx or V3Jxx
Board       : B-L475E-IOT01A1
Voltage     : 3.26V
SWD freq    : 4000 KHz
Connection mode : Normal
Reset mode      : Software reset
Device ID       : 0x415
Revision ID     : Rev 3
Device name     : STM32L475xx
Flash size      : 1 MBytes
Device type     : MCU
Device CPU      : Cortex-M4
```

Cross-check three things:
- **`Board : B-L475E-IOT01A1`** — confirms it is the right Discovery Kit.
- **`Device name : STM32L475xx`** — confirms the MCU matches our target.
- **`Voltage : ~3.3V`** — confirms the MCU is powered, not in reset.

A bare `STM32_Programmer_CLI --connect port=SWD` will produce the same
info and additionally attach to the target; either is fine.

### 2.4 Probe firmware upgrade (only if `--list` fails)

```bash
/opt/ST/STM32CubeCLT_1.21.0/STM32CubeProgrammer/bin/STM32_Programmer_CLI \
    -upgrade
```

This runs the bundled `STLinkUpgrade` routine. Re-run `--list` afterwards.

---

## 3. MCU-side: is the firmware alive?

Once `--list` confirms the probe sees the target, build & flash the
firmware (see `01-toolchain-and-build.md`) and verify the MCU is running:

### 3.1 UART Main-Loop Heartbeat

Current firmware reserves PA5 / Arduino D13 for SPI1 SCK so SATEL-VL53L8 can
run in SPI mode. Do not use LD1 as a firmware heartbeat in this branch.

After `./build.sh flash` finishes with `[OK] Flash and verify complete.`, open
the ST-LINK VCP serial log at 115200 baud and look for the boot phases and the
1 Hz `LOOP` line:

```text
=== OpenOtter STM32 boot ===
BOOT reset_csr=0x... cause=...
BOOT phase=peripherals_done tick=...
BOOT phase=watchdog_ready tick=...
BOOT phase=ble_app_init
BOOT phase=ble_tof_init
BOOT phase=services_ready tick=...
BOOT phase=main_loop_enter tick=...
LOOP iter=... tick=...
```

- If `LOOP` appears once per second, the MCU reached the main loop.
- LD2 / PB14 is a **main-loop heartbeat**. It toggles every 500 ms, so the
  visible blink cycle is about 1 Hz while the loop is alive.
- If no boot or `LOOP` lines appear, the MCU may not have reached the main loop.
  Likely causes include a power/brownout issue, HardFault, or early init error.
- If the serial log stops after a `BOOT phase=...` line, use the last printed
  phase as the boundary. For example, a stop after `ble_app_init` points at
  BlueNRG/SPI3/GATT startup.
- If the log prints `PANIC:I`, a fatal init path reset the MCU. If it prints
  `PANIC:P`, the BlueNRG SPI transport stayed busy too long and the firmware
  reset instead of deadlocking.
- If `LOOP` continues but BLE never advertises, see 3.3.

ToF frame health is reported through the STM32 diagnostic UI, FE63 status, and
the UART ToF logs when debug output is enabled. LD2 intentionally answers the
lower-level question first: whether the firmware loop is still executing.

### 3.2 UART trace over ST-LINK VCP

USART1 is wired to the ST-Link VCP at 115200-8-N-1 (PB6 TX / PB7 RX).
The BLE middleware's `PRINT_MESG_DBG` macro can emit to this UART if
`CFG_DEBUG_TRACE` is set to `1` in `ble_config.h`. By default debug trace
is **disabled**, so the VCP is normally silent during a healthy run —
silence is expected, not a bug.

To capture any output that is emitted:

```bash
# macOS — replace usbmodem1103 with the device from `ls /dev/tty.usbmodem*`
screen /dev/tty.usbmodem1103 115200
# exit with: Ctrl-A, then K, then Y
```

Alternatives: `minicom -D /dev/tty.usbmodem1103 -b 115200`, or `picocom`.

### 3.3 BLE advertising check (no iOS app required)

The firmware advertises as **`OPENOTTER-MCP`** (GAP device name) from the
main-loop advertising retry path after BLE/GATT initialization completes. Any
BLE scanner can confirm this:

**macOS** (built-in):

```bash
system_profiler SPBluetoothDataType | grep -i openotter || true
# or use the LightBlue / nRF Connect apps
```

**iOS** — install **nRF Connect** from the App Store, tap *Scan*, look for
a device advertising the name `OPENOTTER-MCP` with service UUID `0xFE40`.

**Linux** (for reference):

```bash
sudo hcitool -i hci0 lescan --duplicates
# should list <MAC>  OPENOTTER-MCP
```

A successful scan proves:
- The BlueNRG-MS module on SPI3 came out of reset.
- The HCI transport layer synchronized.
- `aci_gap_set_discoverable` succeeded.

If the UART `LOOP` heartbeat continues but no advertisement is seen:
- Verify the SPBTLE-RF module is not physically damaged (visual check).
- Check `ble_config.h` — `CFG_ADV_BD_ADDRESS` must be non-zero.
- Connect gdb and break inside `BLE_InitStack` to verify
  `TL_BLE_HCI_Init` returned without asserting.

### 3.4 VIN / RC battery startup triage

When the board is powered from the RC car battery rail, noisy startup or a
short brownout can leave external devices in a different state than the STM32
core. The firmware now hardens this path by:

- starting the independent watchdog before BlueNRG BLE bringup;
- resetting the BlueNRG coprocessor with a bounded GPIO reset pulse that does
  not depend on the BLE timer server;
- limiting BlueNRG HCI command waits to 3 s, below the watchdog window;
- starting BLE advertising from the main-loop retry/backoff path instead of
  blocking boot inside `BLE_App_Init`;
- panic-resetting instead of spinning forever on init errors or BlueNRG SPI
  busy lockups;
- clearing reset-cause flags after each boot log so `BOR`, `IWDG`, `PIN`, and
  `SFT` reports describe the current reboot.

If the car battery path reproduces a freeze, capture the first boot line:

```text
BOOT reset_csr=0x... cause=BOR IWDG PIN ...
```

- `BOR` means the MCU saw a brownout. Improve the 5 V rail before debugging
  firmware; a buck regulator with enough surge margin and local bulk
  capacitance near the IoT board is strongly recommended.
- `IWDG` means the firmware watchdog recovered a stuck startup or loop path.
  The next boot should continue to `main_loop_enter`; repeated `IWDG` points to
  a persistent external-device or power issue.
- `PANIC:I` before reset points at fatal peripheral/BLE service init.
- `PANIC:P` before reset points at BlueNRG SPI bus busy lockup.

---

## 4. End-to-end sanity check

Once all the above pass, a final end-to-end test without any external
hardware:

1. Flash Debug firmware: `./build.sh all`.
2. Confirm the UART `LOOP` heartbeat appears once per second (section 3.1).
3. Use nRF Connect on iOS to scan, **connect** to `OPENOTTER-MCP`, and
   locate service `0xFE40` with characteristic `0xFE41` (write) and
   `0xFE42` (notify).
4. Write 4 bytes to `0xFE41` — the payload is little-endian
   `[int16_t steering_us, int16_t throttle_us]`. Neutral = `1500, 1500`,
   so the bytes are `DC 05 DC 05` (0x05DC = 1500). Any write should be
   accepted silently (no GATT error).
5. Wait 2 s without writing — the safety watchdog reverts internally to
   neutral; no observable side-effect without a servo attached. You can
   confirm by reattaching gdb and inspecting `bleCtx.safetyTriggered`.
6. Disconnect the BLE central — the peripheral should re-advertise
   immediately (deferred via the scheduler, see `ble_app.c:310`).

No servo, ESC, or battery is required for this bringup sequence. The MCU
self-powers from the CN7 USB cable and the BLE module runs from the same
3.3 V rail.

---

## 5. What can go wrong — quick reference

| Symptom                                           | Root cause hint                                                   |
|---------------------------------------------------|-------------------------------------------------------------------|
| `--list` → `No STLink device detected`            | Charge-only cable, bad USB port, or probe FW too old — see 2.4.   |
| `--list` OK, flash → `Error: Data mismatch`       | Flash wear or stale cache — try `--fullchip-erase` then reflash.  |
| No `LOOP` line after flash                         | Early init/fault/power issue before the main loop; check `BOOT phase` and panic tag. |
| LD2 not blinking                                   | Main loop is not alive, or the board has not reached `main_loop_enter`. |
| Repeated `BOOT cause=BOR` on RC battery VIN         | Brownout/noisy 5 V rail; improve regulation and capacitance before code debugging. |
| Repeated `BOOT cause=IWDG`                          | Watchdog is recovering a persistent startup/loop stall. Capture the last boot phase. |
| `PANIC:I`                                          | Fatal init/GATT setup failure; inspect prior boot phase and BLE logs. |
| `PANIC:P`                                          | BlueNRG SPI stayed busy; inspect SPI3/BlueNRG power/reset behavior. |
| `LOOP` continues but no BLE advert                 | Check for `BLE adv_start fail ...` logs; SPI3 / SPBTLE-RF fault, or BlueNRG startup/GATT service failure. |
| Advert seen as "BlueNRG"                           | Old firmware on flash — reflash latest Debug build.               |
| iOS app connects once, then refuses to reconnect   | GAP name mismatch with iOS cache — see BLE doc for cache notes.   |
