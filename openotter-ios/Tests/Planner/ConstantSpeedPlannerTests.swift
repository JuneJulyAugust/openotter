import XCTest
@testable import openotter

// MARK: - ConstantSpeedPlannerTests

final class ConstantSpeedPlannerTests: XCTestCase {

    // MARK: - Goal Setting

    func testIdleGoalProducesNeutral() {
        let planner = ConstantSpeedPlanner()
        planner.setGoal(.idle)
        let cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 1.0))
        XCTAssertEqual(cmd, .neutral)
    }

    func testFollowWaypointsGoalIsIgnored() {
        let planner = ConstantSpeedPlanner()
        planner.setGoal(.followWaypoints([], maxThrottle: 0.5))
        let cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 1.0))
        XCTAssertEqual(cmd, .neutral, "ConstantSpeedPlanner should ignore followWaypoints goals")
    }

    func testConstantThrottleGoalActivatesPlanner() {
        let planner = ConstantSpeedPlanner()
        planner.setGoal(.constantThrottle(targetThrottle: 0.4))

        // First tick returns zero (ramp starts from 0).
        let cmd1 = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0))
        XCTAssertEqual(cmd1.throttle, 0, accuracy: 1e-5, "First tick should output zero (ramp start)")
        XCTAssertEqual(cmd1.steering, 0, accuracy: 1e-5)
        XCTAssertEqual(cmd1.source, .planner("ConstantThrottlePlanner"))
    }

    func testThrottleIsClamped() {
        let planner = ConstantSpeedPlanner()
        planner.setGoal(.constantThrottle(targetThrottle: 5.0))

        // After several ticks the output should never exceed 1.0
        var cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0))
        for i in 1...100 {
            cmd = planner.plan(context: PlannerTestFactory.context(timestamp: Double(i) * 0.1))
        }
        XCTAssertLessThanOrEqual(cmd.throttle, 1.0)
    }

    func testNegativeThrottleIsClamped() {
        let planner = ConstantSpeedPlanner()
        planner.setGoal(.constantThrottle(targetThrottle: -5.0))

        var cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0))
        for i in 1...100 {
            cmd = planner.plan(context: PlannerTestFactory.context(timestamp: Double(i) * 0.1))
        }
        XCTAssertGreaterThanOrEqual(cmd.throttle, -1.0)
    }

    // MARK: - Throttle Ramp

    func testThrottleRampsGraduallyNotInstant() {
        let config = ConstantSpeedPlannerConfig(maxRampRatePerSecond: 0.5)
        let planner = ConstantSpeedPlanner(config: config)
        planner.setGoal(.constantThrottle(targetThrottle: 0.5))

        // t=0: first tick, output = 0 (initializes timestamp)
        let cmd0 = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0))
        XCTAssertEqual(cmd0.throttle, 0, accuracy: 1e-5)

        // t=0.1: after 100ms, max delta = 0.5 * 0.1 = 0.05
        let cmd1 = planner.plan(context: PlannerTestFactory.context(timestamp: 0.1))
        XCTAssertEqual(cmd1.throttle, 0.05, accuracy: 1e-4, "After 100ms, ramp should produce ~0.05")

        // t=0.2: after another 100ms, delta += 0.05 → 0.10
        let cmd2 = planner.plan(context: PlannerTestFactory.context(timestamp: 0.2))
        XCTAssertEqual(cmd2.throttle, 0.10, accuracy: 1e-4)
    }

    func testThrottleReachesTargetEventually() {
        let config = ConstantSpeedPlannerConfig(maxRampRatePerSecond: 1.0)
        let planner = ConstantSpeedPlanner(config: config)
        planner.setGoal(.constantThrottle(targetThrottle: 0.3))

        // Simulate 2 seconds at 60 Hz — more than enough time to reach 0.3
        var cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0))
        let dt = 1.0 / 60.0
        for i in 1...120 {
            cmd = planner.plan(context: PlannerTestFactory.context(timestamp: Double(i) * dt))
        }
        XCTAssertEqual(cmd.throttle, 0.3, accuracy: 1e-3, "Throttle should converge to target")
    }

    func testThrottleRampsDown() {
        let config = ConstantSpeedPlannerConfig(maxRampRatePerSecond: 1.0)
        let planner = ConstantSpeedPlanner(config: config)
        planner.setGoal(.constantThrottle(targetThrottle: 0.5))

        // Ramp up for 1 second
        _ = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0))
        for i in 1...60 {
            _ = planner.plan(context: PlannerTestFactory.context(timestamp: Double(i) / 60.0))
        }

        // Change goal to lower throttle
        planner.setGoal(.constantThrottle(targetThrottle: 0.1))

        // Ramp down for 1 second
        _ = planner.plan(context: PlannerTestFactory.context(timestamp: 2.0))
        var cmd = ControlCommand.neutral
        for i in 1...60 {
            cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 2.0 + Double(i) / 60.0))
        }
        XCTAssertEqual(cmd.throttle, 0.1, accuracy: 1e-2, "Throttle should ramp down to new target")
    }

    func testStaleTimestampDoesNotJump() {
        let planner = ConstantSpeedPlanner()
        planner.setGoal(.constantThrottle(targetThrottle: 0.5))

        _ = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0))
        let cmd1 = planner.plan(context: PlannerTestFactory.context(timestamp: 0.1))
        let t1 = cmd1.throttle

        // dt > 1.0 → stale, should not change output
        let cmd2 = planner.plan(context: PlannerTestFactory.context(timestamp: 5.0))
        XCTAssertEqual(cmd2.throttle, t1, accuracy: 1e-5, "Stale dt should not change throttle output")
    }

    // MARK: - Reset

    func testResetClearsState() {
        let planner = ConstantSpeedPlanner()
        planner.setGoal(.constantThrottle(targetThrottle: 0.5))

        _ = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0))
        _ = planner.plan(context: PlannerTestFactory.context(timestamp: 0.1))

        planner.reset()
        let cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 1.0))
        XCTAssertEqual(cmd, .neutral, "After reset, planner should produce neutral")
    }

    func testSetGoalResetsBeforeApplying() {
        let planner = ConstantSpeedPlanner()
        planner.setGoal(.constantThrottle(targetThrottle: 0.5))
        _ = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0))
        _ = planner.plan(context: PlannerTestFactory.context(timestamp: 0.1))

        // Setting a new goal should reset the ramp state
        planner.setGoal(.constantThrottle(targetThrottle: 0.3))
        let cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 1.0))
        XCTAssertEqual(cmd.throttle, 0, accuracy: 1e-5, "New goal should reset ramp to zero")
    }

    // MARK: - Steering

    func testSteeringIsAlwaysNeutral() {
        let planner = ConstantSpeedPlanner()
        planner.setGoal(.constantThrottle(targetThrottle: 0.5))

        for i in 0...10 {
            let cmd = planner.plan(context: PlannerTestFactory.context(timestamp: Double(i) * 0.1))
            XCTAssertEqual(cmd.steering, 0, accuracy: 1e-5, "Constant speed planner always has zero steering")
        }
    }
}
