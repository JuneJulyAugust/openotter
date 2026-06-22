import XCTest
@testable import openotter

final class LQRTrackPlannerTests: XCTestCase {

    private let defaultPose = PoseEntry(
        timestamp: 0,
        x: 0,
        y: 0,
        z: 0,
        yaw: 0,
        confidence: 1.0
    )

    func testFigureEightGoalAnchorsAndUsesLQRTrackSource() {
        let planner = LQRTrackPlanner()
        planner.setGoal(.followFigureEight(
            config: .init(segmentCount: 240, length: 3.2, width: 1.6, acceptanceRadius: 0.12),
            maxThrottle: 0.4,
            controller: .lqrTrack
        ))

        let command = planner.plan(context: PlannerTestFactory.context(
            timestamp: 0,
            arkitSpeedMps: 0,
            pose: defaultPose
        ))

        XCTAssertEqual(command.source, .planner("LQRTrack"))
        XCTAssertEqual(planner.activeWaypoints.count, 240)
        XCTAssertEqual(planner.activeWaypoints.first?.x ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(planner.activeWaypoints.first?.z ?? -1, 0, accuracy: 0.001)
        XCTAssertGreaterThan(command.throttle, 0)
        XCTAssertLessThanOrEqual(command.throttle, 0.4)
        XCTAssertLessThanOrEqual(abs(command.steering), 1.0)
    }

    func testRightOfPathCommandsLeftSteering() {
        let command = figureEightCommand(offsetAt: 30, lateralOffset: 0.2, arkitSpeedMps: 0.2)

        XCTAssertLessThan(
            command.steering,
            -0.02,
            "Positive cross-track error means right of path, so LQRTrack should steer left"
        )
    }

    func testLeftOfPathCommandsRightSteering() {
        let command = figureEightCommand(offsetAt: 30, lateralOffset: -0.2, arkitSpeedMps: 0.2)

        XCTAssertGreaterThan(
            command.steering,
            0.02,
            "Negative cross-track error means left of path, so LQRTrack should steer right"
        )
    }

    func testSpeedErrorChangesThrottle() {
        let slow = figureEightCommand(offsetAt: 20, lateralOffset: 0, arkitSpeedMps: 0.05)
        let fast = figureEightCommand(offsetAt: 20, lateralOffset: 0, arkitSpeedMps: 0.40)

        XCTAssertGreaterThan(slow.throttle, fast.throttle)
        XCTAssertGreaterThan(slow.throttle, 0.25)
        XCTAssertGreaterThanOrEqual(fast.throttle, 0)
        XCTAssertLessThanOrEqual(slow.throttle, 0.4)
        XCTAssertLessThanOrEqual(fast.throttle, 0.4)
    }

    func testFigureEightSimulationMakesForwardProgress() {
        let planner = LQRTrackPlanner()
        planner.setGoal(.followFigureEight(
            config: .init(segmentCount: 240, length: 3.2, width: 1.6, acceptanceRadius: 0.12),
            maxThrottle: 0.4,
            controller: .lqrTrack
        ))

        let result = simulateFigureEight(
            planner: planner,
            stepCount: 260,
            yawGain: 0.7,
            throttleToMps: 0.65,
            length: 3.2,
            width: 1.6
        )

        XCTAssertLessThan(result.maxEnvelopeOvershoot, 0.35)
        XCTAssertLessThan(result.maxSegmentCrossTrackError, 0.45)
        XCTAssertGreaterThan(
            planner.currentWaypointIndex,
            40,
            "LQRTrack should make visible progress around the reference path in the deterministic simulation"
        )
    }

    private func figureEightCommand(offsetAt index: Int,
                                    lateralOffset: Float,
                                    arkitSpeedMps: Double) -> ControlCommand {
        let planner = LQRTrackPlanner()
        planner.setGoal(.followFigureEight(
            config: .init(segmentCount: 240, length: 3.2, width: 1.6, acceptanceRadius: 0.12),
            maxThrottle: 0.4,
            controller: .lqrTrack
        ))
        _ = planner.plan(context: PlannerTestFactory.context(timestamp: 0, arkitSpeedMps: arkitSpeedMps, pose: defaultPose))

        let waypoints = planner.activeWaypoints
        let reference = PathReference.project(
            pose: PoseEntry(timestamp: 0, x: waypoints[index].x, y: 0, z: waypoints[index].z, yaw: 0, confidence: 1),
            waypoints: waypoints,
            currentIndex: index,
            progressSearchCount: 0,
            curvatureSampleSpan: 3
        )
        let right = rightVector(yaw: reference.tangentYaw)
        let pose = PoseEntry(
            timestamp: 1,
            x: reference.projectedPoint.x + right.x * lateralOffset,
            y: 0,
            z: reference.projectedPoint.z + right.z * lateralOffset,
            yaw: reference.tangentYaw,
            confidence: 1
        )

        return planner.plan(context: PlannerTestFactory.context(
            timestamp: pose.timestamp,
            arkitSpeedMps: arkitSpeedMps,
            pose: pose
        ))
    }

    private struct FigureEightSimulationResult {
        let maxSegmentCrossTrackError: Float
        let maxEnvelopeOvershoot: Float
    }

    private func simulateFigureEight(planner: LQRTrackPlanner,
                                     stepCount: Int,
                                     yawGain: Float,
                                     throttleToMps: Float,
                                     length: Float,
                                     width: Float) -> FigureEightSimulationResult {
        let dt: TimeInterval = 0.1
        var pose = defaultPose
        var measuredSpeedMps: Double = 0
        var maxDistance: Float = 0
        var maxOvershoot: Float = 0

        for step in 0..<stepCount {
            let timestamp = TimeInterval(step) * dt
            let command = planner.plan(context: PlannerTestFactory.context(
                timestamp: timestamp,
                arkitSpeedMps: measuredSpeedMps,
                pose: pose
            ))

            let reference = PathReference.project(
                pose: pose,
                waypoints: planner.activeWaypoints,
                currentIndex: planner.currentWaypointIndex,
                progressSearchCount: 32,
                curvatureSampleSpan: 3
            )
            maxDistance = max(maxDistance, abs(reference.crossTrackError))
            maxOvershoot = max(maxOvershoot, envelopeOvershoot(pose: pose, length: length, width: width))

            let speed = max(0, command.throttle) * throttleToMps
            measuredSpeedMps = Double(speed)
            let yaw = (pose.yaw - command.steering * yawGain * Float(dt)).wrapToPi()
            pose = PoseEntry(
                timestamp: timestamp + dt,
                x: pose.x + cosf(yaw) * speed * Float(dt),
                y: 0,
                z: pose.z - sinf(yaw) * speed * Float(dt),
                yaw: yaw,
                confidence: 1
            )
        }

        return FigureEightSimulationResult(
            maxSegmentCrossTrackError: maxDistance,
            maxEnvelopeOvershoot: maxOvershoot
        )
    }

    private func envelopeOvershoot(pose: PoseEntry, length: Float, width: Float) -> Float {
        max(0, abs(pose.x) - width / 2, abs(pose.z) - length / 2)
    }
}
