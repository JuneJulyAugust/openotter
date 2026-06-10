# Figure-Eight Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a practical iOS-side figure-eight path tracker for basement driving, with firmware kept as the deterministic actuator/safety layer and optional drive-status telemetry for tuning.

**Architecture:** Add pure Swift trajectory and controller math under `openotter-ios/Sources/Planner/`, integrate it through `PlannerProtocol` and `PlannerOrchestrator`, and expose controls/telemetry in `SelfDrivingView`. Firmware does not own path tracking; it may add an FE42 status payload to report desired/applied PWM after arbitration.

**Tech Stack:** Swift, Combine, SwiftUI, XCTest for iOS planner/controller work; C11 and host tests for optional STM32 FE42 status telemetry.

**Design:** `docs/superpowers/specs/2026-06-10-figure-eight-control-design.md`

---

## File Map

### iOS - new

- `openotter-ios/Sources/Planner/Trajectory/TrajectoryPoint.swift`
  - `TrajectoryPoint`, `SampledTrajectory`, `PathTrackingDebugState`.
- `openotter-ios/Sources/Planner/Trajectory/FigureEightTrajectory.swift`
  - Generates anchored sampled figure-eight paths.
- `openotter-ios/Sources/Planner/Trajectory/PathProjection.swift`
  - Closest-point and lookahead-point helpers.
- `openotter-ios/Sources/Planner/Planners/PathTrackingConfig.swift`
  - Tunable controller defaults and clamps.
- `openotter-ios/Sources/Planner/Planners/PathTrackingPlanner.swift`
  - `PlannerProtocol` implementation using pure pursuit, speed PI, and trim.
- `openotter-ios/Tests/Planner/FigureEightTrajectoryTests.swift`
- `openotter-ios/Tests/Planner/PathProjectionTests.swift`
- `openotter-ios/Tests/Planner/PathTrackingPlannerTests.swift`

### iOS - modified

- `openotter-ios/Sources/Planner/PlannerProtocol.swift`
  - Add trajectory goal.
- `openotter-ios/Sources/Planner/PlannerOrchestrator.swift`
  - Expose latest path debug state when active planner provides it.
- `openotter-ios/Sources/Capture/SelfDrivingViewModel.swift`
  - Add figure-eight start/park entry point and path overlay state.
- `openotter-ios/Sources/Views/PoseMapView.swift`
  - Draw sampled trajectory.
- `openotter-ios/Sources/Views/SelfDrivingView.swift`
  - Add compact Figure 8 controls and tracking metrics.
- `openotter-ios/Tests/Planner/PlannerOrchestratorTests.swift`
  - Cover planner debug-state exposure.

### Firmware - optional

- `firmware/stm32-mcp/Core/Inc/ble_drive_status.h`
- `firmware/stm32-mcp/Core/Src/ble_drive_status.c`
- `firmware/stm32-mcp/tests/host/test_ble_drive_status.c`
- `firmware/stm32-mcp/Core/Inc/ble_app.h`
- `firmware/stm32-mcp/Core/Src/ble_app.c`
- `openotter-ios/Sources/Capture/STM32DriveStatus.swift`
- `openotter-ios/Tests/Capture/STM32DriveStatusTests.swift`

---

## Task 1: Lock the coordinate invariant with tests

**Files:**
- Modify: `openotter-ios/Tests/Planner/PlannerTestFactory.swift`
- Create: `openotter-ios/Tests/Planner/RobotGeometryTests.swift`

- [ ] **Step 1: Add tests for yaw and local axes**

Create tests proving:

```swift
// yaw 0 means forward is +x, right is +z.
XCTAssertEqual(forward.x, 1, accuracy: 1e-5)
XCTAssertEqual(forward.z, 0, accuracy: 1e-5)
XCTAssertEqual(right.x, 0, accuracy: 1e-5)
XCTAssertEqual(right.z, 1, accuracy: 1e-5)
```

- [ ] **Step 2: Add a helper for test poses**

Use:

```swift
static func pose(x: Float, z: Float, yaw: Float, timestamp: TimeInterval = 0) -> PoseEntry {
    PoseEntry(timestamp: timestamp, x: x, y: 0, z: z, yaw: yaw, confidence: 1)
}
```

- [ ] **Step 3: Run the failing test**

Run:

```bash
bash openotter-ios/build.sh test
```

Expected: new tests compile and expose any mismatch in current heading math.

- [ ] **Step 4: Implement minimal geometry helpers if needed**

Add pure helpers near `RobotGeometry.swift` only if tests require them:

```swift
struct GroundVector: Equatable {
    let x: Float
    let z: Float
}

func forwardVector(yaw: Float) -> GroundVector {
    GroundVector(x: cosf(yaw), z: -sinf(yaw))
}

func rightVector(yaw: Float) -> GroundVector {
    GroundVector(x: sinf(yaw), z: cosf(yaw))
}
```

- [ ] **Step 5: Run tests and commit**

Run:

```bash
bash openotter-ios/build.sh test
git add openotter-ios/Sources/Util/RobotGeometry.swift openotter-ios/Tests/Planner/RobotGeometryTests.swift openotter-ios/Tests/Planner/PlannerTestFactory.swift
git commit -m "test: lock ground-plane coordinate geometry"
```

---

## Task 2: Add sampled trajectory value types

**Files:**
- Create: `openotter-ios/Sources/Planner/Trajectory/TrajectoryPoint.swift`
- Create: `openotter-ios/Tests/Planner/FigureEightTrajectoryTests.swift`

- [ ] **Step 1: Write failing value-type tests**

Tests should verify a sampled trajectory rejects empty paths and stores total
arc length:

```swift
func testSampledTrajectoryStoresClosedPathMetadata() {
    let points = [
        TrajectoryPoint(x: 0, z: 0, yaw: 0, curvature: 0, arcLength: 0),
        TrajectoryPoint(x: 1, z: 0, yaw: 0, curvature: 0, arcLength: 1)
    ]
    let trajectory = SampledTrajectory(points: points, isClosed: true)
    XCTAssertEqual(trajectory.totalLength, 1, accuracy: 1e-5)
    XCTAssertTrue(trajectory.isClosed)
}
```

- [ ] **Step 2: Implement the types**

Add:

```swift
struct TrajectoryPoint: Equatable {
    let x: Float
    let z: Float
    let yaw: Float
    let curvature: Float
    let arcLength: Float
}

struct SampledTrajectory: Equatable {
    let points: [TrajectoryPoint]
    let isClosed: Bool

    var totalLength: Float {
        points.last?.arcLength ?? 0
    }
}

struct PathTrackingDebugState: Equatable {
    let closestIndex: Int
    let lookaheadIndex: Int
    let crossTrackErrorM: Float
    let headingErrorRad: Float
    let curvatureCommand: Float
    let targetSpeedMps: Float
    let measuredSpeedMps: Float?
    let steeringTrim: Float
}
```

- [ ] **Step 3: Run tests and commit**

Run:

```bash
bash openotter-ios/build.sh test
git add openotter-ios/Sources/Planner/Trajectory/TrajectoryPoint.swift openotter-ios/Tests/Planner/FigureEightTrajectoryTests.swift
git commit -m "planner: add sampled trajectory value types"
```

---

## Task 3: Generate an anchored figure-eight trajectory

**Files:**
- Create: `openotter-ios/Sources/Planner/Trajectory/FigureEightTrajectory.swift`
- Modify: `openotter-ios/Tests/Planner/FigureEightTrajectoryTests.swift`

- [ ] **Step 1: Add generator tests**

Cover:

- generated point count equals requested sample count,
- path stays inside `length_m` and `width_m`,
- first point equals anchor position,
- first tangent aligns with anchor yaw,
- final point is close to first point for a closed loop.

- [ ] **Step 2: Implement config and generator**

Use:

```swift
struct FigureEightConfig: Equatable {
    var lengthM: Float = 3.0
    var widthM: Float = 1.8
    var sampleCount: Int = 240
    var laps: Int = 1
}

enum FigureEightTrajectory {
    static func make(config: FigureEightConfig, anchor: PoseEntry) -> SampledTrajectory {
        // Generate local points:
        // x = length/2 * sin(t)
        // z = width/2 * sin(2t)
        // Rotate so the t=0 tangent matches anchor.yaw.
        // Translate by anchor.x/anchor.z.
    }
}
```

- [ ] **Step 3: Estimate yaw, curvature, and arc length**

Use neighboring samples:

```swift
let yaw = atan2f(-dz, dx)
let curvature = signedCurvature(previous, current, next)
```

Clamp non-finite curvature to zero.

- [ ] **Step 4: Run tests and commit**

Run:

```bash
bash openotter-ios/build.sh test
git add openotter-ios/Sources/Planner/Trajectory/FigureEightTrajectory.swift openotter-ios/Tests/Planner/FigureEightTrajectoryTests.swift
git commit -m "planner: generate anchored figure-eight trajectory"
```

---

## Task 4: Add path projection and lookahead

**Files:**
- Create: `openotter-ios/Sources/Planner/Trajectory/PathProjection.swift`
- Create: `openotter-ios/Tests/Planner/PathProjectionTests.swift`

