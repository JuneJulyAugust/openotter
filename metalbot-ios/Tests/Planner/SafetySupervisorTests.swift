import XCTest
@testable import metalbot

// MARK: - SafetySupervisorTests

final class SafetySupervisorTests: XCTestCase {

    /// Config with well-known values for deterministic testing.
    /// At speed 1.0 m/s with these settings:
    ///   brakeDistance = max(0.15, 1.0*0.8, 1.0²/(2*1.5)) = max(0.15, 0.80, 0.333) = 0.80 m
    ///   clearDistance = max(0.25, 1.0*1.5, 1.0²/(2*1.5)) = max(0.25, 1.50, 0.333) = 1.50 m
    private var config: SafetySupervisorConfig {
        var c = SafetySupervisorConfig()
        c.ttcBrakeS = 0.8
        c.ttcCautionS = 1.5
        c.minBrakeDistanceM = 0.15
        c.minCautionDistanceM = 0.25
        c.maxDecelerationMPS2 = 1.5
        c.fallbackSpeedMPS = 0.3
        c.minBrakeDurationS = 0.5
        c.minCautionDurationS = 0.3
        // Use alpha=1.0 to disable EMA filtering in most tests (raw depth passes through).
        c.depthEmaAlphaApproaching = 1.0
        c.depthEmaAlphaReceding = 1.0
        c.minSpeedEpsilonMPS = 0.01
        return c
    }

    private func makeSupervisor(config: SafetySupervisorConfig? = nil) -> SafetySupervisor {
        SafetySupervisor(config: config ?? self.config)
    }

    // MARK: - Passthrough Cases

    func testPassesThroughOwnCommands() {
        let sv = makeSupervisor()
        let brakeCmd = ControlCommand.brake(reason: "test")
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.1, arkitSpeedMps: 1.0)

