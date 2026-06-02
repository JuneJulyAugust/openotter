# iOS VL53L8 ToF Debug And Autonomy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Make the iOS STM32 ToF debug visualization work with SATEL-VL53L8 firmware frames first, then surface VL53L8 rear sensor health and safety state in autonomous mode.

**Architecture:** Keep the existing CoreBluetooth and planner boundaries. Rename the iOS ToF model from VL53L5CX to VL53L8CX while preserving wire value `2`, keep FE62 frame streaming Debug-only, and use FE63/FE43 for autonomous rear-safety visibility in Drive.

**Tech Stack:** Swift, SwiftUI, Combine, CoreBluetooth, XCTest, `openotter-ios/build.sh`.

---

## Release-Candidate Status

- Version prepared: `openotter-ios` `1.2.0`.
- Branch status: implemented and committed as a release candidate; not merged
  or tagged yet.
- Debug status: STM32 Control was deployed from the feature worktree and the
  live VL53L8 ToF visualization worked against the connected IOT01A1.
- Autonomous status: rear ToF health presentation is implemented; full
  vehicle-level autonomous validation is still pending.

## Files

- Modify: `openotter-ios/VERSION`
- Modify: `openotter-ios/Sources/Capture/TofTypes.swift`
- Modify: `openotter-ios/Sources/Capture/STM32TofService.swift`
- Modify: `openotter-ios/Sources/Capture/STM32ControlViewModel.swift`
- Modify: `openotter-ios/Sources/Capture/SelfDrivingViewModel.swift`
- Create: `openotter-ios/Sources/Capture/TofHealthPresentation.swift`
- Modify: `openotter-ios/Sources/Views/TofGridView.swift`
- Modify: `openotter-ios/Sources/Views/STM32ControlView.swift`
- Modify: `openotter-ios/Sources/Views/SelfDrivingView.swift`
- Modify: `openotter-ios/Tests/Capture/STM32TofServiceTests.swift`
- Create: `openotter-ios/Tests/Capture/TofHealthPresentationTests.swift`
- Modify: `openotter-ios/Tests/Capture/STM32BleModeTransitionTests.swift`
- Modify: `openotter-ios/build.sh`
- Modify: `openotter-ios/project.yml`
- Modify: `openotter-ios/README.md`
- Modify: `openotter-ios/CHANGELOG.md`

## Task 1: Rename The iOS ToF Wire Model To VL53L8

**Files:**
- Modify: `openotter-ios/Sources/Capture/TofTypes.swift`
- Modify: `openotter-ios/Tests/Capture/STM32TofServiceTests.swift`

- [x] **Step 1: Update tests for the new sensor semantic name**

In `openotter-ios/Tests/Capture/STM32TofServiceTests.swift`, rename the
VL53L5 tests to VL53L8 and change expected enum cases:

```swift
func testVL53L8CXConfigEncodesFE61V2() {
    let payload = STM32TofService.makeConfigPayload(
        sensor: .vl53l8cx,
        layout: 8,
        profile: 1,
        frequencyHz: 10,
        integrationMs: 20,
        budgetMs: 0
    )

    XCTAssertEqual([UInt8](payload), [2, 8, 1, 10, 20, 0, 0, 0])
}
```

Expected: tests fail because `.vl53l8cx` is not defined.

- [x] **Step 2: Rename the enum case while preserving wire value**

In `openotter-ios/Sources/Capture/TofTypes.swift`, change:

```swift
public enum TofSensorType: UInt8, Equatable, Sendable {
    case none = 0
    case vl53l1cb = 1
    case vl53l8cx = 2
    case unknown = 255
}
```

Do not keep `.vl53l5cx`; the deployment path is deprecated and compile errors
should force every call site to choose the new name.

- [x] **Step 3: Add a current sensor display name**

Add this extension below `TofSensorType`:

```swift
public extension TofSensorType {
    var displayName: String {
        switch self {
        case .none: return "None"
        case .vl53l1cb: return "VL53L1CB"
        case .vl53l8cx: return "VL53L8CX"
        case .unknown: return "Unknown"
        }
    }
}
```

