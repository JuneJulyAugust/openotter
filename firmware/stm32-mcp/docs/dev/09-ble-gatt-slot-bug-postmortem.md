# Postmortem: FE44 Mode Characteristic Lost — Depth Map Silent Failure

**Date:** 2026-04-25
**Commit:** d902f07 (`fix: correct FE40 GATT slot count so FE44 mode char is discoverable`)

---

## Symptom

After adding the VL53L5CX reverse safety supervisor, the iOS depth map view showed
`chunks rx 0` — zero BLE frame chunks received — while the ToF status indicator
continued to show `state: running`. LED2 on the board blinked normally, confirming
the sensor was producing frames in firmware.

---

## Root Cause

`aci_gatt_add_serv` for the FE40 control service was given
`Max_Attribute_Records = 10`. The BlueNRG-MS GATT stack allocates one attribute
record per declaration, value, and CCCD (Client Characteristic Configuration
Descriptor). The FE40 service contains:

```
 Slot   Characteristic
 ─────────────────────────────────────────────────────────────
  1     service declaration
  2     FE41 cmd   — declaration
  3     FE41 cmd   — value  (write / write-without-response)
  4     FE42 status — declaration
  5     FE42 status — value  (notify + read)
  6     FE42 status — CCCD   ← notify chars require a CCCD slot
  7     FE43 safety — declaration
  8     FE43 safety — value  (notify + read)
  9     FE43 safety — CCCD   ← second CCCD slot
 10     FE44 mode  — declaration
 11     FE44 mode  — value  (write / write-without-response / read)
```

Total required: **11**. Allocated: **10**.

When the firmware called `aci_gatt_add_char` for FE44, the stack returned
`BLE_STATUS_INSUFFICIENT_RESOURCES (0x64)`. The error was suppressed by
`(void)ret`, so `bleCtx.modeCharHandle` remained `0` (zeroed by `memset`).

Consequence chain:

```
FE44 aci_gatt_add_char fails (0x64)
  → modeCharHandle = 0
  → iOS GATT discovery finds no FE44 characteristic
  → STM32BleManager.modeChar = nil
  → writeMode() guard returns early
  → firmware never receives operating mode byte 0x01 (DEBUG)
  → firmware remains in DRIVE mode
  → BLE_Tof_FrameStreamAllowed(DRIVE) returns false
  → BLE_Tof_Process() early-returns before snapshotting L5 frames
  → no FE62 notifications sent
  → iOS chunksReceived stays 0, depth map blank
```

---

## Why the Status Notifications Were Misleading

FE63 status notifications are published in the **same early-return branch** as the
rate-window log — the early-return in `BLE_Tof_Process()` skips only the frame
snapshot/chunk path, not the 1 Hz status publish. So iOS still received `state:
running` with a non-zero scan rate, making the sensor appear healthy.

---

## Evidence Trail (Debugging Session)

1. **LED2 toggling** — L5 frames arriving physically. Ruled out sensor and I²C.
2. **`chunks rx 0` on iOS** with `state: running` — frames produced but not sent
   over BLE.
3. **No `[TOF] write ack FE44`** in Xcode console — FE44 was never discovered,
   so `writeMode()` never fired. This was the key signal.
4. **No `L5 dbg:` UART line** — the diagnostic log lives after the early-return
   gate, so its absence confirmed firmware was in DRIVE mode.
5. **FE63 CCCD update logged as `isNotifying=true`** — proved BLE path and iOS
   subscription were working; the problem was mode-gating, not connectivity.

---

## Fix

Changed `Max_Attribute_Records` from `10` to `11` in `BLE_InitGATTService`:

```c
/*
 * Max_Attribute_Records exact accounting (BlueNRG-MS):
 *   1  service declaration
 * + 2  FE41 cmd     (decl + value, write/wwr — no CCCD)
 * + 3  FE42 status  (decl + value + CCCD, notify+read)
 * + 3  FE43 safety  (decl + value + CCCD, notify+read)
 * + 2  FE44 mode    (decl + value, write/wwr/read — no CCCD)
 * = 11 records.
 */
ret = aci_gatt_add_serv(UUID_TYPE_16, (const uint8_t *)&uuid,
                        PRIMARY_SERVICE, 11, &bleCtx.svcHandle);
```

All four `aci_gatt_add_char` calls now log explicit UART failure messages instead
of silently discarding the return value.

**Rule for BlueNRG-MS:**
- Notify or Indicate characteristic → declaration + value + CCCD = **3 slots**
- Write-only or Read-only characteristic → declaration + value = **2 slots**
- Add 1 for the service declaration itself.

---

## Diagnostic Instrumentation Added

To make future silent failures visible, the following were added and kept:

**Firmware (`ble_app.c`):**
- Explicit UART log on `aci_gatt_add_char` failure for FE41–FE44.

**Firmware (`ble_tof.c`):**
- Restored `log_fmt()` variadic helper.
- 1 Hz `L5 dbg:` UART line reporting `seen / snap / push / fail / mode / sensor /
  dbgseq / pubseq / hz`. Fires only when `pending_chunk == 0` to avoid starving
  the chunk drain.
- `chunks_failed` and `snapshots_taken` counters in `BLE_TofContext_t`.

**iOS (`STM32BleManager.swift`):**
- `didUpdateNotificationStateFor` — logs UUID, `isNotifying`, error per
  characteristic.
- `didWriteValueFor` — logs write acks for FE61 (config) and FE44 (mode).

**iOS (`STM32TofService.swift`):**
- `applyDebugStreamingState()` logs characteristic property bitmasks and which
  `setNotifyValue` calls are attempted.
- `handleFrameNotification()` logs the first 3 chunks received and every 64th
  thereafter.

---

## Secondary Bug (Not Yet Fixed)

`TofL5_Init` calls `TofL5_Configure(&g_cfg)` internally, which sets
`g_last_configure_tick` to the current tick. When `BLE_Tof_EnforceSafetyConfig`
subsequently tries to reconfigure the sensor at 30 Hz (for the safety supervisor),
it is inside the 500 ms debounce window and silently dropped. The safety supervisor
therefore runs at the 10 Hz rate set during init, not at the intended 30 Hz.

**Fix:** Clear `g_last_configure_tick = 0` after the internal configure call in
`TofL5_Init`, so the next external `TofL5_Configure` call is never blocked by the
init's own debounce timestamp.