        let result = sv.supervise(command: brakeCmd, context: ctx)
        XCTAssertEqual(result, brakeCmd, "Should not re-process safetySupervisor commands")
    }

    func testPassesThroughNegativeThrottle() {
        let sv = makeSupervisor()
        let reverseCmd = ControlCommand(steering: 0, throttle: -0.5, source: .planner("Test"))
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.1, arkitSpeedMps: 1.0)

        let result = sv.supervise(command: reverseCmd, context: ctx)
        XCTAssertEqual(result.throttle, -0.5, accuracy: 1e-5, "Reverse throttle should pass through")
    }

    func testPassesThroughZeroThrottle() {
        let sv = makeSupervisor()
        let neutralCmd = ControlCommand(steering: 0, throttle: 0, source: .planner("Test"))
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.1, arkitSpeedMps: 1.0)

        let result = sv.supervise(command: neutralCmd, context: ctx)
        XCTAssertEqual(result.throttle, 0, "Zero throttle should pass through")
    }

    func testPassesThroughWhenNoDepthData() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: nil, arkitSpeedMps: 1.0)

        let result = sv.supervise(command: cmd, context: ctx)
        XCTAssertEqual(result.throttle, 0.5, accuracy: 1e-5, "No depth → pass through")
    }

    func testPassesThroughWhenDepthIsNaN() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: Float.nan, arkitSpeedMps: 1.0)

        let result = sv.supervise(command: cmd, context: ctx)
        XCTAssertEqual(result.throttle, 0.5, accuracy: 1e-5, "NaN depth → pass through")
    }

    func testPassesThroughWhenDepthIsZero() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.0, arkitSpeedMps: 1.0)

        let result = sv.supervise(command: cmd, context: ctx)
        XCTAssertEqual(result.throttle, 0.5, accuracy: 1e-5, "Zero depth → invalid → pass through")
    }

    // MARK: - Tri-Zone Classification

    func testClearWhenDepthFarAboveClearDistance() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)
        // At fallback speed 0.3: clearDist = max(0.25, 0.3*1.5, 0.3²/(2*1.5)) = max(0.25, 0.45, 0.03) = 0.45
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 5.0)

        let result = sv.supervise(command: cmd, context: ctx)
        XCTAssertEqual(result.throttle, 0.5, accuracy: 1e-5, "Far depth should be CLEAR")
        XCTAssertEqual(sv.state, .clear)
    }

    func testBrakeWhenDepthBelowBrakeDistance() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)
        // At fallback speed 0.3: brakeDist = max(0.15, 0.3*0.8, 0.3²/(2*1.5)) = max(0.15, 0.24, 0.03) = 0.24
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.1)

        let result = sv.supervise(command: cmd, context: ctx)
        XCTAssertEqual(result.throttle, 0, accuracy: 1e-5, "Depth below brake dist → full stop")
        XCTAssertEqual(result.source, .safetySupervisor)
        if case .brake = sv.state {} else {
            XCTFail("Expected BRAKE state, got \(sv.state)")
        }
    }

    func testCautionWhenDepthBetweenBrakeAndClear() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)
        // At fallback speed 0.3: brakeDist=0.24, clearDist=0.45
        // Depth 0.35 is between them → CAUTION
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.35)

        let result = sv.supervise(command: cmd, context: ctx)
        XCTAssertLessThan(result.throttle, 0.5, "CAUTION should scale throttle down")
        XCTAssertGreaterThan(result.throttle, 0, "CAUTION should not fully stop")
        XCTAssertEqual(result.source, .safetySupervisor)
        if case .caution = sv.state {} else {
            XCTFail("Expected CAUTION state, got \(sv.state)")
        }
    }

    func testCautionThrottleScalesLinearly() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 1.0)
        // At fallback speed 0.3: brakeDist=0.24, clearDist=0.45
        // At exact midpoint 0.345: scale = (0.345-0.24)/(0.45-0.24) = 0.105/0.21 = 0.50
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.345)

        let result = sv.supervise(command: cmd, context: ctx)
        XCTAssertEqual(result.throttle, 0.5, accuracy: 0.05, "Midpoint of caution zone → ~50% throttle")
    }

    // MARK: - Latched Speed (Anti-Oscillation Invariant)

    func testLatchedSpeedPreventsThresholdShrinkage() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)

        // Tick 1: Moving at 1.0 m/s, depth 0.5m → below brakeDist (0.80m at 1.0 m/s) → BRAKE
        let ctx1 = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.5, arkitSpeedMps: 1.0)
        let r1 = sv.supervise(command: cmd, context: ctx1)
        XCTAssertEqual(r1.throttle, 0, accuracy: 1e-5, "Should brake at 0.5m with 1.0 m/s")

        // Tick 2: Speed has dropped to 0.1 m/s (because we braked), same depth.
        // Without latched speed, brakeDist would be max(0.15, 0.1*0.8, 0.01/3.0) = 0.15
        // → 0.5m > 0.15m → would release brake! That's the oscillation bug.
        // With latched speed (1.0), brakeDist stays at 0.80m → 0.5m < 0.80m → stays in BRAKE.
        let ctx2 = PlannerTestFactory.context(timestamp: 0.1, forwardDepth: 0.5, arkitSpeedMps: 0.1)
        let r2 = sv.supervise(command: cmd, context: ctx2)
        XCTAssertEqual(r2.throttle, 0, accuracy: 1e-5,
                       "Latched speed must prevent threshold shrinkage — stay in BRAKE")
    }

    func testLatchedSpeedClearsOnReturnToClear() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)

        // Enter BRAKE at speed 1.0
        let ctx1 = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.1, arkitSpeedMps: 1.0)
        _ = sv.supervise(command: cmd, context: ctx1)

        // Wait out cooldown, obstacle moves far away
        let ctx2 = PlannerTestFactory.context(timestamp: 0.6, forwardDepth: 10.0, arkitSpeedMps: 1.0)
        _ = sv.supervise(command: cmd, context: ctx2)  // BRAKE → CAUTION

        let ctx3 = PlannerTestFactory.context(timestamp: 1.0, forwardDepth: 10.0, arkitSpeedMps: 1.0)
        _ = sv.supervise(command: cmd, context: ctx3)  // CAUTION → CLEAR

        XCTAssertEqual(sv.state, .clear, "Should return to CLEAR with far depth and elapsed cooldowns")
    }

    // MARK: - Cooldown Timers

    func testBrakeCooldownPreventsImmediateRelease() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)

        // Enter BRAKE
        let ctx1 = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.1, arkitSpeedMps: 0.3)
        _ = sv.supervise(command: cmd, context: ctx1)
        XCTAssert(sv.state == .brake(since: 0))

        // Obstacle instantly removed (depth = 10m), but within cooldown (0.3s < 0.5s)
        let ctx2 = PlannerTestFactory.context(timestamp: 0.3, forwardDepth: 10.0, arkitSpeedMps: 0.3)
        _ = sv.supervise(command: cmd, context: ctx2)
        if case .brake = sv.state {} else {
            XCTFail("Should remain in BRAKE during cooldown, got \(sv.state)")
        }
    }

    func testBrakeTransitionsThroughCautionNeverDirectlyToClear() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)

        // Enter BRAKE
        let ctx1 = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.1, arkitSpeedMps: 0.3)
        _ = sv.supervise(command: cmd, context: ctx1)

        // Wait past brake cooldown (0.5s), depth far away → should transition to CAUTION, not CLEAR
        let ctx2 = PlannerTestFactory.context(timestamp: 0.6, forwardDepth: 10.0, arkitSpeedMps: 0.3)
        _ = sv.supervise(command: cmd, context: ctx2)
        if case .caution = sv.state {} else {
            XCTFail("BRAKE should transition to CAUTION (not CLEAR), got \(sv.state)")
        }
    }

    func testCautionCooldownPreventsImmediateClear() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)

        // Enter CAUTION directly
        // At fallback speed 0.3: brakeDist=0.24, clearDist=0.45
        let ctx1 = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.35)
        _ = sv.supervise(command: cmd, context: ctx1)
        if case .caution = sv.state {} else {
            XCTFail("Expected CAUTION state")
        }

        // Depth clears immediately (0.1s < 0.3s cooldown)
        let ctx2 = PlannerTestFactory.context(timestamp: 0.1, forwardDepth: 10.0)
        _ = sv.supervise(command: cmd, context: ctx2)
        if case .caution = sv.state {} else {
            XCTFail("Should remain in CAUTION during cooldown, got \(sv.state)")
        }
    }

    func testFullRecoverySequence_BrakeToCautionToClear() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)

        // t=0: BRAKE
        let ctx1 = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.1, arkitSpeedMps: 0.3)
        _ = sv.supervise(command: cmd, context: ctx1)
        if case .brake = sv.state {} else { XCTFail("Expected BRAKE") }

        // t=0.3: Still BRAKE (cooldown not met)
        let ctx2 = PlannerTestFactory.context(timestamp: 0.3, forwardDepth: 10.0, arkitSpeedMps: 0.3)
        _ = sv.supervise(command: cmd, context: ctx2)
        if case .brake = sv.state {} else { XCTFail("Expected BRAKE (cooldown)") }

        // t=0.6: BRAKE → CAUTION (brake cooldown met)
        let ctx3 = PlannerTestFactory.context(timestamp: 0.6, forwardDepth: 10.0, arkitSpeedMps: 0.3)
        _ = sv.supervise(command: cmd, context: ctx3)
        if case .caution = sv.state {} else { XCTFail("Expected CAUTION, got \(sv.state)") }

        // t=0.7: Still CAUTION (caution cooldown not met)
        let ctx4 = PlannerTestFactory.context(timestamp: 0.7, forwardDepth: 10.0, arkitSpeedMps: 0.3)
        _ = sv.supervise(command: cmd, context: ctx4)
        if case .caution = sv.state {} else { XCTFail("Expected CAUTION (cooldown), got \(sv.state)") }

        // t=1.0: CAUTION → CLEAR (caution cooldown met)
        let ctx5 = PlannerTestFactory.context(timestamp: 1.0, forwardDepth: 10.0, arkitSpeedMps: 0.3)
        _ = sv.supervise(command: cmd, context: ctx5)
        XCTAssertEqual(sv.state, .clear, "Should reach CLEAR after both cooldowns")
    }

    // MARK: - Re-engagement

    func testCautionEscalatesToBrakeIfDepthDrops() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)

        // Enter CAUTION (at fallback 0.3: brakeDist=0.24, clearDist=0.45, depth 0.35 is in CAUTION)
        let ctx1 = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.35)
        _ = sv.supervise(command: cmd, context: ctx1)
        if case .caution = sv.state {} else { XCTFail("Expected CAUTION") }

        // Depth drops below brake distance → escalate to BRAKE
        let ctx2 = PlannerTestFactory.context(timestamp: 0.1, forwardDepth: 0.1)
        let result = sv.supervise(command: cmd, context: ctx2)
        XCTAssertEqual(result.throttle, 0, accuracy: 1e-5, "Should escalate to BRAKE")
        if case .brake = sv.state {} else { XCTFail("Expected BRAKE, got \(sv.state)") }
    }

    // MARK: - Non-Forward Clears State

    func testNonForwardCommandClearsStateImmediately() {
        let sv = makeSupervisor()
        let fwd = PlannerTestFactory.forwardCommand(throttle: 0.5)
        let rev = ControlCommand(steering: 0, throttle: -0.5, source: .planner("Test"))

        // Enter BRAKE
        let ctx1 = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.1, arkitSpeedMps: 0.3)
        _ = sv.supervise(command: fwd, context: ctx1)
        if case .brake = sv.state {} else { XCTFail("Expected BRAKE") }

        // Send reverse command → should clear immediately (no cooldown)
        let ctx2 = PlannerTestFactory.context(timestamp: 0.1, forwardDepth: 0.1, arkitSpeedMps: 0.3)
        let result = sv.supervise(command: rev, context: ctx2)
        XCTAssertEqual(result.throttle, -0.5, accuracy: 1e-5)
        XCTAssertEqual(sv.state, .clear, "Non-forward command should clear state immediately")
    }

    // MARK: - Reset

    func testResetClearsAllState() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)

        // Enter BRAKE
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.1, arkitSpeedMps: 0.3)
        _ = sv.supervise(command: cmd, context: ctx)

        sv.reset()
        XCTAssertEqual(sv.state, .clear)
        XCTAssertNil(sv.lastEvent)
    }

    // MARK: - Event Reporting

    func testEventReportsClearAction() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)
        let ctx = PlannerTestFactory.context(timestamp: 1.0, forwardDepth: 10.0)

        _ = sv.supervise(command: cmd, context: ctx)
        let event = sv.lastEvent
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.action, .clear)
        XCTAssertEqual(event!.timestamp, 1.0, accuracy: 1e-5)
        XCTAssertEqual(event!.forwardDepth, 10.0, accuracy: 1e-5)
    }

    func testEventReportsBrakeAction() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)
        let ctx = PlannerTestFactory.context(timestamp: 1.0, forwardDepth: 0.1, arkitSpeedMps: 0.3)

        _ = sv.supervise(command: cmd, context: ctx)
        let event = sv.lastEvent
        XCTAssertNotNil(event)
        if case .brakeApplied = event?.action {} else {
            XCTFail("Expected brakeApplied action, got \(String(describing: event?.action))")
        }
    }

    func testEventReportsCautionWithThrottleScale() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 1.0)
        // At fallback speed 0.3: brakeDist=0.24, clearDist=0.45, midpoint=0.345 → scale≈0.5
        let ctx = PlannerTestFactory.context(timestamp: 1.0, forwardDepth: 0.345)

        _ = sv.supervise(command: cmd, context: ctx)
        let event = sv.lastEvent
        XCTAssertNotNil(event)
        if case .caution(let scale, _) = event?.action {
            XCTAssertEqual(scale, 0.5, accuracy: 0.1, "Should report throttle scale ≈ 0.5")
        } else {
            XCTFail("Expected caution action, got \(String(describing: event?.action))")
        }
    }

    // MARK: - Speed Resolution

    func testUsesMotorSpeedOverARKitSpeed() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)
        // Motor speed 2.0 → brakeDist = max(0.15, 2.0*0.8, 4.0/3.0) = max(0.15, 1.6, 1.333) = 1.6
        // Depth 1.0m < 1.6m → BRAKE
        let ctx = PlannerTestFactory.context(
            timestamp: 0, forwardDepth: 1.0,
            motorSpeedMps: 2.0, arkitSpeedMps: 0.5
        )

        let result = sv.supervise(command: cmd, context: ctx)
        XCTAssertEqual(result.throttle, 0, accuracy: 1e-5,
                       "Should use motor speed (2.0) for thresholds, causing brake at 1.0m")
    }

    func testFallsBackToFallbackSpeed() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)
        // No speed sensors → uses fallbackSpeedMPS (0.3)
        // brakeDist = max(0.15, 0.3*0.8, 0.09/3.0) = max(0.15, 0.24, 0.03) = 0.24
        // Depth 0.2m < 0.24m → BRAKE
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.2)

        let result = sv.supervise(command: cmd, context: ctx)
        XCTAssertEqual(result.throttle, 0, accuracy: 1e-5, "Should use fallback speed for thresholds")
    }

    // MARK: - Steering Passthrough

    func testSteeringIsPreservedInCaution() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5, steering: 0.7)
        // At fallback 0.3: CAUTION zone 0.24..0.45, depth=0.35
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.35)

        let result = sv.supervise(command: cmd, context: ctx)
        XCTAssertEqual(result.steering, 0.7, accuracy: 1e-5,
                       "CAUTION should preserve planner's steering output")
    }

    func testSteeringIsZeroInBrake() {
        let sv = makeSupervisor()
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5, steering: 0.7)
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.1) // BRAKE zone

        let result = sv.supervise(command: cmd, context: ctx)
        XCTAssertEqual(result.steering, 0, accuracy: 1e-5,
                       "BRAKE should zero out steering (ControlCommand.brake)")
    }
}

