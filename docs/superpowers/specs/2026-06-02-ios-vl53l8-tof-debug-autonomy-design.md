# iOS VL53L8 ToF Debug And Autonomy Design

## Goal

Update the iOS app to match the SATEL-VL53L8 firmware migration, make the
STM32 debug ToF visualization work against VL53L8 frames first, then surface the
same sensor health and rear safety information in autonomous mode. The design
must leave one clear extension point for a future second VL53L8 sensor.

## Release-Candidate Status

As of 2026-06-08, the iOS app is prepared as `1.2.0` for final PR CI/release
hygiene before merge and tag. The STM32 Control diagnostics path was deployed
to the iPhone from the feature worktree and verified against the connected
IOT01A1 plus one rear SATEL-VL53L8. The debug view rendered live VL53L8 ToF
data without requiring an iOS protocol change.

One-rear-sensor app/firmware end-to-end validation passed after the final
forward/rear safety fixes. Full front/two-SATEL validation remains intentionally
pending until the second SATEL board is available.

Final validation and resolved-bug evidence is tracked in:

```text
docs/superpowers/specs/2026-06-08-vl53l8-v1.2-validation-and-bugs.md
```

## Current App Context

The app already has the right physical boundaries:

- `STM32BleManager` discovers FE60, wires FE61/FE62/FE63 to
  `STM32TofService`, and gates debug streaming through firmware mode FE44.
- `STM32TofService` reassembles V2 FE62 chunks and parses generic `TofFrame`
  payloads.
- `STM32ControlView` has a ToF debug card and `TofGridView`.
- `SelfDrivingViewModel` drives autonomy through `PlannerOrchestrator`, while
  firmware reverse safety arrives independently through FE43.

The iOS semantic model now describes VL53L8CX while preserving the historical
wire value `2`. Firmware and iOS both treat that value as
`TOF_SENSOR_VL53L8CX`; VL53L5 remains historical/deprecated.

## Wire Contract

Current single-sensor firmware:

| Channel | Mode | Payload |
| --- | --- | --- |
| FE61 config write | Debug only | `Tof_Config_t`: sensor `2`, layout `4` or `8`, profile `1`, frequency, integration, budget |
| FE62 frame notify | Debug only | V2 chunk stream from `tof_frame_codec`: 4x4 or 8x8 `Tof_Frame_t` |
| FE63 status notify/read | Debug and Drive | `BLE_TofStatusPayload_t`: state, last error, scan rate |
| FE43 safety notify/read | Drive | Firmware reverse safety event with BRAKE/SAFE state, cause, depth, velocity |

Autonomous mode must not depend on FE62 debug frames because firmware suppresses
frame streaming in Drive mode. It can use FE63 for rear ToF health and FE43 for
rear safety events.

## Phase 1: Debug ToF Visualization

The debug view must be the first working iOS outcome. It should:

- Rename `TofSensorType.vl53l5cx` to `TofSensorType.vl53l8cx`, preserving raw
  value `2`.
- Rename VL53L5-specific helper names to VL53L8-specific helper names.
- Keep V2 chunk reassembly unchanged; the frame format is already generic.
- Decode and display VL53L8 target statuses with VL53L8 semantics:
  - `5`, `6`, `9`, and `10` are usable range readings when range is non-zero.
  - valid-status ranges above the firmware trusted band render as clear.
  - non-OK statuses such as `2`, `4`, or `255` are invalid/uncertain even when
    their range field looks plausible, and should be visually distinct without
    hiding their raw status code.
- Update the debug card copy and error messages from VL53L5CX to VL53L8CX.

The grid remains compact and operator-focused: one heat-map cell per zone,
range in millimeters, status pill, and border color. The STM32 Control view has
`Rear` and `Front` debug selectors, but v1.2.0 physically verifies only the
rear role. Selecting `Front` with one rear sensor connected should show the
front role as unavailable and avoid displaying stale rear frames.

## Phase 2: Autonomous Mode

Autonomous mode keeps the existing safety split:

- Forward safety remains iOS ARKit/LiDAR depth through `SafetySupervisor`.
- Rear safety remains firmware VL53L8 through FE43, with FE63 health surfaced
  in the iOS UI.

iOS should not reinterpret rear ToF grid frames in Drive mode. The invariant is:

```text
Drive mode command path
  -> iOS planner command
  -> iOS forward safety supervisor
  -> FE41 command
  -> firmware rear VL53L8 safety gate
  -> PWM output
```

The iOS autonomous view should add a rear ToF health/presentation layer:

- show FE63 state, last error, and scan rate in the safety HUD;
- have `SelfDrivingViewModel` observe `STM32TofService` status changes so FE63
  health updates redraw the HUD;
- continue using FE43 for rear BRAKE overlays and alarm;
- display "rear sensor not ready" when FE63 reports no sensor, boot failure,
  input/output error, or driver-dead status;
- never turn on FE62 debug streaming during Drive.

This gives the operator enough information to see whether autonomous motion is
being held by firmware rear safety without coupling the planner to BLE details.

## Future Two-Sensor Extension

The future front/rear SATEL-VL53L8 topology needs one additional protocol fact
from firmware: which physical sensor produced a frame or safety summary. iOS
should prepare names around "sensor role" without requiring that role in the
current wire payload.

Recommended shape:

```swift
public enum TofSensorRole: Equatable, Sendable {
    case rear
    case front
    case unknown
}
```

Today, FE61 carries the selected debug role and FE63 reports the selected role
plus available-role mask. FE62 publishes one selected debug depth stream at a
time. When the future front sensor is installed, the same role convention
continues; autonomous safety should consume high-level role-aware safety state
rather than raw debug frames.

Autonomous safety then remains direction-aware:

- rear VL53L8 gates reverse motion in firmware;
- front VL53L8 can either replace iOS scalar forward LiDAR depth or publish a
  firmware front safety event, depending on the firmware protocol chosen later;
- the planner consumes only high-level safety state, not raw BLE frames.

## Error Handling

The app must keep bad sensor identity and mode lock distinct:

- FE61 writes for anything other than `vl53l8cx` are invalid configuration.
- FE61 writes in Drive/Park are mode-locked.
- FE63 driver failures are displayed as rear ToF health failures.
- FE62 chunk drops are counted and shown only in Debug.

## Verification

Debug-view implementation must be covered by:

- `STM32TofServiceTests` for FE61 payload bytes, V2 parsing, and chunk
  reassembly.
- `TofTypes` tests for VL53L8 zone classification.
- `STM32BleModeTransitionTests` proving Debug enables FE62 only after mode ack
  and Drive/Park disable debug streaming.

Autonomous-mode implementation must be covered by:

- pure presentation tests for rear ToF health;
- view-model tests or policy tests proving Drive mode does not enable debug
  streaming;
- existing planner and firmware safety event tests.

Manual verification:

- Enter STM32 Control, observe a VL53L8 4x4 grid and FE63 state.
- Switch to 8x8 and confirm frames parse at the BLE-capped rate.
- Enter Self Driving and confirm no FE62 debug streaming is enabled while FE63
  health and FE43 rear safety remain visible.
