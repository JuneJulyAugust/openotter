# ARKit Velocity, TTC Integration & Constant Speed Planner

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Estimate vehicle speed from ARKit pose differentiation, use real speed for TTC, and replace the waypoint planner with a closed-loop constant-speed-forward planner.

**Architecture:** Add an `ARKitVelocityEstimator` that differentiates consecutive poses using timestamps. Feed real speed (motor RPM primary, ARKit fallback) into `SafetySupervisor` for TTC. Replace `WaypointPlanner` with `ConstantSpeedPlanner` that uses a PI controller to track a configurable target speed. UI shows both speed sources and a speed slider.

**Tech Stack:** Swift, SwiftUI, ARKit, Combine

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `Sources/Util/ARKitVelocityEstimator.swift` | Pose differentiation + filtering (MA / EMA) |
| Modify | `Sources/Capture/ARKitPoseViewModel.swift` | Publish `arkitSpeedMps` using the estimator |
| Modify | `Sources/Views/ARKitPoseView.swift` | Show ARKit speed in data panel |
| Modify | `Sources/Planner/PlannerContext.swift` | Add `motorSpeedMps` and `arkitSpeedMps` fields |
| Modify | `Sources/Capture/SelfDrivingViewModel.swift` | Pass both speeds into PlannerContext, swap to ConstantSpeedPlanner |
| Modify | `Sources/Planner/Safety/SafetySupervisor.swift` | Use real speed (motor primary, ARKit fallback) for TTC |
| Create | `Sources/Planner/Planners/ConstantSpeedPlanner.swift` | PI controller for constant forward speed |
| Modify | `Sources/Planner/PlannerProtocol.swift` | Add `PlannerGoal.constantSpeed(targetMps:)` |
| Modify | `Sources/Views/SelfDrivingView.swift` | Show both speeds in telemetry, add speed slider |

---

### Task 1: ARKit Velocity Estimator

**Files:**
- Create: `Sources/Util/ARKitVelocityEstimator.swift`

This is a pure computation unit. It takes consecutive `(x, z, timestamp)` tuples and outputs ground-plane speed in m/s.

- [ ] **Step 1: Create ARKitVelocityEstimator**

```swift
// Sources/Util/ARKitVelocityEstimator.swift
import Foundation

/// Velocity filter strategy for ARKit-derived speed.
enum VelocityFilterMode {
    case movingAverage
    case exponentialMovingAverage
}

/// Estimates ground-plane speed by differentiating consecutive ARKit poses.
///
/// Speed = sqrt(dx^2 + dz^2) / dt, where dx/dz are position deltas in robot frame
/// and dt is the timestamp delta between consecutive frames.
struct ARKitVelocityEstimator {

    var filterMode: VelocityFilterMode

    /// Moving average window size.
    private let maWindowSize: Int
    /// EMA smoothing factor (0..1). Higher = more responsive, noisier.
    private let emaSmoothingFactor: Double

    private var maWindow: [Double] = []
    private var emaValue: Double?
    private var lastX: Float?
    private var lastZ: Float?
    private var lastTimestamp: TimeInterval?

    init(filterMode: VelocityFilterMode = .movingAverage,
         maWindowSize: Int = 5,
         emaSmoothingFactor: Double = 0.3) {
        self.filterMode = filterMode
        self.maWindowSize = maWindowSize
        self.emaSmoothingFactor = emaSmoothingFactor
    }

    /// Feed a new pose and get filtered speed in m/s. Returns nil until two poses received.
    mutating func update(x: Float, z: Float, timestamp: TimeInterval) -> Double? {
        defer {
            lastX = x
            lastZ = z
            lastTimestamp = timestamp
        }

        guard let prevX = lastX, let prevZ = lastZ, let prevT = lastTimestamp else {
            return nil
        }

        let dt = timestamp - prevT
        guard dt > 1e-6 else { return nil } // avoid division by near-zero dt

        let dx = Double(x - prevX)
        let dz = Double(z - prevZ)
        let rawSpeed = sqrt(dx * dx + dz * dz) / dt

        switch filterMode {
        case .movingAverage:
            return applyMA(rawSpeed)
        case .exponentialMovingAverage:
            return applyEMA(rawSpeed)
        }
    }

    mutating func reset() {
        lastX = nil
        lastZ = nil
        lastTimestamp = nil
        maWindow.removeAll()
        emaValue = nil
    }

    // MARK: - Filters

    private mutating func applyMA(_ value: Double) -> Double {
        maWindow.append(value)
        if maWindow.count > maWindowSize { maWindow.removeFirst() }
        return maWindow.reduce(0, +) / Double(maWindow.count)
    }

    private mutating func applyEMA(_ value: Double) -> Double {
        guard let prev = emaValue else {
            emaValue = value
            return value
        }
        let filtered = emaSmoothingFactor * value + (1.0 - emaSmoothingFactor) * prev
        emaValue = filtered
        return filtered
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Util/ARKitVelocityEstimator.swift
git commit -m "feat: add ARKitVelocityEstimator with MA and EMA filters"
```

