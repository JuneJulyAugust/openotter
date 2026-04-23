import XCTest
@testable import openotter

// MARK: - PlannerOrchestratorTests
//
// Exercises the orchestrator's wiring between the active planner and the
// time-to-brake safety supervisor (v1.0). The supervisor's internal math is
// tested in SafetySupervisorTests; here we only verify the orchestrator
// correctly forwards state, events, and records.

final class PlannerOrchestratorTests: XCTestCase {

    // MARK: - Planner ↔ Supervisor Wiring

    func testPlannerOutputFlowsThroughSupervisor() {
        let planner = ConstantSpeedPlanner()
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        // Far depth → SAFE → planner output passes through.
        let ctx = PlannerTestFactory.context(timestamp: 1.0, forwardDepth: 10.0, arkitSpeedMps: 0.3)
        let cmd = orchestrator.tick(context: ctx)

        // First tick output is 0 (ramp starts from zero).
        XCTAssertEqual(cmd.throttle, 0, accuracy: 1e-5, "First tick should be 0 (ramp initialization)")
        XCTAssertEqual(cmd.source, .planner("ConstantThrottlePlanner"))
    }

    func testSupervisorOverridesBrakesPlanner() {
        let planner = ConstantSpeedPlanner(config: .init(maxRampRatePerSecond: 10.0))
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        // Warm up ramp with open road.
        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 10.0, arkitSpeedMps: 1.0))
        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0.5, forwardDepth: 10.0, arkitSpeedMps: 1.0))

        // Drive smoothed depth below criticalDistance(1.0) = 0.45. Sustained close readings
        // at alphaSmoothing = 0.5 converge geometrically; ~15 ticks is plenty.
        var cmd = ControlCommand.neutral
        for i in 1...15 {
            let t = 0.5 + Double(i) * 0.016
            cmd = orchestrator.tick(context: PlannerTestFactory.context(
                timestamp: t, forwardDepth: 0.1, arkitSpeedMps: 1.0
            ))
        }

        XCTAssertEqual(cmd.throttle, 0, accuracy: 1e-5, "Supervisor should override to brake")
        XCTAssertEqual(cmd.source, .safetySupervisor)
    }

    // MARK: - isOverridden Semantics

    func testIsOverriddenTrueForBrake() {
        let planner = ConstantSpeedPlanner(config: .init(maxRampRatePerSecond: 10.0))
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 10.0, arkitSpeedMps: 1.0))
        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0.5, forwardDepth: 10.0, arkitSpeedMps: 1.0))

        for i in 1...15 {
            let t = 0.5 + Double(i) * 0.016
            _ = orchestrator.tick(context: PlannerTestFactory.context(
                timestamp: t, forwardDepth: 0.1, arkitSpeedMps: 1.0
            ))
        }
        XCTAssertTrue(orchestrator.isOverridden, "isOverridden should be true in BRAKE")
    }

    func testIsOverriddenFalseForSafe() {
        let planner = ConstantSpeedPlanner()
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        let ctx = PlannerTestFactory.context(timestamp: 1.0, forwardDepth: 10.0)
        _ = orchestrator.tick(context: ctx)
        XCTAssertFalse(orchestrator.isOverridden)
    }

    // MARK: - Supervisor State Exposure

    func testSupervisorStateIsExposed() {
        let planner = ConstantSpeedPlanner(config: .init(maxRampRatePerSecond: 10.0))
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 10.0, arkitSpeedMps: 1.0))
        XCTAssertEqual(orchestrator.supervisorState, .safe)

        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0.5, forwardDepth: 10.0, arkitSpeedMps: 1.0))
        for i in 1...15 {
            let t = 0.5 + Double(i) * 0.016
            _ = orchestrator.tick(context: PlannerTestFactory.context(
                timestamp: t, forwardDepth: 0.1, arkitSpeedMps: 1.0
            ))
        }
        if case .brake = orchestrator.supervisorState {} else {
            XCTFail("Expected BRAKE state, got \(orchestrator.supervisorState)")
        }
    }

    // MARK: - Event & Record Reporting

    func testLastSupervisorEventIsUpdated() {
        let planner = ConstantSpeedPlanner()
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        let ctx = PlannerTestFactory.context(timestamp: 1.0, forwardDepth: 5.0)
        _ = orchestrator.tick(context: ctx)

        XCTAssertNotNil(orchestrator.lastSupervisorEvent)
        XCTAssertEqual(orchestrator.lastSupervisorEvent!.timestamp, 1.0, accuracy: 1e-5)
    }

    func testBrakeRecordExposedDuringBrake() {
        let planner = ConstantSpeedPlanner(config: .init(maxRampRatePerSecond: 10.0))
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 10.0, arkitSpeedMps: 1.0))
        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0.5, forwardDepth: 10.0, arkitSpeedMps: 1.0))
        for i in 1...15 {
            let t = 0.5 + Double(i) * 0.016
            _ = orchestrator.tick(context: PlannerTestFactory.context(
                timestamp: t, forwardDepth: 0.1, arkitSpeedMps: 1.0
            ))
        }
        XCTAssertNotNil(orchestrator.brakeRecord, "brakeRecord should be exposed while BRAKE")
    }

    // MARK: - Reset

    func testResetClearsAllState() {
        let planner = ConstantSpeedPlanner()
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.1))

        orchestrator.reset()
        XCTAssertEqual(orchestrator.lastCommand, .neutral)
        XCTAssertNil(orchestrator.lastSupervisorEvent)
        XCTAssertFalse(orchestrator.isOverridden)
        XCTAssertEqual(orchestrator.supervisorState, .safe)
        XCTAssertNil(orchestrator.brakeRecord)
    }

    // MARK: - Planner Swap

    func testSwapPlannerResetsPrevious() {
        let planner1 = ConstantSpeedPlanner()
        let orchestrator = PlannerOrchestrator(planner: planner1)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 10.0))

        let planner2 = ConstantSpeedPlanner()
        orchestrator.swapPlanner(planner2)

        XCTAssertTrue(orchestrator.activePlanner === planner2)

        let cmd = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 1.0, forwardDepth: 10.0))
        XCTAssertEqual(cmd, .neutral, "Swapped planner with no goal should produce neutral")
    }

    // MARK: - Goal Passthrough

    func testGoalPassthroughToPlanner() {
        let planner = ConstantSpeedPlanner()
        let orchestrator = PlannerOrchestrator(planner: planner)

        let cmd1 = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 10.0))
        XCTAssertEqual(cmd1, .neutral)

        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.3))
        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 1.0, forwardDepth: 10.0))
        let cmd2 = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 1.1, forwardDepth: 10.0))
        XCTAssertGreaterThan(cmd2.throttle, 0, "After goal set and ramp, throttle should be positive")
    }
}