// MARK: - EMA Depth Filter Tests

final class SafetySupervisorEMATests: XCTestCase {

    /// Config with real EMA alphas (not 1.0).
    private var emaConfig: SafetySupervisorConfig {
        var c = SafetySupervisorConfig()
        c.depthEmaAlphaApproaching = 0.5
        c.depthEmaAlphaReceding = 0.3
        // Use very wide zones so we stay in CLEAR and can observe filtered depth.
        c.ttcBrakeS = 0.01
        c.ttcCautionS = 0.02
        c.minBrakeDistanceM = 0.01
        c.minCautionDistanceM = 0.02
        c.fallbackSpeedMPS = 0.3
        return c
    }

    func testFirstReadingPassesThroughUnfiltered() {
        let sv = SafetySupervisor(config: emaConfig)
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)
        let ctx = PlannerTestFactory.context(timestamp: 0, forwardDepth: 2.0)

        _ = sv.supervise(command: cmd, context: ctx)
        XCTAssertNotNil(sv.lastEvent)
        XCTAssertEqual(sv.lastEvent!.filteredDepth, 2.0, accuracy: 1e-5,
                       "First depth reading should pass through unfiltered")
    }

    func testApproachingObstacleUsesHigherAlpha() {
        let sv = SafetySupervisor(config: emaConfig)
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)

        // First reading: 2.0m
        _ = sv.supervise(command: cmd, context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 2.0))

        // Second reading: 1.0m (approaching) → alpha=0.5
        // filtered = 0.5 * 1.0 + 0.5 * 2.0 = 1.5
        _ = sv.supervise(command: cmd, context: PlannerTestFactory.context(timestamp: 0.1, forwardDepth: 1.0))
        XCTAssertEqual(sv.lastEvent?.filteredDepth ?? 0, 1.5, accuracy: 1e-4,
                       "Approaching should use alpha=0.5: 0.5*1.0 + 0.5*2.0 = 1.5")
    }

    func testRecedingObstacleUsesLowerAlpha() {
        let sv = SafetySupervisor(config: emaConfig)
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)

        // First reading: 1.0m
        _ = sv.supervise(command: cmd, context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 1.0))

        // Second reading: 2.0m (receding) → alpha=0.3
        // filtered = 0.3 * 2.0 + 0.7 * 1.0 = 0.6 + 0.7 = 1.3
        _ = sv.supervise(command: cmd, context: PlannerTestFactory.context(timestamp: 0.1, forwardDepth: 2.0))
        XCTAssertEqual(sv.lastEvent?.filteredDepth ?? 0, 1.3, accuracy: 1e-4,
                       "Receding should use alpha=0.3: 0.3*2.0 + 0.7*1.0 = 1.3")
    }

    func testNoiseSpikeSuppressedByEMA() {
        let sv = SafetySupervisor(config: emaConfig)
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)

        // Establish steady state at 3.0m (several readings)
        for i in 0..<10 {
            _ = sv.supervise(command: cmd, context: PlannerTestFactory.context(
                timestamp: Double(i) * 0.1, forwardDepth: 3.0
            ))
        }

        // Single spike down to 0.5m (noisy frame)
        _ = sv.supervise(command: cmd, context: PlannerTestFactory.context(
            timestamp: 1.0, forwardDepth: 0.5
        ))
        let filteredAfterSpike = sv.lastEvent?.filteredDepth ?? 0

        // With alpha=0.5 (approaching), filtered = 0.5*0.5 + 0.5*3.0 = 1.75
        // This is much higher than the raw 0.5, proving the filter suppresses the spike.
        XCTAssertGreaterThan(filteredAfterSpike, 1.0,
                             "EMA should suppress single noise spike from 3.0→0.5")
    }
}