---

### Task 2: Publish ARKit Speed from ARKitPoseViewModel

**Files:**
- Modify: `Sources/Capture/ARKitPoseViewModel.swift`

Wire the estimator into the pose update callback so `arkitSpeedMps` is published on every frame.

- [ ] **Step 1: Add properties to ARKitPoseViewModel**

After the existing `@Published var forwardDepth: Float?` line (~line 59), add:

```swift
/// Ground-plane speed estimated from ARKit pose differentiation (m/s).
@Published var arkitSpeedMps: Double = 0
```

After the existing `private let freqWindowSize = 30` line (~line 94), add:

```swift
/// Velocity estimator — differentiates consecutive poses.
private var velocityEstimator = ARKitVelocityEstimator()
```

- [ ] **Step 2: Update the frame callback to compute speed**

In `session(_:didUpdate:)`, inside the `DispatchQueue.main.async` block, after `self.forwardDepth = centerDepth` (~line 473), add:

```swift
if let speed = self.velocityEstimator.update(x: robotX, z: robotZ, timestamp: timestamp) {
    self.arkitSpeedMps = speed
}
```

Note: `robotX`, `robotZ`, `timestamp` are already computed earlier in that method and are captured by the closure since they are local value types.

- [ ] **Step 3: Reset estimator on start**

In the `start()` method, inside the `DispatchQueue.main.async` block (after `self.isRelocalizing = false`, ~line 154), add:

```swift
self.velocityEstimator.reset()
self.arkitSpeedMps = 0
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Capture/ARKitPoseViewModel.swift
git commit -m "feat: publish ARKit-derived speed from pose differentiation"
```

---

### Task 3: Show ARKit Speed in ARKitPoseView

**Files:**
- Modify: `Sources/Views/ARKitPoseView.swift`

Add a speed readout to the data panel.

- [ ] **Step 1: Add speed display after the yaw line**

In `dataPanel(topPad:)`, after the yaw `Text` (~line 116), add:

```swift
Text(String(format: "Speed: %.2f m/s", viewModel.arkitSpeedMps))
    .font(.system(.subheadline, design: .monospaced))
    .foregroundColor(.green)
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Views/ARKitPoseView.swift
git commit -m "feat: show ARKit speed in pose test view"
```

---

### Task 4: Add Speed Fields to PlannerContext

**Files:**
- Modify: `Sources/Planner/PlannerContext.swift`

Add explicit speed fields so the safety supervisor and planner can use real velocity.

- [ ] **Step 1: Add speed fields**

Replace the entire file with:

