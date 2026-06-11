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

    func testPlannerAdvancesToNextWaypointAfterReach() {
        let planner = WaypointPlanner()
        planner.setGoal(.followWaypoints([
            Waypoint(x: 0.4, z: 0.4, acceptanceRadius: 0.1),
            Waypoint(x: 0.4, z: -0.4, acceptanceRadius: 0.1)
        ], maxThrottle: 0.5))

        let first = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0, pose: defaultPose))
        XCTAssertLessThan(first.steering, 0, "First segment should steer toward +z right")

        let second = planner.plan(context: PlannerTestFactory.context(
            timestamp: 0.1,
            pose: PoseEntry(timestamp: 0.1, x: 0.4, y: 0, z: 0.4, yaw: 0, confidence: 1)
        ))
        XCTAssertGreaterThan(second.steering, 0, "After reaching first waypoint, target should flip")
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
