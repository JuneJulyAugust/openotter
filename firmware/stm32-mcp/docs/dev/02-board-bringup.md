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
│      LED  LD1  (green, PA5)     ← heartbeat, blinks ~1 Hz          │
│      LED  LD2  (green, PB14)    ← user LED, unused by firmware     │
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
Manual PDF in `docs/um2153-discovery-kit-for-iot-node-...pdf`.

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

### 3.1 Heartbeat LED (LD1, PA5)

The firmware toggles PA5 every 500 ms in the main loop (`main.c:160`).
After `./build.sh flash` finishes with `[OK] Flash and verify complete.`:

- LD1 should start blinking at ~1 Hz within 2 seconds.
- If LD1 is **off** → MCU did not reach the main loop. Likely a HardFault;
  attach with `arm-none-eabi-gdb` to inspect.
- If LD1 is **solid on or solid off** and flash succeeded →
  `Error_Handler()` was hit during one of the `MX_*_Init` calls. Run
  under gdb and break at `Error_Handler`.
- If LD1 blinks but BLE never advertises, see 3.3.

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

The firmware advertises as **`OPENOTTER-MCP`** (GAP device name) after
`BLE_App_Init` completes. Any BLE scanner can confirm this:

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

If the heartbeat LED blinks but no advertisement is seen:
- Verify the SPBTLE-RF module is not physically damaged (visual check).
- Check `ble_config.h` — `CFG_ADV_BD_ADDRESS` must be non-zero.
- Connect gdb and break inside `BLE_InitStack` to verify
  `TL_BLE_HCI_Init` returned without asserting.

---

## 4. End-to-end sanity check

Once all the above pass, a final end-to-end test without any external
hardware:

1. Flash Debug firmware: `./build.sh all`.
2. Confirm LD1 blinks (section 3.1).
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
| LD1 off after flash                                | `Error_Handler()` hit — attach gdb, break on `Error_Handler`.     |
| LD1 blinks but no BLE advert                       | SPI3 / SPBTLE-RF wiring fault, or BlueNRG reset hold time too low.|
| Advert seen as "BlueNRG"                           | Old firmware on flash — reflash latest Debug build.               |
| iOS app connects once, then refuses to reconnect   | GAP name mismatch with iOS cache — see BLE doc for cache notes.   |