- [x] **Step 4: Run the focused ToF tests**

Run:

```sh
cd openotter-ios
./build.sh test
```

Expected: failures only at call sites still using `.vl53l5cx` or VL53L5 names.

## Task 2: Rename VL53L8 Zone Classification

**Files:**
- Modify: `openotter-ios/Sources/Capture/TofTypes.swift`
- Modify: `openotter-ios/Sources/Views/TofGridView.swift`
- Modify: `openotter-ios/Tests/Capture/STM32TofServiceTests.swift`

- [x] **Step 1: Rename the zone class type and tests**

Replace `VL53L5CXZoneClass` with:

```swift
public enum VL53L8CXZoneClass: Equatable, Sendable {
    case invalid
    case clear
    case valid
}
```

Rename tests:

```swift
func testVL53L8CXFarStatus2ClassifiesAsClear() {
    XCTAssertEqual(ZoneReading(rangeMm: 4300,
                               status: VL53L1RangeStatus(raw: 2),
                               flags: 1).vl53l8cxClass,
                   .clear)
    XCTAssertEqual(ZoneReading(rangeMm: 0,
                               status: VL53L1RangeStatus(raw: 2),
                               flags: 0).vl53l8cxClass,
                   .clear)
}

func testVL53L8CXNearStatus2StaysInvalid() {
    XCTAssertEqual(ZoneReading(rangeMm: 1000,
                               status: VL53L1RangeStatus(raw: 2),
                               flags: 1).vl53l8cxClass,
                   .invalid)
}
```

- [x] **Step 2: Implement the VL53L8 class helper**

In `ZoneReading` extension, replace `vl53l5cxClass` with:

```swift
var vl53l8cxClass: VL53L8CXZoneClass {
    switch status.rawValue {
    case 5, 6, 9, 10:
        return rangeMm > 0 ? .valid : .invalid
    case 2 where rangeMm >= 4000:
        return .clear
    default:
        return rangeMm == 0 && flags == 0 ? .clear : .invalid
    }
}
```

- [x] **Step 3: Update `TofGridView` to use VL53L8 semantics**

Replace every `.vl53l5cx` check with `.vl53l8cx`, and every
`vl53l5cxClass` call with `vl53l8cxClass`.

Keep legacy VL53L1 rendering for `.vl53l1cb` frames only; this is historical
parser compatibility, not the active deployment path.

- [x] **Step 4: Verify**

Run:

```sh
cd openotter-ios
./build.sh test
```

Expected: ToF tests pass or remaining failures point to stale VL53L5 names.

## Task 3: Make `STM32TofService` Default To VL53L8

**Files:**
- Modify: `openotter-ios/Sources/Capture/STM32TofService.swift`
- Modify: `openotter-ios/Sources/Capture/STM32ControlViewModel.swift`
- Modify: `openotter-ios/Tests/Capture/STM32TofServiceTests.swift`

- [x] **Step 1: Change service preferred config**

In `STM32TofService`, change:

```swift
private var preferredConfig = TofConfig(sensor: .vl53l8cx,
                                        layout: 4,
                                        distMode: 1,
                                        budgetUs: 0,
                                        frequencyHz: 10,
                                        integrationMs: 20)
```

Update the file header so the frame wire authority points to
`firmware/stm32-mcp/Core/Inc/tof_frame_codec.h` and
`firmware/stm32-mcp/Core/Inc/tof_types.h`.

- [x] **Step 2: Change debug view model default config**

In `STM32ControlViewModel`, change:

```swift
@Published var tofConfig = TofConfig(sensor: .vl53l8cx,
                                     layout: 4,
                                     distMode: 1,
                                     budgetUs: 0,
                                     frequencyHz: 10,
                                     integrationMs: 20)
```

Rename helper functions in `TofConfig`:

```swift
public static func maxL8FrequencyHz(layout: UInt8) -> UInt8
public static func maxL8IntegrationMs(frequencyHz: UInt8) -> UInt16
public static func clampL8IntegrationMs(_ requestedMs: UInt16,
                                        frequencyHz: UInt8) -> UInt16
public static func defaultL8IntegrationMs(layout: UInt8) -> UInt16
```

