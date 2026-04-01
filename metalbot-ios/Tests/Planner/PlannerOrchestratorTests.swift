import XCTest
@testable import metalbot

// MARK: - PlannerOrchestratorTests

final class PlannerOrchestratorTests: XCTestCase {

    // MARK: - Planner ↔ Supervisor Wiring

    func testPlannerOutputFlowsThroughSupervisor() {
        let planner = ConstantSpeedPlanner()
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        // Far depth → CLEAR → planner output passes through
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

        // Initialize ramp with far depth
        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 10.0, arkitSpeedMps: 1.0))
        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0.5, forwardDepth: 10.0, arkitSpeedMps: 1.0))

        // Provide sustained close readings so the internal EMA filter converges.
        // Default EMA alpha (approaching) = 0.5, so each tick halves the gap.
        // After ~10 readings at 0.1m, filtered depth converges well below brakeDist.
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

    func testIsOverriddenTrueOnlyForBrake() {
        let planner = ConstantSpeedPlanner(config: .init(maxRampRatePerSecond: 10.0))
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        // Ramp up first
        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 10.0, arkitSpeedMps: 1.0))
        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0.5, forwardDepth: 10.0, arkitSpeedMps: 1.0))

        // Sustained close readings to converge EMA filter
        for i in 1...15 {
            let t = 0.5 + Double(i) * 0.016
            _ = orchestrator.tick(context: PlannerTestFactory.context(
                timestamp: t, forwardDepth: 0.1, arkitSpeedMps: 1.0
            ))
        }
        XCTAssertTrue(orchestrator.isOverridden, "isOverridden should be true in BRAKE")
    }

    func testIsOverriddenFalseForCaution() {
        let planner = ConstantSpeedPlanner()
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        // Initialize planner ramp
        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 10.0))

        // CAUTION zone: at fallback 0.3 m/s, brakeDist=0.24, clearDist=0.45
        // depth=0.35 should be in CAUTION
        let ctxCaution = PlannerTestFactory.context(timestamp: 0.1, forwardDepth: 0.35)
        _ = orchestrator.tick(context: ctxCaution)
        XCTAssertFalse(orchestrator.isOverridden,
                       "isOverridden should be false for CAUTION (only BRAKE triggers alarm)")
    }

    func testIsOverriddenFalseForClear() {
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
        XCTAssertEqual(orchestrator.supervisorState, .clear)

        // Ramp up, then sustained close readings to converge EMA and trigger BRAKE
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

    // MARK: - Event Reporting

    func testLastSupervisorEventIsUpdated() {
        let planner = ConstantSpeedPlanner()
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        let ctx = PlannerTestFactory.context(timestamp: 1.0, forwardDepth: 5.0)
        _ = orchestrator.tick(context: ctx)

        XCTAssertNotNil(orchestrator.lastSupervisorEvent)
        XCTAssertEqual(orchestrator.lastSupervisorEvent!.timestamp, 1.0, accuracy: 1e-5)
    }

    // MARK: - Reset

    func testResetClearsAllState() {
        let planner = ConstantSpeedPlanner()
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        // Build up some state by ticking
        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 0.1))

        orchestrator.reset()
        XCTAssertEqual(orchestrator.lastCommand, .neutral)
        XCTAssertNil(orchestrator.lastSupervisorEvent)
        XCTAssertFalse(orchestrator.isOverridden)
        XCTAssertEqual(orchestrator.supervisorState, .clear)
    }

    // MARK: - Planner Swap

    func testSwapPlannerResetsPrevious() {
        let planner1 = ConstantSpeedPlanner()
        let orchestrator = PlannerOrchestrator(planner: planner1)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.5))

        // Build up state
        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 10.0))

        let planner2 = ConstantSpeedPlanner()
        orchestrator.swapPlanner(planner2)

        // After swap, activePlanner should be planner2
        XCTAssertTrue(orchestrator.activePlanner === planner2)

        // planner2 has no goal set → should produce neutral
        let cmd = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 1.0, forwardDepth: 10.0))
        XCTAssertEqual(cmd, .neutral, "Swapped planner with no goal should produce neutral")
    }

    // MARK: - Goal Passthrough

    func testGoalPassthroughToPlanner() {
        let planner = ConstantSpeedPlanner()
        let orchestrator = PlannerOrchestrator(planner: planner)

        // Before goal: should produce neutral
        let cmd1 = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 0, forwardDepth: 10.0))
        XCTAssertEqual(cmd1, .neutral)

        // After goal: should produce non-neutral (after ramp)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.3))
        _ = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 1.0, forwardDepth: 10.0))
        let cmd2 = orchestrator.tick(context: PlannerTestFactory.context(timestamp: 1.1, forwardDepth: 10.0))
        XCTAssertGreaterThan(cmd2.throttle, 0, "After goal set and ramp, throttle should be positive")
    }
}

// MARK: - Integration: Full Pipeline Tests

