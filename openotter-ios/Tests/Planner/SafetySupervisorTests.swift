import XCTest
@testable import openotter

// MARK: - SafetySupervisorTests (v1.0 — time-to-brake policy)
//
// Deterministic config throughout: alphaSmoothing = 1.0 so rawDepth passes straight
// to smoothedDepth (no exponential moving average mixing). The temporal-smoothing
// behavior gets its own dedicated block at the bottom.
//
// Default policy values (see DESIGN.md §4):
//   tSysS = 0.1, decelIntercept = 2.0, decelSlope = 0.0, dMarginM = 0.1
// criticalDistance(v) = v·0.1 + v²/4 + 0.1  (decelSlope=0 → constant a=2.0)
//
// Worked values:
//   v = 0.3 → 0.03 + 0.0225 + 0.1 = 0.1525
//   v = 0.5 → 0.05 + 0.0625 + 0.1 = 0.2125
//   v = 1.0 → 0.10 + 0.2500 + 0.1 = 0.4500
//   v = 1.5 → 0.15 + 0.5625 + 0.1 = 0.8125
//   v = 2.0 → 0.20 + 1.0000 + 0.1 = 1.3000

final class SafetySupervisorTests: XCTestCase {

    private var defaultConfig: SafetySupervisorConfig {
        var c = SafetySupervisorConfig()
        c.tSysS = 0.1
        c.decelIntercept = 2.0
        c.decelSlope = 0.0
        c.dMarginM = 0.1
        c.alphaSmoothing = 1.0          // disable temporal smoothing by default
        c.releaseHoldS = 0.3
        c.fallbackSpeedMPS = 0.3
        c.stopSpeedEpsilonMPS = 0.05
        c.minSpeedEpsilonMPS = 0.01
        return c
    }

    private func makeSupervisor(config: SafetySupervisorConfig? = nil) -> SafetySupervisor {
        SafetySupervisor(config: config ?? defaultConfig)
    }

    private func forwardCmd(_ throttle: Float = 0.5) -> ControlCommand {
        PlannerTestFactory.forwardCommand(throttle: throttle)
    }

    // MARK: - Math

    func testCriticalDistanceMatchesFormula() {
        let sv = makeSupervisor()
        XCTAssertEqual(sv.criticalDistance(speed: 0.0), 0.1,   accuracy: 1e-6)
        XCTAssertEqual(sv.criticalDistance(speed: 0.3), 0.1525, accuracy: 1e-5)
        XCTAssertEqual(sv.criticalDistance(speed: 1.0), 0.45,  accuracy: 1e-5)
        XCTAssertEqual(sv.criticalDistance(speed: 2.0), 1.30,  accuracy: 1e-5)
    }

    // MARK: - Passthrough