```swift
import Foundation

/// Immutable sensor snapshot passed to the planner and safety supervisor each tick.
struct PlannerContext {
    /// Robot 6D pose in ARKit world frame.
    let pose: PoseEntry

    /// Last commanded throttle [-1, +1] (speed proxy until wheel calibration).
    let currentThrottle: Float

    /// ESC telemetry (nil if BLE not connected).
    let escTelemetry: ESCTelemetry?

    /// Center-pixel depth from LiDAR in meters (nil if depth unavailable).
    let forwardDepth: Float?

    /// Vehicle speed from motor RPM (nil if ESC not connected or RPM zero).
    let motorSpeedMps: Double?

    /// Vehicle speed from ARKit pose differentiation (nil if not yet available).
    let arkitSpeedMps: Double?

    /// Monotonic timestamp (seconds).
    let timestamp: TimeInterval

    /// Best available speed estimate: motor RPM preferred, ARKit fallback.
    /// Returns nil if neither source is available or both report zero.
    var bestSpeedMps: Double? {
        if let motor = motorSpeedMps, motor > 0.01 { return motor }
        if let arkit = arkitSpeedMps, arkit > 0.01 { return arkit }
        return nil
    }
}
```

- [ ] **Step 2: Update SelfDrivingViewModel to populate new fields**

In `SelfDrivingViewModel.swift`, update the `PlannerContext` construction in `runControlLoop()` (~line 123):

```swift
let motorSpeed: Double? = {
    guard let tel = escManager.telemetry, tel.speedMps > 0.01 else { return nil }
    return tel.speedMps
}()
let arkitSpeed: Double? = {
    let s = poseModel.arkitSpeedMps
    return s > 0.01 ? s : nil
}()

let context = PlannerContext(
    pose: pose,
    currentThrottle: throttle,
    escTelemetry: escManager.telemetry,
    forwardDepth: poseModel.forwardDepth,
    motorSpeedMps: motorSpeed,
    arkitSpeedMps: arkitSpeed,
    timestamp: pose.timestamp
)
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Planner/PlannerContext.swift Sources/Capture/SelfDrivingViewModel.swift
git commit -m "feat: add motorSpeedMps and arkitSpeedMps to PlannerContext"
```

---

### Task 5: Use Real Speed for TTC in SafetySupervisor

**Files:**
- Modify: `Sources/Planner/Safety/SafetySupervisor.swift`

Replace the hardcoded `assumedSpeedMPS = 2.0` with real speed from `PlannerContext.bestSpeedMps`.

- [ ] **Step 1: Remove assumed speed from config, update TTC computation**

Replace the entire file with:

```swift
import Foundation

// MARK: - Config

struct SafetySupervisorConfig {
    /// Fallback speed if no sensor data available (conservative estimate).
    var fallbackSpeedMPS: Float = 0.5
    /// Brake unconditionally when TTC falls below this threshold.
    var ttcCriticalS: Float = 1.0
    /// Avoid division by zero at standstill.
    var minSpeedEpsilonMPS: Float = 0.01
}

// MARK: - SafetySupervisor

/// Monitors forward depth and overrides planner commands when collision is imminent.
///
/// TTC uses real speed from motor RPM (primary) or ARKit (fallback).
/// If neither is available, falls back to a conservative fixed estimate.
final class SafetySupervisor {

    let config: SafetySupervisorConfig
    private(set) var lastEvent: SafetySupervisorEvent?

    init(config: SafetySupervisorConfig = .init()) {
        self.config = config
    }

    // MARK: - Public

    func supervise(command: ControlCommand, context: PlannerContext) -> ControlCommand {
        guard command.source != .safetySupervisor else { return command }
        guard command.throttle > 0 else { return passThrough(command, context: context) }
        guard let depth = validDepth(from: context) else { return command }

        let speed = resolveSpeed(context: context)
        let ttc = depth / speed
        let event = makeEvent(ttc: ttc, depth: depth, context: context)
        lastEvent = event

        if ttc < config.ttcCriticalS {
            let reason = String(format: "TTC %.2fs (d=%.2fm, v=%.2fm/s)", ttc, depth, speed)
            return .brake(reason: reason)
        }
        return command
    }

    func reset() {
        lastEvent = nil
    }

    // MARK: - Private Helpers

    private func passThrough(_ command: ControlCommand, context: PlannerContext) -> ControlCommand {
        if let depth = validDepth(from: context) {
            let speed = resolveSpeed(context: context)
            lastEvent = makeEvent(ttc: depth / speed, depth: depth, context: context)
        } else {
            lastEvent = nil
        }
        return command
    }

    private func validDepth(from context: PlannerContext) -> Float? {
        guard let d = context.forwardDepth, d > 0, d.isFinite else { return nil }
        return d
    }

    /// Motor RPM speed preferred, then ARKit, then conservative fallback.
    private func resolveSpeed(context: PlannerContext) -> Float {
        if let best = context.bestSpeedMps, best > Double(config.minSpeedEpsilonMPS) {
            return Float(best)
        }
        return max(config.fallbackSpeedMPS, config.minSpeedEpsilonMPS)
    }

    private func makeEvent(ttc: Float, depth: Float, context: PlannerContext) -> SafetySupervisorEvent {
        let action: SafetySupervisorEvent.Action = ttc < config.ttcCriticalS
            ? .brakeApplied(String(format: "TTC %.2fs (d=%.2fm)", ttc, depth))
            : .clear
        return SafetySupervisorEvent(timestamp: context.timestamp, ttc: ttc, forwardDepth: depth, action: action)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Planner/Safety/SafetySupervisor.swift
git commit -m "feat: use real speed (motor RPM / ARKit fallback) for TTC"
```