Use the same formulas currently used by the L5-named helpers.

- [x] **Step 3: Update config send path**

In `STM32ControlViewModel.sendTofConfig()`, collapse to the VL53L8 path:

```swift
tofService.sendConfig(sensor: tofConfig.sensor,
                      layout: tofConfig.layout,
                      profile: tofConfig.distMode,
                      frequencyHz: tofConfig.frequencyHz,
                      integrationMs: tofConfig.integrationMs,
                      budgetMs: UInt16(min(UInt32(UInt16.max),
                                           tofConfig.budgetUs / 1000)))
```

The legacy L1 branch can be removed because firmware rejects deprecated sensor
config writes.

- [x] **Step 4: Verify parser tests**

Update `makeV2Payload(layout:)` test helper to expect `.vl53l8cx` and keep
wire byte `2`. Run:

```sh
cd openotter-ios
./build.sh test
```

Expected: `STM32TofServiceTests` pass.

## Task 4: Update The STM32 Debug Card UI

**Files:**
- Modify: `openotter-ios/Sources/Views/STM32ControlView.swift`
- Modify: `openotter-ios/Sources/Views/TofGridView.swift`

- [x] **Step 1: Rename visible text**

Change the group label in `STM32ControlView` to:

```swift
Label("VL53L8CX DEPTH MAP", systemImage: "square.grid.3x3.fill")
```

Update error strings:

```swift
case 1:  return "VL53L8CX not detected"
case 2:  return "VL53L8CX boot failed"
case 3:  return "VL53L8CX I2C error"
case 4:  return "Firmware rejected VL53L8CX config"
case 5:  return "VL53L8CX driver missing"
case 6:  return "VL53L8CX driver offline"
case 11: return "Config locked outside Debug mode"
```

Status code `6` now maps to `TOF_STATUS_DRIVER_DEAD`; the old iOS text
"Firmware rejected layout" is no longer correct.

- [x] **Step 2: Use display names in debug text**

Change the debug line to use:

```swift
Text(verbatim: "sensor \(viewModel.tofConfig.sensor.displayName)  layout \(viewModel.tofConfig.layout)x\(viewModel.tofConfig.layout)  freq \(viewModel.tofConfig.frequencyHz)Hz  it \(viewModel.tofConfig.integrationMs)ms")
```

- [x] **Step 3: Improve empty state**

Replace "Waiting for frame..." with mode-aware copy:

```swift
Text(viewModel.firmwareMode == .debug ? "Waiting for VL53L8 frame..." : "Switch to Debug for depth frames")
```

- [x] **Step 4: Manual debug check**

Run the app on device after firmware is flashed:

```sh
cd openotter-ios
./build.sh deploy
```

Expected:

- entering STM32 Control puts firmware in Debug;
- FE62 chunks increase;
- 4x4 frames render as a 4x4 grid;
- 8x8 frames render as an 8x8 grid at the capped rate;
- FE63 status shows running and a non-zero scan rate.

Status: passed on 2026-06-02. The feature-worktree app deployed to the iPhone,
entered STM32 Control, and rendered live VL53L8 ToF data from the flashed
IOT01A1 plus one SATEL-VL53L8.

## Task 5: Add Rear ToF Health Presentation For Autonomous Mode

**Files:**
- Create: `openotter-ios/Sources/Capture/TofHealthPresentation.swift`
- Create: `openotter-ios/Tests/Capture/TofHealthPresentationTests.swift`
- Modify: `openotter-ios/Sources/Capture/SelfDrivingViewModel.swift`

- [x] **Step 1: Write presentation tests**

Create `openotter-ios/Tests/Capture/TofHealthPresentationTests.swift`:

```swift
import XCTest
@testable import openotter

final class TofHealthPresentationTests: XCTestCase {
    func testRunningHealth() {
        let p = TofHealthPresentation(state: .running, lastError: 0, scanHz: 30)
        XCTAssertEqual(p.statusText, "RUNNING")
        XCTAssertEqual(p.detailText, "30 Hz")
        XCTAssertEqual(p.compactDetailText, "30 Hz")
        XCTAssertFalse(p.isError)
    }

    func testNoSensorError() {
        let p = TofHealthPresentation(state: .error, lastError: 1, scanHz: 0)
        XCTAssertEqual(p.statusText, "ERROR")
        XCTAssertEqual(p.detailText, "VL53L8CX not detected")
        XCTAssertEqual(p.compactDetailText, "No sensor")
        XCTAssertTrue(p.isError)
    }

    func testLockedModeIsNotHealthFailure() {
        let p = TofHealthPresentation(state: .running, lastError: 11, scanHz: 30)
        XCTAssertEqual(p.detailText, "Config locked outside Debug mode")
        XCTAssertEqual(p.compactDetailText, "Locked")
        XCTAssertFalse(p.isError)
    }
}
```

Expected: fails because `TofHealthPresentation` does not exist.

- [x] **Step 2: Implement presentation model**

Create `openotter-ios/Sources/Capture/TofHealthPresentation.swift`:

```swift
import Foundation

struct TofHealthPresentation: Equatable {
    let statusText: String
    let detailText: String
    let compactDetailText: String
    let isError: Bool

    init(state: TofState, lastError: UInt8, scanHz: UInt8) {
        statusText = {
            switch state {
            case .idle: return "IDLE"
            case .running: return "RUNNING"
            case .error: return "ERROR"
            case .unknown: return "UNKNOWN"
            }
        }()

        detailText = Self.detail(lastError: lastError, scanHz: scanHz)
        compactDetailText = Self.compactDetail(lastError: lastError, scanHz: scanHz)
        isError = state == .error || [1, 2, 3, 5, 6].contains(lastError)
    }

    private static func detail(lastError: UInt8, scanHz: UInt8) -> String {
        switch lastError {
        case 0: return "\(scanHz) Hz"
        case 1: return "VL53L8CX not detected"
        case 2: return "VL53L8CX boot failed"
        case 3: return "VL53L8CX I2C error"
        case 4: return "Firmware rejected VL53L8CX config"
        case 5: return "VL53L8CX driver missing"
        case 6: return "VL53L8CX driver offline"
        case 11: return "Config locked outside Debug mode"
        default: return "ToF error \(lastError)"
        }
    }

    private static func compactDetail(lastError: UInt8, scanHz: UInt8) -> String {
        switch lastError {
        case 0: return "\(scanHz) Hz"
        case 1: return "No sensor"
        case 2: return "Boot fail"
        case 3: return "I2C"
        case 4: return "Config"
        case 5: return "Missing"
        case 6: return "Offline"
        case 11: return "Locked"
        default: return "Err \(lastError)"
        }
    }
}
```

- [x] **Step 3: Expose rear ToF health from SelfDrivingViewModel**

In `SelfDrivingViewModel`, store the ToF service and observe it so FE63 status
updates redraw the autonomous HUD:

```swift
private let tofService = STM32TofService.shared

var rearTofHealth: TofHealthPresentation {
    TofHealthPresentation(
        state: tofService.state,
        lastError: tofService.lastError,
        scanHz: tofService.scanHz
    )
}
```

In `setupSubscriptions()`, add:

```swift
tofService.objectWillChange
    .sink { [weak self] _ in self?.objectWillChange.send() }
    .store(in: &cancellables)
```

This is a read-only presentation helper. Do not enable debug streaming in
Self Driving.

- [x] **Step 4: Verify**

Run:

```sh
cd openotter-ios
./build.sh test
```

Expected: health presentation tests pass.

## Task 6: Surface Rear ToF Health In Self Driving

**Files:**
- Modify: `openotter-ios/Sources/Views/SelfDrivingView.swift`
- Modify: `openotter-ios/Tests/Capture/STM32BleModeTransitionTests.swift`

- [x] **Step 1: Add rear ToF rows to the safety HUD**

In `SelfDrivingView.bottomHUD`, inside the `SAFETY` card after forward depth,
add:

```swift
let rearHealth = viewModel.rearTofHealth
MetricRow(label: "Rear ToF", value: rearHealth.statusText)
MetricRow(label: "ToF Info", value: rearHealth.compactDetailText)
```

Use red/orange text only if the local `MetricRow` API supports row coloring
without broad UI refactoring; otherwise keep the value text simple and let the
emergency overlay carry the urgent state.

- [x] **Step 2: Preserve Drive/Park streaming invariant**

Keep `STM32ModeTransitionPolicy.startActions(for:)` unchanged:

```swift
case .drive:
    return [.setDebugStreamingEnabled(false),
            .writeMode(.drive)]
case .park:
    return [.setDebugStreamingEnabled(false),
            .writeMode(.park)]
```

Add a test name making the invariant explicit:

```swift
func testAutonomousDriveDoesNotEnableDebugFrameStreaming() {
    XCTAssertEqual(STM32ModeTransitionPolicy.startActions(for: .drive),
                   [.setDebugStreamingEnabled(false),
                    .writeMode(.drive)])
}
```

- [ ] **Step 3: Manual autonomous check**

Run on device:

```sh
cd openotter-ios
./build.sh deploy
```

Expected:

- Self Driving enters Drive;
- FE62 chunks do not increase while in Drive;
- FE63 health remains visible;
- FE43 rear BRAKE overlay still appears when firmware reports rear safety brake.

Status: pending. The iOS rear ToF health presentation is implemented, but full
vehicle-level autonomous validation still requires a controlled physical run
after the release-candidate commit.
hardware.

## Task 7: Document Future Two-Sensor Hook

**Files:**
- Modify: `openotter-ios/Sources/Capture/TofTypes.swift`
- Modify: `docs/superpowers/specs/2026-06-02-ios-vl53l8-tof-debug-autonomy-design.md`

- [x] **Step 1: Add role enum without changing wire parsing**

Add:

```swift
public enum TofSensorRole: Equatable, Sendable {
    case rear
    case front
    case unknown
}
```

Keep `TofFrame` role-free in this phase unless the implementation needs a
visible label. Current firmware exposes one sensor only; role is inferred as
rear in UI copy, not encoded in the frame.

- [x] **Step 2: Keep future role protocol explicit in docs**

The design doc must state that future front/rear role must come from firmware
protocol extension, not from whichever UI tab is active.

- [x] **Step 3: Verify no behavior changed**

Run:

```sh
cd openotter-ios
./build.sh test
```

Expected: tests pass.

## Task 8: Final Verification And Commit

**Files:**
- Modify: `openotter-ios/VERSION`
- Modify: `openotter-ios/CHANGELOG.md`
- Modify: `openotter-ios/build.sh`
- Modify: `openotter-ios/project.yml`

- [x] **Step 1: Add changelog entry**

Promote the iOS release-candidate changelog to `1.2.0`, bump `VERSION`, keep
the worktree bundle identifier at `com.openotter-ios.app`, and pass
`MARKETING_VERSION` from `VERSION` into `xcodebuild`.

- [x] **Step 2: Full iOS verification**

Run:

```sh
cd openotter-ios
./build.sh test
./build.sh --release build
```

Expected: release build passes; full simulator suite either passes or records
any residual failure clearly before commit.

Status: release device deploy passed on 2026-06-02 after the bundle identifier
fix. Final release build also passed and the built app reported
`CFBundleShortVersionString=1.2.0` and
`CFBundleIdentifier=com.openotter-ios.app`.

`./build.sh test` ran the full simulator suite with the same bundle/version
overrides. It executed 200 tests with one residual failure in the existing
Telegram agent test `AgentRuntimeTests.testUnknownCommandReturnHelp`. The
VL53L8-relevant suites passed, including `STM32TofServiceTests`,
`STM32BleModeTransitionTests`, `TofHealthPresentationTests`, and
`FirmwareSafetyEventTests`.

- [x] **Step 3: Commit release candidate**

Run:

```sh
git add openotter-ios docs/superpowers .ai-context firmware/stm32-mcp
git commit -m "chore: prepare VL53L8 v1.2.0 release candidate"
```