final class PlannerPipelineIntegrationTests: XCTestCase {

    /// Simulates an entire mission: start → approach wall → brake → wall removed → resume.
    /// Verifies no oscillation and correct state sequence end-to-end.
    func testFullMissionWithWallEncounter() {
        let planner = ConstantSpeedPlanner(config: .init(maxRampRatePerSecond: 2.0))
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.3))

        let dt = 1.0 / 60.0  // 60 Hz
        var speed = 0.0
        var stateLog: [(time: Double, state: String, throttle: Float)] = []

        // Phase 1 (t=0..1s): Open road, ramp up
        for i in 0..<60 {
            let t = Double(i) * dt
            let ctx = PlannerTestFactory.context(
                timestamp: t, forwardDepth: 10.0, arkitSpeedMps: speed
            )
            let cmd = orchestrator.tick(context: ctx)
            speed = Double(max(0, cmd.throttle)) * 1.0  // Simple speed model
            stateLog.append((t, "\(orchestrator.supervisorState)", cmd.throttle))
        }

        // Should be driving with positive throttle by now
        let lastThrottle = stateLog.last?.throttle ?? 0
        XCTAssertGreaterThan(lastThrottle, 0.1, "Should be driving after 1s ramp")

        // Phase 2 (t=1..2s): Wall at 0.1m appears
        var brakeEngaged = false
        for i in 0..<60 {
            let t = 1.0 + Double(i) * dt
            let ctx = PlannerTestFactory.context(
                timestamp: t, forwardDepth: 0.1, arkitSpeedMps: speed
            )
            let cmd = orchestrator.tick(context: ctx)
            if cmd.throttle == 0 && !brakeEngaged {
                brakeEngaged = true
            }
            speed = max(0, Double(cmd.throttle) * 1.0)
        }
        XCTAssertTrue(brakeEngaged, "Brake should have engaged when wall appeared")
        XCTAssertTrue(orchestrator.isOverridden, "Should be in override at end of wall phase")

        // Phase 3 (t=2..4s): Wall removed, verify smooth recovery
        var stateTransitions: [String] = []
        var lastStateName = "brake"

        for i in 0..<120 {
            let t = 2.0 + Double(i) * dt
            let ctx = PlannerTestFactory.context(
                timestamp: t, forwardDepth: 10.0, arkitSpeedMps: speed
            )
            let cmd = orchestrator.tick(context: ctx)
            speed = max(0, Double(cmd.throttle) * 1.0)

            let currentState: String
            switch orchestrator.supervisorState {
            case .clear: currentState = "clear"
            case .caution: currentState = "caution"
            case .brake: currentState = "brake"
            }
            if currentState != lastStateName {
                stateTransitions.append(currentState)
                lastStateName = currentState
            }
        }

        // Should recover: brake → caution → clear
        XCTAssertEqual(stateTransitions, ["caution", "clear"],
                       "Recovery should be brake→caution→clear, got: \(stateTransitions)")

        // Should be driving again
        XCTAssertFalse(orchestrator.isOverridden, "Should not be overridden after recovery")
    }

    /// Proves that the planner's throttle ramp cooperates with the supervisor:
    /// after brake release, the gentle ramp prevents re-triggering.
    func testRampPreventsReEngagementAfterBrakeRelease() {
        // Use a slow ramp rate so throttle rises gradually
        let planner = ConstantSpeedPlanner(config: .init(maxRampRatePerSecond: 0.3))
        let orchestrator = PlannerOrchestrator(planner: planner)
        orchestrator.setGoal(.constantThrottle(targetThrottle: 0.3))

        let dt = 1.0 / 60.0

        // Phase 1: Ramp up in open space
        for i in 0..<60 {
            let ctx = PlannerTestFactory.context(
                timestamp: Double(i) * dt, forwardDepth: 10.0, arkitSpeedMps: 0.3
            )
            _ = orchestrator.tick(context: ctx)
        }

        // Phase 2: Obstacle at edge of caution zone (0.35m at fallback speed)
        // This is right at the boundary where old design would oscillate.
        var brakeCount = 0
        var lastWasBrake = false
        for i in 0..<300 {  // 5 seconds of continuous operation
            let t = 1.0 + Double(i) * dt
            let ctx = PlannerTestFactory.context(
                timestamp: t, forwardDepth: 0.35, arkitSpeedMps: 0.3
            )
            let cmd = orchestrator.tick(context: ctx)
            let isBrake = cmd.throttle == 0 && cmd.source == .safetySupervisor
            if isBrake && !lastWasBrake { brakeCount += 1 }
            lastWasBrake = isBrake
        }

        // At 0.35m with fallback speed 0.3: brakeDist=0.24, clearDist=0.45
        // 0.35m is in CAUTION, should NEVER enter BRAKE
        XCTAssertEqual(brakeCount, 0,
                       "Obstacle at 0.35m (CAUTION zone) should never trigger BRAKE (triggered \(brakeCount) times)")
    }
}