---

### Task 6: Constant Speed Planner with PI Controller

**Files:**
- Create: `Sources/Planner/Planners/ConstantSpeedPlanner.swift`
- Modify: `Sources/Planner/PlannerProtocol.swift`

- [ ] **Step 1: Add constantSpeed goal to PlannerGoal**

In `PlannerProtocol.swift`, add a new case to `PlannerGoal`:

```swift
enum PlannerGoal {
    case idle
    case followWaypoints([Waypoint], maxThrottle: Float)
    case constantSpeed(targetMps: Float)
}
```

- [ ] **Step 2: Handle the new case in WaypointPlanner**

In `WaypointPlanner.swift`, update `setGoal(_:)` to handle the new case:

```swift
func setGoal(_ goal: PlannerGoal) {
    reset()
    switch goal {
    case .idle: break
    case .followWaypoints(let wps, let throttle):
        waypoints = wps
        maxThrottle = throttle
    case .constantSpeed:
        break // Not handled by WaypointPlanner
    }
}
```

- [ ] **Step 3: Create ConstantSpeedPlanner**

```swift
// Sources/Planner/Planners/ConstantSpeedPlanner.swift
import Foundation

/// Drives forward at a constant target speed with neutral steering.
///
/// Uses a discrete PI controller to convert the speed error (target - measured)
/// into a throttle command. The integrator is clamped to prevent windup.
///
/// Speed source priority: motor RPM > ARKit > open-loop ramp.
final class ConstantSpeedPlanner: PlannerProtocol {

    let name = "ConstantSpeedPlanner"

    // MARK: - PI Gains

    /// Proportional gain: throttle fraction per (m/s) error.
    private let kP: Float = 1.0
    /// Integral gain: throttle fraction per (m/s * s) accumulated error.
    private let kI: Float = 0.3
    /// Anti-windup clamp for the integrator (throttle-seconds).
    private let integralLimit: Float = 0.5

    // MARK: - State

    private var targetMps: Float = 0
    private var integralError: Float = 0
    private var lastTimestamp: TimeInterval?
    private var isActive: Bool = false

    // MARK: - PlannerProtocol

    func setGoal(_ goal: PlannerGoal) {
        reset()
        switch goal {
        case .constantSpeed(let target):
            targetMps = target
            isActive = true
        case .idle, .followWaypoints:
            break
        }
    }

    func plan(context: PlannerContext) -> ControlCommand {
        guard isActive else { return .neutral }

        let dt = computeDt(timestamp: context.timestamp)
        let measuredSpeed = Float(context.bestSpeedMps ?? 0)
        let error = targetMps - measuredSpeed

        // Integrate with anti-windup clamp
        integralError += error * dt
        integralError = max(-integralLimit, min(integralLimit, integralError))

        let output = kP * error + kI * integralError
        // Clamp throttle to [-1, 1] range
        let throttle = max(-1.0, min(1.0, output))

        return ControlCommand(
            steering: 0, // neutral steering — drive straight
            throttle: throttle,
            source: .planner(name)
        )
    }

    func reset() {
        targetMps = 0
        integralError = 0
        lastTimestamp = nil
        isActive = false
    }

    // MARK: - Private

    private func computeDt(timestamp: TimeInterval) -> Float {
        defer { lastTimestamp = timestamp }
        guard let prev = lastTimestamp else { return 0 }
        let dt = timestamp - prev
        // Cap dt to avoid integral spikes after pauses
        return Float(min(dt, 0.1))
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Planner/PlannerProtocol.swift Sources/Planner/Planners/ConstantSpeedPlanner.swift Sources/Planner/Planners/WaypointPlanner.swift
git commit -m "feat: add ConstantSpeedPlanner with PI controller"
```