- [ ] **Step 1: Add projection tests**

Cover:

- closest point near pose is returned,
- search starts near previous index,
- closed path wraps at end,
- lookahead advances by arc length,
- lookahead wraps on a closed path.

- [ ] **Step 2: Implement projection**

Use a local search window to avoid jumping to the other branch of the figure
eight at the crossover:

```swift
struct PathProjection {
    let closestIndex: Int
    let lookaheadIndex: Int
    let crossTrackErrorM: Float
    let headingErrorRad: Float
}
```

Search around the previous closest index first. If the planner has no previous
index, do a full search for initialization.

- [ ] **Step 3: Run tests and commit**

Run:

```bash
bash openotter-ios/build.sh test
git add openotter-ios/Sources/Planner/Trajectory/PathProjection.swift openotter-ios/Tests/Planner/PathProjectionTests.swift
git commit -m "planner: add trajectory projection and lookahead"
```

---

## Task 5: Add the path-tracking planner

**Files:**
- Create: `openotter-ios/Sources/Planner/Planners/PathTrackingConfig.swift`
- Create: `openotter-ios/Sources/Planner/Planners/PathTrackingPlanner.swift`
- Create: `openotter-ios/Tests/Planner/PathTrackingPlannerTests.swift`
- Modify: `openotter-ios/Sources/Planner/PlannerProtocol.swift`

- [ ] **Step 1: Extend planner goal**

Add:

```swift
case followTrajectory(SampledTrajectory, config: PathTrackingConfig)
```

- [ ] **Step 2: Add steering tests**

Cover:

- inactive planner returns `.neutral`,
- target straight ahead gives near-zero steering,
- target to right gives positive steering,
- target to left gives negative steering,
- output is clamped to `[-1, +1]`,
- stale timestamp does not jump trim or throttle.

- [ ] **Step 3: Implement pure pursuit steering**

Core formula:

```swift
let curvature = 2 * rightOffset / max(lookaheadDistance * lookaheadDistance, 0.01)
let steeringAngle = atan(config.wheelbaseM * curvature)
let steering = clamp(steeringAngle / config.maxSteeringAngleRad + steeringTrim, -1, 1)
```

- [ ] **Step 4: Add speed target tests**

Cover:

- high curvature lowers target speed,
- low curvature uses cruise speed,
- missing speed falls back to conservative throttle,
- PI throttle increases when measured speed is below target.

- [ ] **Step 5: Implement speed PI and throttle rate limit**

Use the same timing guard shape as `ConstantSpeedPlanner`:

```swift
guard dt > 0, dt < 1 else { return previousOutput }
```

Clamp integral and throttle output.

- [ ] **Step 6: Add steering trim tests**

Cover:

- persistent positive cross-track error changes trim in correcting direction,
- trim is clamped,
- reset clears trim.

- [ ] **Step 7: Run tests and commit**

Run:

```bash
bash openotter-ios/build.sh test
git add openotter-ios/Sources/Planner/PlannerProtocol.swift openotter-ios/Sources/Planner/Planners/PathTrackingConfig.swift openotter-ios/Sources/Planner/Planners/PathTrackingPlanner.swift openotter-ios/Tests/Planner/PathTrackingPlannerTests.swift
git commit -m "planner: add pure pursuit path tracker"
```

---

## Task 6: Integrate figure-eight mode into the orchestrator and view model

**Files:**
- Modify: `openotter-ios/Sources/Planner/PlannerOrchestrator.swift`
- Modify: `openotter-ios/Sources/Capture/SelfDrivingViewModel.swift`
- Modify: `openotter-ios/Tests/Planner/PlannerOrchestratorTests.swift`

- [ ] **Step 1: Add debug-state protocol**

Add:

```swift
protocol PathTrackingDebugProviding: AnyObject {
    var debugState: PathTrackingDebugState? { get }
}
```

Have `PathTrackingPlanner` conform.

- [ ] **Step 2: Expose debug state through orchestrator**

When active planner conforms to `PathTrackingDebugProviding`, publish the last
debug state after each tick.

- [ ] **Step 3: Add `startFigureEight(config:)`**

In `SelfDrivingViewModel`, create the trajectory from `poseModel.currentPose`,
swap to `PathTrackingPlanner`, publish the path overlay, and call
`orchestrator.setGoal`.

- [ ] **Step 4: Run tests and commit**

Run:

```bash
bash openotter-ios/build.sh test
git add openotter-ios/Sources/Planner/PlannerOrchestrator.swift openotter-ios/Sources/Capture/SelfDrivingViewModel.swift openotter-ios/Tests/Planner/PlannerOrchestratorTests.swift
git commit -m "planner: wire figure-eight tracker into orchestrator"
```