// MARK: - Anti-Oscillation Integration Tests

final class SafetySupervisorOscillationTests: XCTestCase {

    /// Simulates the exact scenario that caused stop-go oscillation in the old design.
    /// The robot approaches a wall, brakes, speed drops, and we verify no oscillation.
    func testNoOscillationOnWallApproach() {
        var config = SafetySupervisorConfig()
        config.depthEmaAlphaApproaching = 1.0  // Disable EMA for clarity
        config.depthEmaAlphaReceding = 1.0
        config.ttcBrakeS = 1.5
        config.ttcCautionS = 2.5
        config.minBrakeDistanceM = 0.3
        config.minCautionDistanceM = 0.5
        config.maxDecelerationMPS2 = 0.5
        config.fallbackSpeedMPS = 0.3
        config.minBrakeDurationS = 0.5
        config.minCautionDurationS = 0.3
        let sv = SafetySupervisor(config: config)
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)

        // Wall at 0.2m, robot at 1.0 m/s
        // brakeDist = max(0.3, 1.5, 1.0) = 1.5m
        // 0.2m < 1.5m → BRAKE immediately

        var speed = 1.0
        let wallDepth: Float = 0.2
        var stateChanges = 0
        var lastWasBraking = false

        for i in 0..<100 {
            let t = Double(i) * 0.016  // ~60Hz
            let ctx = PlannerTestFactory.context(
                timestamp: t,
                forwardDepth: wallDepth,
                arkitSpeedMps: speed
            )
            let result = sv.supervise(command: cmd, context: ctx)

            let isBraking: Bool
            if case .brake = sv.state {
                isBraking = true
            } else {
                isBraking = false
            }

            if isBraking != lastWasBraking { stateChanges += 1 }
            lastWasBraking = isBraking

            // Simulate speed decay when braking
            if result.throttle == 0 {
                speed = max(0.01, speed * 0.9)
            } else {
                speed = min(1.0, speed + 0.05)
            }
        }