---

### Task 7: Wire ConstantSpeedPlanner into SelfDrivingViewModel

**Files:**
- Modify: `Sources/Capture/SelfDrivingViewModel.swift`

Switch the orchestrator to use `ConstantSpeedPlanner`, add a published `targetSpeedMps` property, and wire arm/disarm to the new goal.

- [ ] **Step 1: Replace WaypointPlanner with ConstantSpeedPlanner**

Replace the entire `SelfDrivingViewModel.swift` with:

```swift
import Foundation
import Combine
import SwiftUI

/// Orchestrates all subsystems for autonomous operation.
final class SelfDrivingViewModel: ObservableObject {

    // MARK: - Subsystems

    @Published var poseModel = ARKitPoseViewModel()
    @Published var escManager = ESCBleManager.shared
    @Published var stm32Manager = STM32BleManager.shared

    // MARK: - Planner

    let orchestrator = PlannerOrchestrator(planner: ConstantSpeedPlanner())

    /// Active waypoints for map overlay (empty for constant speed mode).
    @Published var waypoints: [Waypoint] = []

    /// Target speed for constant speed planner (m/s). Adjustable from UI.
    @Published var targetSpeedMps: Float = 0.2

    // MARK: - Speed Limits

    static let maxSpeedMps: Float = 0.5
    static let minSpeedMps: Float = -0.3

    // MARK: - State

    @Published var isStarted = false
    @Published var isAutonomous = false
    @Published var showMapManager = false

    // Manual/Auto overrides for UI feedback
    @Published var steering: Float = 0.0
    @Published var throttle: Float = 0.0

    // Control loop subscription — driven by ARKit pose updates, not a fixed timer.
    private var controlLoopSub: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupSubscriptions()
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }

        poseModel.start()
        escManager.start()
        stm32Manager.start()

        isStarted = true

        controlLoopSub = poseModel.$currentPose
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.runControlLoop()
            }
    }

    func stop() {
        isStarted = false
        isAutonomous = false

        controlLoopSub?.cancel()
        controlLoopSub = nil

        poseModel.stop()

        resetActuators()
    }

    func toggleAutonomous() {
        isAutonomous.toggle()
        if isAutonomous {
            orchestrator.setGoal(.constantSpeed(targetMps: targetSpeedMps))
        } else {
            orchestrator.reset()
            waypoints = []
            resetActuators()
        }
    }

    // MARK: - Control Loop

    private func runControlLoop() {
        guard isStarted && isAutonomous else { return }
        guard let pose = poseModel.currentPose else { return }

        let motorSpeed: Double? = {
            guard let tel = escManager.telemetry, tel.speedMps > 0.01 else { return nil }
            return tel.speedMps
        }()
        let arkitSpeed: Double? = {
            let s = poseModel.arkitSpeedMps
            return s > 0.01 ? s : nil
        }()

        let context = PlannerContext(
            pose: pose,
            currentThrottle: throttle,
            escTelemetry: escManager.telemetry,
            forwardDepth: poseModel.forwardDepth,
            motorSpeedMps: motorSpeed,
            arkitSpeedMps: arkitSpeed,
            timestamp: pose.timestamp
        )

        let command = orchestrator.tick(context: context)

        self.steering = command.steering
        self.throttle = command.throttle

        sendActuatorCommands(steering: command.steering, throttle: command.throttle)
    }

    // MARK: - Helpers

    private func setupSubscriptions() {
        poseModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        escManager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        stm32Manager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        orchestrator.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    private func sendActuatorCommands(steering: Float, throttle: Float) {
        let sPWM = toPulseWidth(steering)
        let tPWM = toPulseWidth(throttle)
        stm32Manager.sendCommand(steeringMicros: sPWM, throttleMicros: tPWM)
    }

    private func resetActuators() {
        steering = 0
        throttle = 0
        stm32Manager.sendCommand(steeringMicros: 1500, throttleMicros: 1500)
    }

    private func toPulseWidth(_ normalized: Float) -> Int16 {
        let clamped = max(-1.0, min(1.0, normalized))
        return Int16(1500.0 + clamped * 500.0)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Capture/SelfDrivingViewModel.swift
git commit -m "feat: wire ConstantSpeedPlanner and real speed into control loop"
```