    func testPassesThroughOwnBrakeCommands() {
        let sv = makeSupervisor()
        let brakeCmd = ControlCommand.brake(reason: "test")
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.1, arkitSpeedMps: 1.0)
        XCTAssertEqual(sv.supervise(command: brakeCmd, context: ctx), brakeCmd)
    }

    func testPassesThroughReverseCommand() {
        let sv = makeSupervisor()
        let reverseCmd = ControlCommand(steering: 0, throttle: -0.5, source: .planner("Test"))
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.01, arkitSpeedMps: 1.0)
        let result = sv.supervise(command: reverseCmd, context: ctx)
        XCTAssertEqual(result.throttle, -0.5, accuracy: 1e-6, "Reverse always passes through")
    }

    func testPassesThroughZeroThrottle() {
        let sv = makeSupervisor()
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.01, arkitSpeedMps: 1.0)
        let result = sv.supervise(
            command: ControlCommand(steering: 0, throttle: 0, source: .planner("Test")),
            context: ctx
        )
        XCTAssertEqual(result.throttle, 0)
    }

    func testPassesThroughWhenDepthMissing() {
        let sv = makeSupervisor()
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: nil, arkitSpeedMps: 1.0)
        let result = sv.supervise(command: forwardCmd(), context: ctx)
        XCTAssertEqual(result.throttle, 0.5, accuracy: 1e-6)
    }

    func testPassesThroughWhenDepthIsNaN() {
        let sv = makeSupervisor()
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: .nan, arkitSpeedMps: 1.0)
        let result = sv.supervise(command: forwardCmd(), context: ctx)
        XCTAssertEqual(result.throttle, 0.5, accuracy: 1e-6)
    }

    func testPassesThroughWhenDepthIsZeroOrNegative() {
        let sv = makeSupervisor()
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.0, arkitSpeedMps: 1.0)
        XCTAssertEqual(sv.supervise(command: forwardCmd(), context: ctx).throttle, 0.5, accuracy: 1e-6)
    }

    // MARK: - Binary SAFE / BRAKE classification

    func testSafeWhenDepthFarAboveCritical() {
        let sv = makeSupervisor()
        // v = 1.0 → criticalDistance = 0.45. Depth 5.0 m is far above.
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 5.0, arkitSpeedMps: 1.0)
        let result = sv.supervise(command: forwardCmd(), context: ctx)
        XCTAssertEqual(result.throttle, 0.5, accuracy: 1e-6)
        XCTAssertEqual(sv.state, .safe)
    }

    func testBrakeWhenDepthAtOrBelowCritical() {
        let sv = makeSupervisor()
        // v = 1.0 → criticalDistance = 0.45. Depth 0.44 m is just under.
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.44, arkitSpeedMps: 1.0)
        let result = sv.supervise(command: forwardCmd(), context: ctx)
        XCTAssertEqual(result.throttle, 0, accuracy: 1e-6)
        XCTAssertEqual(result.source, .safetySupervisor)
        if case .brake = sv.state {} else {
            XCTFail("Expected BRAKE, got \(sv.state)")
        }
    }

    func testBrakeTriggersWhenDepthEqualsCritical() {
        let sv = makeSupervisor()
        // Boundary: depth == criticalDistance → BRAKE (uses ≤).
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.45, arkitSpeedMps: 1.0)
        let result = sv.supervise(command: forwardCmd(), context: ctx)
        XCTAssertEqual(result.throttle, 0)
        if case .brake = sv.state {} else { XCTFail("Boundary depth → BRAKE") }
    }

    // MARK: - Latched-speed invariant (anti-oscillation)

    func testLatchedSpeedKeepsBrakeDespiteSlowdown() {
        let sv = makeSupervisor()

        // Tick 1: moving at 1.0 m/s, depth 0.40 m < 0.45 → BRAKE, latch = 1.0.
        let ctx1 = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.40, arkitSpeedMps: 1.0)
        XCTAssertEqual(sv.supervise(command: forwardCmd(), context: ctx1).throttle, 0)

        // Tick 2: robot has slowed to 0.1 m/s (brake worked). Same depth.
        // WITHOUT latch: criticalDistance(0.1) = 0.11 → 0.40 > 0.11 → release. BUG.
        // WITH latch: criticalDistance(1.0) = 0.45 → 0.40 < 0.45 → stay in BRAKE.
        let ctx2 = PlannerTestFactory.context(timestamp: 0.05, forwardDepth: 0.40, arkitSpeedMps: 0.1)
        XCTAssertEqual(sv.supervise(command: forwardCmd(), context: ctx2).throttle, 0)
    }

    func testLatchedSpeedPersistsUntilRelease() {
        let sv = makeSupervisor()

        // Engage at 1.5 m/s, depth 0.70 m < 0.8125 → BRAKE, latch = 1.5.
        let ctx1 = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.70, arkitSpeedMps: 1.5)
        _ = sv.supervise(command: forwardCmd(), context: ctx1)

        // Depth of 0.75 m — still below criticalDistance(1.5) = 0.8125. Stay BRAKE.
        let ctx2 = PlannerTestFactory.context(timestamp: 0.1, forwardDepth: 0.75, arkitSpeedMps: 0.0)
        XCTAssertEqual(sv.supervise(command: forwardCmd(), context: ctx2).throttle, 0)
    }

    // MARK: - Release via genuine clearance

    func testReleaseRequiresContinuousClearanceHold() {
        let sv = makeSupervisor()

        // Engage at 1.0 m/s.
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.30, arkitSpeedMps: 1.0)
        )

        // Depth jumps above criticalDistance(1.0) = 0.45 but hold time < releaseHoldS.
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.1, forwardDepth: 1.0, arkitSpeedMps: 0.5)
        )
        if case .brake = sv.state {} else { XCTFail("Should still be BRAKE during hold window") }

        // Now exceed releaseHoldS (0.3 s since clearance started).
        let released = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.5, forwardDepth: 1.0, arkitSpeedMps: 0.5)
        )
        XCTAssertEqual(sv.state, .safe)
        XCTAssertEqual(released.throttle, 0.5, accuracy: 1e-6)
    }

    func testReleaseTimerResetsOnDepthDip() {
        let sv = makeSupervisor()

        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.30, arkitSpeedMps: 1.0)
        )

        // Depth above threshold briefly.
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.1, forwardDepth: 1.0, arkitSpeedMps: 0.3)
        )
        // Depth dips back below → timer must reset.
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.15, forwardDepth: 0.30, arkitSpeedMps: 0.0)
        )
        // Back above, but only 0.15 s elapsed since new clearance → still BRAKE.
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.30, forwardDepth: 1.0, arkitSpeedMps: 0.0)
        )
        if case .brake = sv.state {} else {
            XCTFail("Timer must reset on dip; supervisor must still be BRAKE")
        }
    }

    // MARK: - Release via operator intervention

    func testOperatorReverseReleasesLatchImmediately() {
        let sv = makeSupervisor()

        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.30, arkitSpeedMps: 1.0)
        )
        if case .brake = sv.state {} else { XCTFail("Expected BRAKE") }

        // Operator commands reverse — even with obstacle still close.
        let reverseCmd = ControlCommand(steering: 0, throttle: -0.4, source: .planner("Op"))
        let out = sv.supervise(command: reverseCmd, context:
            PlannerTestFactory.context(timestamp: 0.05, forwardDepth: 0.30, arkitSpeedMps: 0.0)
        )
        XCTAssertEqual(out.throttle, -0.4, accuracy: 1e-6)
        XCTAssertEqual(sv.state, .safe)
    }

    // MARK: - Trigger & stop snapshots

    func testTriggerSnapshotCapturesFieldsAtEngagement() {
        let sv = makeSupervisor()
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(
                timestamp: 1.5, forwardDepth: 0.35,
                motorSpeedMps: 0.9, arkitSpeedMps: 1.0
            )
        )
        guard let record = sv.currentBrake else {
            XCTFail("BrakeRecord should exist")
            return
        }
        XCTAssertEqual(record.trigger.timestamp, 1.5, accuracy: 1e-6)
        XCTAssertEqual(record.trigger.depth, 0.35, accuracy: 1e-5)
        XCTAssertEqual(record.trigger.speed, 0.9, accuracy: 1e-5, "Motor speed preferred")
        XCTAssertEqual(record.trigger.criticalDistance, 0.9 * 0.1 + 0.81 / 4 + 0.1, accuracy: 1e-4)
        XCTAssertEqual(record.trigger.motorSpeed, 0.9, accuracy: 1e-5)
        XCTAssertEqual(record.trigger.arkitSpeed, 1.0, accuracy: 1e-5)
        XCTAssertNil(record.stop)
    }

    func testStopSnapshotCapturedOnFirstZeroSpeedFrame() {
        let sv = makeSupervisor()
        // Trigger at 1.0 m/s, pose at (0,0).
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.30, arkitSpeedMps: 1.0)
        )
        // Slow but not stopped.
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.1, forwardDepth: 0.25, arkitSpeedMps: 0.2)
        )
        XCTAssertNil(sv.currentBrake?.stop, "Not stopped yet")

        // Robot is now at rest, pose shifted forward by 0.05 m.
        let stopPose = PoseEntry(timestamp: 0.3, x: 0.05, y: 0, z: 0, yaw: 0, confidence: 1.0)
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(
                timestamp: 0.3, forwardDepth: 0.20, arkitSpeedMps: 0.0, pose: stopPose
            )
        )
        guard let stop = sv.currentBrake?.stop else {
            XCTFail("Stop snapshot should be captured")
            return
        }
        XCTAssertEqual(stop.timestamp, 0.3, accuracy: 1e-6)
        XCTAssertEqual(stop.depth, 0.20, accuracy: 1e-5)
        XCTAssertEqual(sv.currentBrake?.stoppingDistanceM ?? -1, 0.05, accuracy: 1e-5)
        XCTAssertEqual(sv.currentBrake?.stoppingTimeS ?? -1, 0.3, accuracy: 1e-6)
        // actualDecel = latchedSpeed / stoppingTime = 1.0 / 0.3 ≈ 3.33
        XCTAssertEqual(sv.currentBrake?.actualDecelMPS2 ?? -1, 1.0 / 0.3, accuracy: 1e-4)
        XCTAssertEqual(sv.currentBrake?.brakingDistanceM ?? -1, 0.30 - 0.20, accuracy: 1e-5)
    }

    func testStopSnapshotOnlyCapturedOnce() {
        let sv = makeSupervisor()
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.30, arkitSpeedMps: 1.0)
        )
        // Two ticks with speed below epsilon — second one must not overwrite.
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.1, forwardDepth: 0.25, arkitSpeedMps: 0.0)
        )
        let firstStopT = sv.currentBrake?.stop?.timestamp
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.2, forwardDepth: 0.20, arkitSpeedMps: 0.0)
        )
        XCTAssertEqual(sv.currentBrake?.stop?.timestamp, firstStopT)
    }

    func testBrakeRecordClearsOnRelease() {
        let sv = makeSupervisor()
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.30, arkitSpeedMps: 1.0)
        )
        XCTAssertNotNil(sv.currentBrake)

        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.1, forwardDepth: 2.0, arkitSpeedMps: 0.3)
        )
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.5, forwardDepth: 2.0, arkitSpeedMps: 0.3)
        )
        XCTAssertEqual(sv.state, .safe)
        XCTAssertNil(sv.currentBrake)
    }

    // MARK: - Event diagnostics

    func testLastEventReportsCurrentCriticalDistance() {
        let sv = makeSupervisor()
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 2.0, arkitSpeedMps: 1.0)
        _ = sv.supervise(command: forwardCmd(), context: ctx)
        guard let e = sv.lastEvent else { XCTFail("lastEvent missing"); return }
        XCTAssertFalse(e.isBraking)
        XCTAssertEqual(e.speed, 1.0, accuracy: 1e-5)
        XCTAssertEqual(e.criticalDistance, 0.45, accuracy: 1e-5)
        XCTAssertEqual(e.smoothedDepth, 2.0, accuracy: 1e-5)
    }

    func testLastEventDuringBrakeReportsLatchedSpeed() {
        let sv = makeSupervisor()
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.30, arkitSpeedMps: 1.0)
        )
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.05, forwardDepth: 0.30, arkitSpeedMps: 0.1)
        )
        guard let e = sv.lastEvent else { XCTFail("lastEvent missing"); return }
        XCTAssertTrue(e.isBraking)
        XCTAssertEqual(e.speed, 1.0, accuracy: 1e-5, "Latched speed reported, not current 0.1")
        XCTAssertEqual(e.criticalDistance, 0.45, accuracy: 1e-5)
    }

    // MARK: - Reset

    func testResetReturnsToSafeAndClearsState() {
        let sv = makeSupervisor()
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.30, arkitSpeedMps: 1.0)
        )
        XCTAssertNotNil(sv.currentBrake)
        sv.reset()
        XCTAssertEqual(sv.state, .safe)
        XCTAssertNil(sv.currentBrake)
        XCTAssertNil(sv.lastEvent)
    }

    // MARK: - Exponential Moving Average smoothing

    func testExponentialMovingAverageInitializesOnFirstReading() {
        var cfg = defaultConfig
        cfg.alphaSmoothing = 0.5
        let sv = makeSupervisor(config: cfg)
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0, forwardDepth: 2.0, arkitSpeedMps: 1.0)
        )
        XCTAssertEqual(sv.lastEvent?.smoothedDepth ?? -1, 2.0, accuracy: 1e-5)
    }

    func testExponentialMovingAverageConvergesGeometrically() {
        var cfg = defaultConfig
        cfg.alphaSmoothing = 0.5
        let sv = makeSupervisor(config: cfg)
        // Prime with 2.0.
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0, forwardDepth: 2.0, arkitSpeedMps: 1.0)
        )
        // New reading 0.50 → smoothed = 0.5·0.50 + 0.5·2.0 = 1.25.
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.05, forwardDepth: 0.50, arkitSpeedMps: 1.0)
        )
        XCTAssertEqual(sv.lastEvent?.smoothedDepth ?? -1, 1.25, accuracy: 1e-5)
        // Again 0.50 → 0.875.
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.1, forwardDepth: 0.50, arkitSpeedMps: 1.0)
        )
        XCTAssertEqual(sv.lastEvent?.smoothedDepth ?? -1, 0.875, accuracy: 1e-5)
    }

    func testSmoothingDelaysBrakeUntilAverageCrossesThreshold() {
        var cfg = defaultConfig
        cfg.alphaSmoothing = 0.5
        let sv = makeSupervisor(config: cfg)
        // Prime far away.
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0, forwardDepth: 2.0, arkitSpeedMps: 1.0)
        )
        // Sudden close reading — smoothed only drops to 1.25, above criticalDistance(1.0) = 0.45 → SAFE.
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.03, forwardDepth: 0.20, arkitSpeedMps: 1.0)
        )
        XCTAssertEqual(sv.state, .safe, "Single noisy dip must not trigger brake under smoothing")
        // Sustained close readings — by third frame smoothed ≈ 0.40 < 0.45 → BRAKE.
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.06, forwardDepth: 0.20, arkitSpeedMps: 1.0)
        )
        _ = sv.supervise(command: forwardCmd(), context:
            PlannerTestFactory.context(timestamp: 0.09, forwardDepth: 0.20, arkitSpeedMps: 1.0)
        )
        if case .brake = sv.state {} else {
            XCTFail("Sustained close readings should eventually trigger BRAKE")
        }
    }

    // MARK: - Fallback speed

    func testUsesFallbackSpeedWhenNoSensorSpeedAvailable() {
        let sv = makeSupervisor()
        // No motor, no ARKit speed → fallbackSpeedMPS = 0.3 → criticalDistance ≈ 0.1525.
        // Depth 0.14 m < 0.1525 → BRAKE.
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.14)
        let result = sv.supervise(command: forwardCmd(), context: ctx)
        XCTAssertEqual(result.throttle, 0)
    }

    func testPrefersMotorSpeedOverArkitSpeed() {
        let sv = makeSupervisor()
        // Motor 0.3 (criticalDistance 0.1525), ARKit 2.0 (criticalDistance 1.3).
        // Depth 0.6: under motor-only config SAFE, under ARKit-only config BRAKE.
        // Expect SAFE, proving motor wins.
        let ctx = PlannerTestFactory.context(
            timestamp: 0, forwardDepth: 0.6,
            motorSpeedMps: 0.3, arkitSpeedMps: 2.0
        )
        _ = sv.supervise(command: forwardCmd(), context: ctx)
        XCTAssertEqual(sv.state, .safe)
    }
}
