import XCTest
@testable import openotter

final class WaypointPlannerTests: XCTestCase {

    private let defaultPose = PoseEntry(
        timestamp: 0,
        x: 0,
        y: 0,
        z: 0,
        yaw: 0,
        confidence: 1.0
    )

    func testEmptyGoalIsNeutral() {
        let planner = WaypointPlanner()
        planner.setGoal(.followWaypoints([], maxThrottle: 0.5))
        let cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 1.0))
        XCTAssertEqual(cmd, .neutral)
    }

    func testTargetAheadHasZeroSteeringWithForwardHeading() {
        let planner = WaypointPlanner()
        planner.setGoal(.followWaypoints([Waypoint(x: 1.0, z: 0.0, acceptanceRadius: 0.2)], maxThrottle: 0.5))

        let cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0, pose: defaultPose))
        XCTAssertEqual(cmd.steering, 0, accuracy: 1e-5)
        XCTAssertEqual(cmd.throttle, 0.5, accuracy: 1e-5)
        XCTAssertEqual(cmd.source, .planner("WaypointPlanner"))
    }

    func testTargetToRobotRightProducesPositiveSteering() {
        let planner = WaypointPlanner()
        planner.setGoal(.followWaypoints([Waypoint(x: 0.5, z: 0.5, acceptanceRadius: 0.1)], maxThrottle: 0.6))

        let cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0, pose: defaultPose))

        XCTAssertGreaterThan(cmd.steering, 0, "Positive steering maps to right PWM in PwmMapping")
        XCTAssertGreaterThan(cmd.throttle, 0.3)
    }

    func testTargetToRobotLeftProducesNegativeSteering() {
        let planner = WaypointPlanner()
        planner.setGoal(.followWaypoints([Waypoint(x: 0.5, z: -0.5, acceptanceRadius: 0.1)], maxThrottle: 0.6))

        let cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0, pose: defaultPose))

        XCTAssertLessThan(cmd.steering, 0, "Negative steering maps to left PWM in PwmMapping")
        XCTAssertGreaterThan(cmd.throttle, 0.3)
    }

    func testFigureEightGoalAnchorsAtFirstPoseAndStartsForward() {
        let anchor = PoseEntry(timestamp: 2.0, x: 2.0, y: 0, z: -1.0, yaw: 0, confidence: 1)
        let planner = WaypointPlanner()
        planner.setGoal(.followFigureEight(
            config: .init(segmentCount: 72, length: 1.5, width: 1.0, acceptanceRadius: 0.2),
            maxThrottle: 0.6
        ))

        let cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 2.0, pose: anchor))

        XCTAssertEqual(planner.activeWaypoints.first?.x ?? -1, anchor.x, accuracy: 0.001)
        XCTAssertEqual(planner.activeWaypoints.first?.z ?? -1, anchor.z, accuracy: 0.001)
        XCTAssertLessThan(abs(cmd.steering), 0.25, "Startup target should be mostly ahead, not hard-left or hard-right")
        XCTAssertGreaterThan(cmd.throttle, 0.4)
        XCTAssertEqual(cmd.source, .planner("WaypointPlanner"))
    }

    func testFigureEightMissionLoopsInsteadOfStoppingAfterOneLap() {
        let anchor = PoseEntry(timestamp: 0, x: 0, y: 0, z: 0, yaw: 0, confidence: 1)
        let planner = WaypointPlanner()
        planner.setGoal(.followFigureEight(
            config: .init(segmentCount: 24, length: 1.2, width: 0.8, acceptanceRadius: 0.08),
            maxThrottle: 0.6
        ))
        _ = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0, pose: anchor))

        for (i, waypoint) in planner.activeWaypoints.enumerated() {
            let pose = PoseEntry(timestamp: TimeInterval(i + 1), x: waypoint.x, y: 0, z: waypoint.z, yaw: 0, confidence: 1)
            _ = planner.plan(context: PlannerTestFactory.context(timestamp: pose.timestamp, pose: pose))
        }

        let cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 100.0, pose: anchor))
        XCTAssertNotEqual(cmd, .neutral)
        XCTAssertEqual(cmd.source, .planner("WaypointPlanner"))
    }

    func testFigureEightMissionDoesNotCompleteWhenAllWaypointsAreInsideAcceptanceRadius() {
        let anchor = PoseEntry(timestamp: 0, x: 0, y: 0, z: 0, yaw: 0, confidence: 1)
        let planner = WaypointPlanner()
        planner.setGoal(.followFigureEight(
            config: .init(segmentCount: 12, length: 0.2, width: 0.2, acceptanceRadius: 10.0),
            maxThrottle: 0.6
        ))

        let cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0, pose: anchor))

        XCTAssertNotEqual(cmd, .neutral)
        XCTAssertEqual(cmd.source, .planner("WaypointPlanner"))
    }

    func testPlannerAdvancesToNextWaypointAfterReach() {
        let planner = WaypointPlanner()
        planner.setGoal(.followWaypoints([
            Waypoint(x: 0.4, z: 0.4, acceptanceRadius: 0.1),
            Waypoint(x: 0.4, z: -0.4, acceptanceRadius: 0.1)
        ], maxThrottle: 0.5))

        let first = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0, pose: defaultPose))
        XCTAssertGreaterThan(first.steering, 0, "First segment should steer toward +z right")

        let second = planner.plan(context: PlannerTestFactory.context(
            timestamp: 0.1,
            pose: PoseEntry(timestamp: 0.1, x: 0.4, y: 0, z: 0.4, yaw: 0, confidence: 1)
        ))
        XCTAssertLessThan(second.steering, 0, "After reaching first waypoint, target should flip")
    }

    func testPlannerBecomesNeutralAfterAllWaypointsReached() {
        let planner = WaypointPlanner()
        planner.setGoal(.followWaypoints([
            Waypoint(x: 0.2, z: 0.0, acceptanceRadius: 0.2),
            Waypoint(x: 0.4, z: 0.0, acceptanceRadius: 0.2)
        ], maxThrottle: 0.5))

        _ = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0, pose: defaultPose))
        _ = planner.plan(context: PlannerTestFactory.context(
            timestamp: 0.1,
            pose: PoseEntry(timestamp: 0.1, x: 0.2, y: 0, z: 0, yaw: 0, confidence: 1)
        ))

        let done = planner.plan(context: PlannerTestFactory.context(
            timestamp: 0.2,
            pose: PoseEntry(timestamp: 0.2, x: 0.4, y: 0, z: 0, yaw: 0, confidence: 1)
        ))
        XCTAssertEqual(done, .neutral)
    }
}