// MARK: - Integration: Full Pipeline Tests

final class PlannerPipelineIntegrationTests: XCTestCase {

    /// Full mission: open road → wall → brake → wall removed → resume.
    /// Expected transitions under the v1.0 policy: safe → brake → safe.
    func testFullMissionWithWallEncounter() {
        let planner = ConstantSpeedPlanner(config: .init(maxRampRatePerSecond: 2.0))
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.3))

        let dt = 1.0 / 60.0
        var speed = 0.0

        // Phase 1 (0..1 s): open road, ramp up.
        for i in 0..<60 {
            let t = Double(i) * dt
            let cmd = orchestrator.tick(context: PlannerTestFactory.context(
                timestamp: t, forwardDepth: 10.0, arkitSpeedMps: speed
            ))
            speed = max(0, Double(cmd.throttle))
        }
        XCTAssertGreaterThan(speed, 0.1, "Should be driving after 1 s ramp")

        // Phase 2 (1..2 s): wall at 0.1 m appears.
        var brakeEngaged = false
        for i in 0..<60 {
            let t = 1.0 + Double(i) * dt
            let cmd = orchestrator.tick(context: PlannerTestFactory.context(
                timestamp: t, forwardDepth: 0.1, arkitSpeedMps: speed
            ))
            if cmd.throttle == 0 && cmd.source == .safetySupervisor && !brakeEngaged {
                brakeEngaged = true
            }
            speed = max(0, Double(cmd.throttle))
        }
        XCTAssertTrue(brakeEngaged, "Brake should have engaged when wall appeared")
        XCTAssertTrue(orchestrator.isOverridden, "Should be overridden at end of wall phase")

        // Phase 3 (2..4 s): wall removed, expect release after releaseHoldS.
        var transitions: [String] = []
        var lastName = "brake"
        for i in 0..<120 {
            let t = 2.0 + Double(i) * dt
            let cmd = orchestrator.tick(context: PlannerTestFactory.context(
                timestamp: t, forwardDepth: 10.0, arkitSpeedMps: speed
            ))
            speed = max(0, Double(cmd.throttle))

            let name: String
            switch orchestrator.supervisorState {
            case .safe:  name = "safe"
            case .brake: name = "brake"
            }
            if name != lastName {
                transitions.append(name)
                lastName = name
            }
        }

        XCTAssertEqual(transitions, ["safe"],
                       "Recovery should be brake→safe, got: \(transitions)")
        XCTAssertFalse(orchestrator.isOverridden, "Should not be overridden after recovery")
    }

    /// Obstacle sits at a depth strictly greater than `criticalDistance(v)` under the
    /// chosen goal speed. The supervisor should never trigger BRAKE.
    ///
    /// With defaults (tSysS=0.1, decelIntercept=0.66, decelSlope=0.87, dMarginM=0.2)
    /// and fallback speed 0.3 m/s, criticalDistance ≈ 0.26 m. Depth 0.40 m is
    /// comfortably above. No triggers expected.
    func testSupervisorDoesNotTriggerWhenAlwaysAboveCriticalDistance() {
        let planner = ConstantSpeedPlanner(config: .init(maxRampRatePerSecond: 0.3))
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.3))

        let dt = 1.0 / 60.0

        for i in 0..<60 {
            _ = orchestrator.tick(context: PlannerTestFactory.context(
                timestamp: Double(i) * dt, forwardDepth: 10.0, arkitSpeedMps: 0.3
            ))
        }

        var brakeCount = 0
        var lastWasBrake = false
        for i in 0..<300 {
            let t = 1.0 + Double(i) * dt
            let cmd = orchestrator.tick(context: PlannerTestFactory.context(
                timestamp: t, forwardDepth: 0.40, arkitSpeedMps: 0.3
            ))
            let isBrake = cmd.throttle == 0 && cmd.source == .safetySupervisor
            if isBrake && !lastWasBrake { brakeCount += 1 }
            lastWasBrake = isBrake
        }

        XCTAssertEqual(brakeCount, 0,
                       "Depth comfortably above criticalDistance should never trigger BRAKE (triggered \(brakeCount) times)")
    }
}