        // Should enter BRAKE once and never leave.
        // The old design would oscillate (stateChanges >> 1).
        XCTAssertEqual(stateChanges, 1,
                       "Should transition to BRAKE once and stay (had \(stateChanges) state changes)")
        if case .brake = sv.state {} else {
            XCTFail("Should remain in BRAKE state with wall at 0.2m, got \(sv.state)")
        }
    }

    /// Verify that after obstacle removal, recovery follows the correct sequence
    /// with no intermediate oscillation.
    func testSmoothRecoveryAfterObstacleRemoval() {
        var config = SafetySupervisorConfig()
        config.depthEmaAlphaApproaching = 1.0
        config.depthEmaAlphaReceding = 1.0
        config.minBrakeDurationS = 0.5
        config.minCautionDurationS = 0.3
        let sv = SafetySupervisor(config: config)
        let cmd = PlannerTestFactory.forwardCommand(throttle: 0.5)

        // Phase 1: Approach and brake (t=0..0.3)
        for i in 0..<20 {
            let t = Double(i) * 0.016
            let ctx = PlannerTestFactory.context(timestamp: t, forwardDepth: 0.1, arkitSpeedMps: 0.3)
            _ = sv.supervise(command: cmd, context: ctx)
        }
        if case .brake = sv.state {} else { XCTFail("Should be in BRAKE") }

        // Phase 2: Obstacle removed at t=0.5 (depth jumps to 10m)
        // Track all state transitions
        var stateSequence: [String] = []
        var lastStateName = "brake"

        for i in 0..<100 {
            let t = 0.5 + Double(i) * 0.016
            let ctx = PlannerTestFactory.context(timestamp: t, forwardDepth: 10.0, arkitSpeedMps: 0.3)
            _ = sv.supervise(command: cmd, context: ctx)

            let currentStateName: String
            switch sv.state {
            case .clear: currentStateName = "clear"
            case .caution: currentStateName = "caution"
            case .brake: currentStateName = "brake"
            }

            if currentStateName != lastStateName {
                stateSequence.append(currentStateName)
                lastStateName = currentStateName
            }
        }

        // Expected: brake → caution → clear (exactly two transitions, no bouncing)
        XCTAssertEqual(stateSequence, ["caution", "clear"],
                       "Recovery should follow brake→caution→clear, got: \(stateSequence)")
    }
}
