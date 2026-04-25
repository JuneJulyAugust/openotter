# VL53L5CX Reverse Safety Design

## Goal

Use the VL53L5CX as the firmware reverse-safety sensor in Drive mode while keeping the existing VL53L1CB code available for debug and fallback work.

## Safety Region

The safety distance comes from the 4x4 VL53L5CX grid:

- Row 3, column 2: zero-based index `9`
- Row 3, column 3: zero-based index `10`

Zone order is top-to-bottom, left-to-right. The firmware takes the minimum valid distance from those two zones. This matches the observed mounting: row 4 sees ground, rows 1-2 are too high, and row 3 center zones cover the likely reverse path.

## Ranging Mode

Drive mode configures VL53L5CX as:

- Layout: `4x4`
- Frequency: `30 Hz`
- Integration: `20 ms`
- Profile: continuous autonomous ranging

`30 Hz` gives roughly 33 ms depth updates, which is fast compared with the iOS command keepalive and fast enough for time-to-brake without pushing VL53L5CX to its noisier maximum frequency. Debug mode may still request other supported layouts and rates through FE61.

## Firmware Behavior

On entry to Drive mode, firmware enforces the L5 safety config and clears any prior safety latch. The reverse safety supervisor consumes the selected L5 distance and the velocity sent in FE41.

If no L5 frame arrives, the existing `FRAME_GAP` path brakes while reversing after the configured gap. If selected zones are invalid, the existing `TOF_BLIND` path brakes after the configured invalid-frame count. If the L5 driver reports dead, the existing `DRIVER_DEAD` path brakes.

The previous VL53L1CB code remains compiled and usable from Debug config writes. Its clear/no-target synthetic distance is raised from `3.0 m` to `4.0 m` to match the current practical range expectation.

## BLE Behavior

Full ToF depth frames on FE62 are Debug-only. Self Driving view should keep the firmware in Drive mode and receive only FE43 safety events, not full depth maps. STM32 Control view still sets Debug and can show 4x4 or 8x8 depth maps.

## LED Diagnostic

LED2 (PB14) is a local L5 activity indicator. If the VL53L5CX is producing fresh frames, LED2 toggles at 1 Hz. If no fresh L5 frame has arrived for more than 1500 ms, firmware forces LED2 off.

## Zone Validity (VL53L5CX target_status)

VL53L5CX uses a different `target_status` code space from VL53L1 (per ST UM2884
§5.5.6). The ST driver header states "5 & 9 means ranging OK". The full valid set:

| Code | Meaning                              | Treatment |
|------|--------------------------------------|-----------|
|  5   | Range valid                          | Valid      |
|  6   | Wrap-around not performed (long range)| Valid     |
|  9   | Range valid with large pulse         | Valid      |
| 10   | Range valid, no target at prev range | Valid      |
| all others | Not updated, sigma high, consistency failed, etc. | Invalid |

**Do not use VL53L1 RangeStatus codes here.** On VL53L1, status 0 = RANGE_VALID
and status 11 = RANGE_VALID_MERGED_PULSE. On VL53L5CX, status 0 = "data not
updated" (invalid) and status 11 = "measurement consistency failed" (invalid).
Copying the L1 whitelist `{0, 3, 6, 11}` to the L5 path rejects every normal
status=5 frame as invalid, triggering `REV_SAFETY_CAUSE_TOF_BLIND` after four
clean frames with no obstacle present. See postmortem
`firmware/stm32-mcp/docs/dev/09-ble-gatt-slot-bug-postmortem.md` — the status
code bug was found and fixed alongside the FE44 GATT slot bug.

## Tests

Host tests cover:

- 4x4 selected-zone index mapping (`9`, `10`)
- minimum valid selected-zone distance
- invalid selected zones
- non-4x4 frames rejected for reverse safety
- L1 no-target clear distance equals 4.0 m
- VL53L1-only valid codes `{0, 11}` rejected on L5 (regression)
- VL53L5CX marginal-valid codes `{6, 10}` accepted on L5 (regression)

iOS tests cover:

- Self-driving mode does not request ToF debug config
- STM32 Control Debug mode still refreshes ToF config
