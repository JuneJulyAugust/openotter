# Figure-Eight Waypoint Controller Rework Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the figure-eight milestone into a coherent waypoint-proportional controller that starts from the car's current pose, steers with the correct sign, moves at a useful default speed, and keeps looping until Park/Stop.

**Architecture:** Keep path tracking in iOS planner code. Telegram dispatch creates a `PlannerGoal.followFigureEight`; `WaypointPlanner` anchors the path on the first control tick because that is where `PlannerContext.pose` is available. Firmware remains unchanged and continues to own PWM clamping, watchdog behavior, and safety arbitration.

**Tech Stack:** Swift, XCTest, existing iOS planner/orchestrator/agent architecture.

**Design:** `docs/superpowers/specs/2026-06-10-figure-eight-control-design.md`

---

## File Map

### Design and technical docs

- `docs/superpowers/specs/2026-06-10-figure-eight-control-design.md`
  - Revised design, field-failure review, and implementation ownership.
- `docs/superpowers/specs/2026-06-10-figure-eight-path-following-technical.md`
  - Expanded math, control theory, steering/speed control, and pseudocode.

### Modified iOS source

- `openotter-ios/Sources/Util/RobotGeometry.swift`
  - Add forward/right vector helpers and local-to-world transform.
- `openotter-ios/Sources/Planner/PlannerProtocol.swift`
  - Add `PlannerGoal.followFigureEight(config:maxThrottle:)`.
- `openotter-ios/Sources/Planner/FigureEightTrajectory.swift`
  - Generate anchored, yaw-aligned horizontal infinity waypoints.
- `openotter-ios/Sources/Planner/Planners/WaypointPlanner.swift`
  - Fix steering sign, add closed-loop figure-eight materialization, avoid recursive advancement, add throttle floor.
- `openotter-ios/Sources/Planner/Planners/ConstantSpeedPlanner.swift`
  - Explicitly ignore figure-eight goals.
- `openotter-ios/Sources/Planner/PlannerOrchestrator.swift`
  - Route figure-eight goals to `WaypointPlanner` and expose active waypoints.
- `openotter-ios/Sources/Agent/KeywordInterpreter.swift`
  - Use default/normal throttle `0.4` after field testing showed `0.6` is too fast.
- `openotter-ios/Sources/Agent/ActionDispatcher.swift`
  - Dispatch `/figure8` as a figure-eight goal instead of precomputed global waypoints.
- `openotter-ios/Sources/Capture/SelfDrivingViewModel.swift`
  - Remove stale waypoint state.
- `openotter-ios/Sources/Views/SelfDrivingView.swift`
  - Feed map overlay from orchestrator active waypoints.

### Modified/additional tests

- `openotter-ios/Tests/Planner/RobotGeometryTests.swift`
- `openotter-ios/Tests/Planner/FigureEightTrajectoryTests.swift`
- `openotter-ios/Tests/Planner/WaypointPlannerTests.swift`
- `openotter-ios/Tests/Planner/PlannerOrchestratorTests.swift`
- `openotter-ios/Tests/Planner/ConstantSpeedPlannerTests.swift`
- `openotter-ios/Tests/Agent/KeywordInterpreterTests.swift`
- `openotter-ios/Tests/Agent/ActionDispatcherTests.swift`
- `openotter-ios/Tests/Agent/AgentRuntimeTests.swift`

---

## Task 1: Lock Coordinate And Steering Sign

**Files:**
- Modify: `openotter-ios/Sources/Util/RobotGeometry.swift`
- Add: `openotter-ios/Tests/Planner/RobotGeometryTests.swift`
- Modify: `openotter-ios/Tests/Planner/WaypointPlannerTests.swift`

- [x] **Step 1: Add axis tests**

Verify yaw `0` means:

```swift
let forward = forwardVector(yaw: 0)
let right = rightVector(yaw: 0)

XCTAssertEqual(forward.x, 1, accuracy: 1e-5)
XCTAssertEqual(forward.z, 0, accuracy: 1e-5)
XCTAssertEqual(right.x, 0, accuracy: 1e-5)
XCTAssertEqual(right.z, 1, accuracy: 1e-5)
```

- [x] **Step 2: Add steering sign tests**

Verify:

```swift
Waypoint(x: 0.5, z: 0.5)  // robot-right -> steering > 0
Waypoint(x: 0.5, z: -0.5) // robot-left  -> steering < 0
```

- [x] **Step 3: Implement helpers and steering sign**

Use:

```swift
forward_world = (cos(yaw), -sin(yaw))
right_world = (sin(yaw), cos(yaw))
steering = clamp(-gain * yawError, -1, 1)
```

---

## Task 2: Anchor Figure-Eight Waypoints To Live Pose

**Files:**
- Modify: `openotter-ios/Sources/Planner/FigureEightTrajectory.swift`
- Modify: `openotter-ios/Tests/Planner/FigureEightTrajectoryTests.swift`

- [x] **Step 1: Add anchored path tests**

Verify:

- first waypoint equals anchor pose,
- first segment enters the first right lobe,
- halfway sample crosses the anchor again,
- path rotates with anchor yaw,
- generated path stays inside configured horizontal infinity dimensions,
- final sample is close enough to first sample for a closed loop.

- [x] **Step 2: Implement anchored generator**