---

## Task 7: Add UI controls and map overlay

**Files:**
- Modify: `openotter-ios/Sources/Views/PoseMapView.swift`
- Modify: `openotter-ios/Sources/Views/SelfDrivingView.swift`
- Add/modify view tests if current snapshot/unit patterns support it.

- [ ] **Step 1: Draw sampled trajectory**

Add a `trajectory: SampledTrajectory?` parameter to `PoseMapView` and draw it
as a continuous line separate from recorded pose history.

- [ ] **Step 2: Add Figure 8 controls**

Add compact controls for:

- length,
- width,
- cruise speed,
- laps,
- start,
- park.

Keep controls in the existing landscape HUD style.

- [ ] **Step 3: Add tracking metrics**

Display:

- cross-track error,
- heading error,
- target speed,
- measured speed,
- steering trim.

- [ ] **Step 4: Run tests and commit**

Run:

```bash
bash openotter-ios/build.sh test
git add openotter-ios/Sources/Views/PoseMapView.swift openotter-ios/Sources/Views/SelfDrivingView.swift
git commit -m "ios: add figure-eight controls and trajectory overlay"
```

---

## Task 8: Optional firmware drive-status telemetry

**Files:**
- Create: `firmware/stm32-mcp/Core/Inc/ble_drive_status.h`
- Create: `firmware/stm32-mcp/Core/Src/ble_drive_status.c`
- Create: `firmware/stm32-mcp/tests/host/test_ble_drive_status.c`
- Modify: `firmware/stm32-mcp/tests/host/Makefile`
- Modify: `firmware/stm32-mcp/Core/Inc/ble_app.h`
- Modify: `firmware/stm32-mcp/Core/Src/ble_app.c`
- Create: `openotter-ios/Sources/Capture/STM32DriveStatus.swift`
- Create: `openotter-ios/Tests/Capture/STM32DriveStatusTests.swift`

- [ ] **Step 1: Add C codec tests**

Verify payload size and field encoding for:

- desired PWM,
- applied PWM,
- mode,
- watchdog flag,
- safety flag.

- [ ] **Step 2: Implement the HAL-free codec**

Keep byte packing outside BlueNRG calls so host tests cover it.

- [ ] **Step 3: Publish FE42 status**

Update FE42 from `BLE_App_Process` at a low fixed rate, for example 5 Hz, after
PWM arbitration.

- [ ] **Step 4: Parse in iOS**

Add a Swift model and parser tests mirroring the C payload.

- [ ] **Step 5: Run firmware and iOS tests**

Run:

```bash
make -C firmware/stm32-mcp/tests/host test
bash openotter-ios/build.sh test
```

- [ ] **Step 6: Commit**

Run:

```bash
git add firmware/stm32-mcp/Core/Inc/ble_drive_status.h firmware/stm32-mcp/Core/Src/ble_drive_status.c firmware/stm32-mcp/tests/host/test_ble_drive_status.c firmware/stm32-mcp/tests/host/Makefile firmware/stm32-mcp/Core/Inc/ble_app.h firmware/stm32-mcp/Core/Src/ble_app.c openotter-ios/Sources/Capture/STM32DriveStatus.swift openotter-ios/Tests/Capture/STM32DriveStatusTests.swift
git commit -m "firmware: publish drive actuator status"
```

---

## Task 9: Field tuning checklist

**Files:**
- Create: `docs/superpowers/specs/2026-06-10-figure-eight-field-tuning.md`

- [ ] **Step 1: Document preflight**

Include:

- wheels off ground,
- verify steering sign,
- verify Park forces neutral throttle,
- verify safety overlay/alarm still works,
- verify trajectory overlay aligns with map.

- [ ] **Step 2: Document first-run sequence**

Use:

```text
length=1.5 m
width=1.0 m
cruise_speed=0.25 m/s
laps=1
```

Increase only after cross-track error and safety behavior look stable.

- [ ] **Step 3: Commit**

Run:

```bash
git add docs/superpowers/specs/2026-06-10-figure-eight-field-tuning.md
git commit -m "docs: add figure-eight field tuning checklist"
```

---

## Verification Commands

Run before opening a PR:

```bash
make -C firmware/stm32-mcp/tests/host test
bash openotter-ios/build.sh test
```

Optional hardware validation:

```bash
bash firmware/stm32-mcp/build.sh build
bash firmware/stm32-mcp/build.sh flash
bash openotter-ios/build.sh --release deploy
```

The flash/deploy commands require the physical STM32/iPhone and host approval.
