import XCTest
@testable import openotter

final class FigureEightTrajectoryTests: XCTestCase {

    func testDefaultConfigGeneratesExpectedCountAndAcceptanceRadius() {
        let config = FigureEightTrajectory.Config()
        let waypoints = FigureEightTrajectory.waypoints(config: config)

        XCTAssertEqual(waypoints.count, 240)
        XCTAssertEqual(config.length, 3.2, accuracy: 0.001)
        XCTAssertEqual(config.width, 1.6, accuracy: 0.001)
        XCTAssertEqual(waypoints.first?.acceptanceRadius ?? -1, 0.12, accuracy: 0.001)
        XCTAssertEqual(waypoints.last?.acceptanceRadius ?? -1, 0.12, accuracy: 0.001)
    }

    func testWaypointsStayWithinConfiguredAppMapHorizontalInfinityDimensions() {
        let config = FigureEightTrajectory.Config(segmentCount: 720)
        let waypoints = FigureEightTrajectory.waypoints(config: config)

        let maxAbsX = waypoints.map { abs($0.x) }.max() ?? 0
        let maxAbsZ = waypoints.map { abs($0.z) }.max() ?? 0
        let hasLeft = waypoints.contains(where: { $0.x < 0 })
        let hasRight = waypoints.contains(where: { $0.x > 0 })
        let hasTop = waypoints.contains(where: { $0.z > 0 })
        let hasBottom = waypoints.contains(where: { $0.z < 0 })

        XCTAssertEqual(maxAbsX, config.width / 2, accuracy: 0.02)
        XCTAssertEqual(maxAbsZ, config.length / 2, accuracy: 0.02)
        XCTAssertTrue(hasLeft)
        XCTAssertTrue(hasRight)
        XCTAssertTrue(hasTop)
        XCTAssertTrue(hasBottom)
    }

    func testAnchoredPathStartsAtCenterCrossingAndFirstSegmentEntersRightLobe() {
        let anchor = PoseEntry(timestamp: 0, x: 4, y: 0, z: -2, yaw: 0, confidence: 1)
        let config = FigureEightTrajectory.Config(
            segmentCount: 240,
            length: 4.0,
            width: 2.0,
            acceptanceRadius: 0.25
        )

        let waypoints = FigureEightTrajectory.waypoints(config: config, anchor: anchor)

        XCTAssertEqual(waypoints.first?.x ?? -1, anchor.x, accuracy: 0.001)
        XCTAssertEqual(waypoints.first?.z ?? -1, anchor.z, accuracy: 0.001)

        let next = waypoints[1]
        XCTAssertGreaterThan(next.x, anchor.x)
        XCTAssertGreaterThan(next.z, anchor.z)

        let rightLobePeak = waypoints[config.segmentCount / 4]
        XCTAssertEqual(rightLobePeak.x, anchor.x, accuracy: 0.08)
        XCTAssertGreaterThan(
            rightLobePeak.z,
            anchor.z + config.length / 2 - 0.08,
            "The app map's horizontal +Z/right axis is the long axis of the figure eight"
        )
    }

    func testPathCrossesAnchorAgainHalfwayThroughLoop() {
        let anchor = PoseEntry(timestamp: 0, x: 4, y: 0, z: -2, yaw: 0, confidence: 1)
        let segmentCount = 240
        let waypoints = FigureEightTrajectory.waypoints(
            config: .init(segmentCount: segmentCount, length: 4.0, width: 2.0, acceptanceRadius: 0.25),
            anchor: anchor
        )
        let halfway = waypoints[segmentCount / 2]

        XCTAssertEqual(halfway.x, anchor.x, accuracy: 0.001)
        XCTAssertEqual(halfway.z, anchor.z, accuracy: 0.001)
    }

    func testAnchoredPathRotatesWithAnchorYaw() {
        let anchor = PoseEntry(timestamp: 0, x: 1, y: 0, z: 1, yaw: .pi / 2, confidence: 1)
        let waypoints = FigureEightTrajectory.waypoints(
            config: .init(segmentCount: 240, length: 4.0, width: 2.0, acceptanceRadius: 0.25),
            anchor: anchor
        )

        let next = waypoints[1]

        XCTAssertLessThan(next.z, anchor.z)
        XCTAssertGreaterThan(next.x, anchor.x)
    }

    func testPathFormsContinuousLoop() {
        let config = FigureEightTrajectory.Config(segmentCount: 240, length: 4.0, width: 2.0)
        let waypoints = FigureEightTrajectory.waypoints(config: config)
        let first = waypoints.first!
        let last = waypoints.last!

        XCTAssertLessThanOrEqual(abs(last.x - first.x), 0.06)
        XCTAssertLessThanOrEqual(abs(last.z - first.z), 0.06)
    }

    func testDefaultPathUsesEvenWaypointSpacingForSmoothLookahead() {
        let waypoints = FigureEightTrajectory.waypoints(config: .init())
        let distances = adjacentDistances(waypoints)

        let minDistance = distances.min() ?? 0
        let maxDistance = distances.max() ?? 0

        XCTAssertGreaterThan(minDistance, 0.04)
        XCTAssertLessThanOrEqual(maxDistance / minDistance, 1.10)
    }

    func testDefaultPathAvoidsTightCornerLikeCurvature() {
        let waypoints = FigureEightTrajectory.waypoints(config: .init())

        XCTAssertLessThanOrEqual(maxDiscreteCurvature(waypoints), 2.3)
    }

    func testConfigClampMinimumValues() {
        let config = FigureEightTrajectory.Config(
            segmentCount: 2,
            length: 0.0,
            width: 0.01,
            acceptanceRadius: 0.0
        )
        let waypoints = FigureEightTrajectory.waypoints(config: config)

        XCTAssertEqual(waypoints.count, 12)
        for waypoint in waypoints {
            XCTAssertFalse(waypoint.x.isNaN)
            XCTAssertFalse(waypoint.z.isNaN)
            XCTAssertTrue(waypoint.x.isFinite)
            XCTAssertTrue(waypoint.z.isFinite)
            XCTAssertGreaterThanOrEqual(waypoint.acceptanceRadius, 0.05)
        }
    }
}

private func adjacentDistances(_ waypoints: [Waypoint]) -> [Float] {
    guard waypoints.count > 1 else { return [] }

    return waypoints.indices.map { index in
        let next = waypoints[(index + 1) % waypoints.count]
        let current = waypoints[index]
        let dx = next.x - current.x
        let dz = next.z - current.z
        return sqrtf(dx * dx + dz * dz)
    }
}

private func maxDiscreteCurvature(_ waypoints: [Waypoint]) -> Float {
    guard waypoints.count > 2 else { return 0 }

    var maxCurvature: Float = 0
    for index in waypoints.indices {
        let previous = waypoints[(index - 1 + waypoints.count) % waypoints.count]
        let current = waypoints[index]
        let next = waypoints[(index + 1) % waypoints.count]

        let a = groundDistance(previous, current)
        let b = groundDistance(current, next)
        let c = groundDistance(previous, next)
        guard a > 0, b > 0, c > 0 else { continue }

        let twiceArea = abs((current.x - previous.x) * (next.z - previous.z) -
                            (current.z - previous.z) * (next.x - previous.x))
        let curvature = 2 * twiceArea / (a * b * c)
        maxCurvature = max(maxCurvature, curvature)
    }
    return maxCurvature
}

private func groundDistance(_ lhs: Waypoint, _ rhs: Waypoint) -> Float {
    let dx = rhs.x - lhs.x
    let dz = rhs.z - lhs.z
    return sqrtf(dx * dx + dz * dz)
}