Generate a smoother Bernoulli-style lemniscate, normalize it to the configured
3.2 m by 1.6 m default envelope, and resample by arc length so the 240 controller
waypoints are evenly spaced. Transform each local point directly through
`worldPoint(localX:localZ:anchor:)` so the requested horizontal infinity shape
is preserved in the car frame.

---

## Task 3: Add Figure-Eight Planner Goal

**Files:**
- Modify: `openotter-ios/Sources/Planner/PlannerProtocol.swift`
- Modify: `openotter-ios/Sources/Planner/Planners/WaypointPlanner.swift`
- Modify: `openotter-ios/Sources/Planner/Planners/ConstantSpeedPlanner.swift`
- Modify: `openotter-ios/Tests/Planner/WaypointPlannerTests.swift`
- Modify: `openotter-ios/Tests/Planner/ConstantSpeedPlannerTests.swift`

- [x] **Step 1: Add goal**

```swift
case followFigureEight(config: FigureEightTrajectory.Config, maxThrottle: Float)
```

- [x] **Step 2: Materialize on first control tick**

`WaypointPlanner.setGoal` stores the config. `WaypointPlanner.plan(context:)`
generates anchored waypoints from `context.pose` when the first control tick
arrives.

- [x] **Step 3: Keep figure-eight looping**

For `followFigureEight`, wrap `currentIndex` to `0` after the last waypoint.
Finite `followWaypoints` goals still end with `.neutral`.

- [x] **Step 4: Avoid recursive waypoint advancement**

Replace recursive `plan(context:)` calls with bounded advancement over reached
waypoints. This avoids deep recursion when dense figure-eight samples are
inside the acceptance radius.

- [x] **Step 5: Recover from missed closed-loop waypoints**

For figure-eight missions, scan a short forward window and advance to the
closest future waypoint. This prevents the car from orbiting a stale waypoint
after it physically misses the acceptance radius.

---

## Task 4: Make Startup Useful But Still Bounded

**Files:**
- Modify: `openotter-ios/Sources/Agent/KeywordInterpreter.swift`
- Modify: `openotter-ios/Sources/Agent/ActionDispatcher.swift`
- Modify: `openotter-ios/Sources/Planner/Planners/WaypointPlanner.swift`
- Modify: related tests

- [x] **Step 1: Set explicit figure-eight throttle policy**

Default and `normal` are `0.4`. `/figure8` uses the current Telegram speed
directly, with no hidden multiplier. Field testing showed `0.6` was too fast;
faster runs should be requested explicitly with `speed <value>`.

- [x] **Step 2: Add waypoint throttle floor**

Use a floor during ordinary turns:

```swift
throttle = maxThrottle * max(0.35, 1 - abs(yawError) / pi)
```

Hold throttle at zero only when the target is nearly behind the car.

- [x] **Step 3: Cap steering below servo end stops**

Use `steeringFractionAt90Deg = 0.7` and `maxSteeringFraction = 0.45` so the
controller gives a visibly stronger initial turn while still avoiding full
servo travel during large heading errors.

---

## Task 5: Wire Agent, Orchestrator, And Map Overlay

**Files:**
- Modify: `openotter-ios/Sources/Agent/ActionDispatcher.swift`
- Modify: `openotter-ios/Sources/Planner/PlannerOrchestrator.swift`
- Modify: `openotter-ios/Sources/Capture/SelfDrivingViewModel.swift`
- Modify: `openotter-ios/Sources/Views/SelfDrivingView.swift`
- Modify: related tests

- [x] **Step 1: Dispatch figure-eight as a planner goal**

`/figure8` now dispatches:

```swift
.followFigureEight(
    config: .init(segmentCount: 240, length: 3.2, width: 1.6, acceptanceRadius: 0.12),
    maxThrottle: interpreter.currentThrottle
)
```

- [x] **Step 2: Route figure-eight to WaypointPlanner**

`PlannerOrchestrator.ensurePlanner(for:)` treats `.followFigureEight` like
`.followWaypoints`.

- [x] **Step 3: Publish active waypoints**

`WaypointPlanner` conforms to `WaypointDebugProviding`; `PlannerOrchestrator`
publishes `activeWaypoints`.

- [x] **Step 4: Use real planner waypoints in the map**

`SelfDrivingView` passes `viewModel.orchestrator.activeWaypoints` to
`PoseMapView`.

---

## Task 6: Verification

**Files:**
- All files above

- [x] **Step 1: Build for testing**

Run:

```bash
cd openotter-ios
APP_VERSION=$(cat VERSION) xcodegen generate
xcodebuild build-for-testing \
  -project openotter.xcodeproj \
  -scheme openotter \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST BUILD SUCCEEDED **`.

- [x] **Step 2: Run full tests**

The default simulator got stuck in `Busy` preflight state, so pin a clean
available simulator:

```bash
SIMULATOR_UDID=40B418BA-9B70-4B34-9D13-81E3A3F281A9 bash openotter-ios/build.sh test
```

Expected: `259 tests, 0 failures`.

---

## Later Milestone: Pure Pursuit

Do not mix this into the waypoint-controller PR. After a basement run produces
logs, add a separate pure-pursuit controller with:

- trajectory point yaw/curvature,
- closest-path projection,
- arc-length lookahead,
- curvature-to-steering conversion,
- speed PI control,
- slow steering trim.
