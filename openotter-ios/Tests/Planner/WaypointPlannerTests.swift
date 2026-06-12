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
            config: .init(segmentCount: 240, length: 3.2, width: 1.6, acceptanceRadius: 0.12),
            maxThrottle: 0.4
        ))

        let cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 2.0, pose: anchor))

        XCTAssertEqual(planner.activeWaypoints.first?.x ?? -1, anchor.x, accuracy: 0.001)
        XCTAssertEqual(planner.activeWaypoints.first?.z ?? -1, anchor.z, accuracy: 0.001)
        XCTAssertGreaterThan(cmd.steering, 0, "Startup should enter the first right lobe of the horizontal figure eight")
        XCTAssertGreaterThan(cmd.steering, 0.35, "Startup steering should overcome linkage deadband")
        XCTAssertLessThanOrEqual(abs(cmd.steering), 0.45, "Figure-eight steering should stay below servo-stop saturation")
        XCTAssertLessThanOrEqual(planner.currentWaypointIndex, 3, "Startup should not skip over the early turning cue")
        XCTAssertGreaterThan(cmd.throttle, 0.25)
        XCTAssertLessThanOrEqual(cmd.throttle, 0.4)
        XCTAssertEqual(cmd.source, .planner("WaypointPlanner"))
    }

    func testSteeringOutputIsLimitedBelowServoStop() {
        let planner = WaypointPlanner()
        planner.setGoal(.followWaypoints([Waypoint(x: 0, z: 1, acceptanceRadius: 0.1)], maxThrottle: 0.6))

        let cmd = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0, pose: defaultPose))

        XCTAssertLessThanOrEqual(abs(cmd.steering), 0.45)
    }

    func testClosedLoopPlannerSkipsAheadWhenCarMissesCurrentWaypoint() {
        let anchor = PoseEntry(timestamp: 0, x: 0, y: 0, z: 0, yaw: 0, confidence: 1)
        let planner = WaypointPlanner()
        planner.setGoal(.followFigureEight(
            config: .init(segmentCount: 240, length: 4.0, width: 2.0, acceptanceRadius: 0.18),
            maxThrottle: 0.6
        ))
        _ = planner.plan(context: PlannerTestFactory.context(timestamp: 0.0, pose: anchor))

        let skippedAheadPose = planner.activeWaypoints[28]
        let cmd = planner.plan(context: PlannerTestFactory.context(
            timestamp: 1.0,
            pose: PoseEntry(timestamp: 1.0, x: skippedAheadPose.x, y: 0, z: skippedAheadPose.z, yaw: 0, confidence: 1)
        ))

        XCTAssertGreaterThanOrEqual(planner.currentWaypointIndex, 28)
        XCTAssertLessThanOrEqual(abs(cmd.steering), 0.45)
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

    func testFigureEightControllerStaysNearPathWithSlowYawResponse() {
        let planner = WaypointPlanner()
        planner.setGoal(.followFigureEight(
            config: .init(segmentCount: 240, length: 3.2, width: 1.6, acceptanceRadius: 0.12),
            maxThrottle: 0.4
        ))

        let result = simulateFigureEight(
            planner: planner,
            stepCount: 320,
            yawGain: 0.6,
            throttleToMps: 0.65,
            length: 3.2,
            width: 1.6
        )

        XCTAssertLessThan(
            result.maxSegmentCrossTrackError,
            0.25,
            "Slow yaw response should not balloon into a lobe outside the figure-eight centerline"
        )
        XCTAssertLessThan(result.averageSegmentCrossTrackError, 0.16)
        XCTAssertGreaterThan(result.samplesWithin16cm, 140)
        XCTAssertLessThan(result.p95ReferenceHeadingError, 45 * Float.pi / 180)
        XCTAssertLessThan(result.maxEnvelopeOvershoot, 0.12)
        XCTAssertGreaterThan(
            planner.currentWaypointIndex,
            80,
            "The closed-loop controller should keep making progress around the track"
        )
    }

    func testFigureEightControllerCorrectsLateralErrorFromPathTangent() {
        let rightOfPath = figureEightCommand(offsetAt: 30, lateralOffset: 0.2)
        XCTAssertLessThan(
            rightOfPath.steering,
            -0.1,
            "When the car is right of a tangent-aligned path segment, steering should pull left"
        )

        let leftOfPath = figureEightCommand(offsetAt: 30, lateralOffset: -0.2)
        XCTAssertGreaterThan(
            leftOfPath.steering,
            0.1,
            "When the car is left of a tangent-aligned path segment, steering should pull right"
        )
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

    private struct FigureEightSimulationResult {
        let maxSegmentCrossTrackError: Float
        let averageSegmentCrossTrackError: Float
        let samplesWithin16cm: Int
        let p95ReferenceHeadingError: Float
        let maxEnvelopeOvershoot: Float
    }

    private func simulateFigureEight(planner: WaypointPlanner,
                                     stepCount: Int,
                                     yawGain: Float,
                                     throttleToMps: Float,
                                     length: Float,
                                     width: Float) -> FigureEightSimulationResult {
        let dt: TimeInterval = 0.1
        var pose = defaultPose
        var distances: [Float] = []
        var headingErrors: [Float] = []
        var envelopeOvershoots: [Float] = []

        for step in 0..<stepCount {
            let timestamp = TimeInterval(step) * dt
            let context = PlannerTestFactory.context(timestamp: timestamp, pose: pose)
            let command = planner.plan(context: context)

            let pathMetrics = nearestSegmentMetrics(from: pose, to: planner.activeWaypoints)
            distances.append(pathMetrics.distance)
            if step >= 20 {
                headingErrors.append(pathMetrics.headingError)
            }
            envelopeOvershoots.append(envelopeOvershoot(pose: pose, length: length, width: width))

            let speed = command.throttle * throttleToMps
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

        let maxError = distances.max() ?? 0
        let averageError = distances.reduce(0, +) / Float(max(1, distances.count))
        let closeSamples = distances.filter { $0 < 0.16 }.count
        return FigureEightSimulationResult(
            maxSegmentCrossTrackError: maxError,
            averageSegmentCrossTrackError: averageError,
            samplesWithin16cm: closeSamples,
            p95ReferenceHeadingError: percentile95(headingErrors),
            maxEnvelopeOvershoot: envelopeOvershoots.max() ?? 0
        )
    }

    private func figureEightCommand(offsetAt index: Int, lateralOffset: Float) -> ControlCommand {
        var config = WaypointPlannerConfig()
        config.headingDerivativeGain = 0
        let planner = WaypointPlanner(config: config)
        planner.setGoal(.followFigureEight(
            config: .init(segmentCount: 240, length: 3.2, width: 1.6, acceptanceRadius: 0.12),
            maxThrottle: 0.4
        ))
        _ = planner.plan(context: PlannerTestFactory.context(timestamp: 0, pose: defaultPose))

        let waypoints = planner.activeWaypoints
        let reference = waypoints[index]
        let tangentYaw = segmentHeading(from: reference, to: waypoints[(index + 1) % waypoints.count])
        let right = rightVector(yaw: tangentYaw)
        let pose = PoseEntry(
            timestamp: 1,
            x: reference.x + right.x * lateralOffset,
            y: 0,
            z: reference.z + right.z * lateralOffset,
            yaw: tangentYaw,
            confidence: 1
        )

        return planner.plan(context: PlannerTestFactory.context(timestamp: pose.timestamp, pose: pose))
    }

    private struct SegmentPathMetrics {
        let distance: Float
        let headingError: Float
    }

    private func nearestSegmentMetrics(from pose: PoseEntry, to waypoints: [Waypoint]) -> SegmentPathMetrics {
        guard waypoints.count > 1 else {
            return SegmentPathMetrics(distance: 0, headingError: 0)
        }

        var bestDistance = Float.greatestFiniteMagnitude
        var bestHeadingError: Float = 0
        for index in waypoints.indices {
            let start = waypoints[index]
            let end = waypoints[(index + 1) % waypoints.count]
            let dx = end.x - start.x
            let dz = end.z - start.z
            let lengthSquared = dx * dx + dz * dz
            let projection: Float
            if lengthSquared > 0 {
                projection = max(
                    0,
                    min(1, ((pose.x - start.x) * dx + (pose.z - start.z) * dz) / lengthSquared)
                )
            } else {
                projection = 0
            }

            let projectedX = start.x + dx * projection
            let projectedZ = start.z + dz * projection
            let distanceX = pose.x - projectedX
            let distanceZ = pose.z - projectedZ
            let distance = sqrtf(distanceX * distanceX + distanceZ * distanceZ)
            if distance < bestDistance {
                bestDistance = distance
                bestHeadingError = abs((segmentHeading(from: start, to: end) - pose.yaw).wrapToPi())
            }
        }

        return SegmentPathMetrics(distance: bestDistance, headingError: bestHeadingError)
    }

    private func segmentHeading(from start: Waypoint, to end: Waypoint) -> Float {
        atan2f(-(end.z - start.z), end.x - start.x)
    }

    private func envelopeOvershoot(pose: PoseEntry, length: Float, width: Float) -> Float {
        max(0, abs(pose.x) - length / 2, abs(pose.z) - width / 2)
    }

    private func percentile95(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        return sorted[index]
    }
}