---

### Task 8: Update SelfDrivingView UI

**Files:**
- Modify: `Sources/Views/SelfDrivingView.swift`

Show both motor and ARKit speed in telemetry, and add a speed target slider.

- [ ] **Step 1: Update the TELEMETRY section in bottomHUD**

Replace the existing telemetry VStack (the first VStack inside `bottomHUD`, ~lines 196-208) with:

```swift
// LEFT: Telemetry
VStack(alignment: .leading, spacing: 6) {
    Text("TELEMETRY")
        .font(.caption2.bold())
        .foregroundColor(.secondary)
    MetricRow(label: "Motor", value: String(format: "%.2f m/s", viewModel.escManager.telemetry?.speedMps ?? 0.0))
    MetricRow(label: "ARKit", value: String(format: "%.2f m/s", viewModel.poseModel.arkitSpeedMps))
    MetricRow(label: "RPM", value: "\(viewModel.escManager.telemetry?.rpm ?? 0)")
    MetricRow(label: "Voltage", value: String(format: "%.1f V", viewModel.escManager.telemetry?.voltage ?? 0.0))
    MetricRow(label: "Temp", value: String(format: "%.0f C", viewModel.escManager.telemetry?.escTemperature ?? 0.0))
}
.padding(12)
.frame(width: 150)
.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
```

- [ ] **Step 2: Add speed target slider between SAFETY and ARM button**

In `bottomHUD`, after the SAFETY VStack block and before `Spacer()` + ARM button, add:

```swift
// SPEED TARGET
VStack(alignment: .leading, spacing: 6) {
    Text("TARGET SPEED")
        .font(.caption2.bold())
        .foregroundColor(.secondary)
    Text(String(format: "%.2f m/s", viewModel.targetSpeedMps))
        .font(.caption.bold().monospacedDigit())
        .foregroundColor(.cyan)
    Slider(
        value: $viewModel.targetSpeedMps,
        in: SelfDrivingViewModel.minSpeedMps...SelfDrivingViewModel.maxSpeedMps,
        step: 0.05
    )
    .tint(.cyan)
    HStack {
        Text(String(format: "%.1f", SelfDrivingViewModel.minSpeedMps))
            .font(.caption2).foregroundColor(.secondary)
        Spacer()
        Text("0")
            .font(.caption2).foregroundColor(.secondary)
        Spacer()
        Text(String(format: "%.1f", SelfDrivingViewModel.maxSpeedMps))
            .font(.caption2).foregroundColor(.secondary)
    }
}
.padding(12)
.frame(width: 150)
.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/SelfDrivingView.swift
git commit -m "feat: show both speeds and target speed slider in self-driving HUD"
```

---

### Task 9: Final Integration & Build Verification

- [ ] **Step 1: Build the project**

```bash
cd openotter-ios && xcodebuild -scheme openotter-ios -destination 'platform=iOS,name=*' build 2>&1 | tail -20
```

Fix any compilation errors.

- [ ] **Step 2: Commit all fixes**

```bash
git add -A
git commit -m "feat(ios): ARKit velocity, real-speed TTC, constant speed planner v0.8.0"
```
