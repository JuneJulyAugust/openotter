import XCTest
@testable import openotter

final class FigureEightTrajectoryTests: XCTestCase {

    func testDefaultConfigGeneratesExpectedCountAndAcceptanceRadius() {
        let config = FigureEightTrajectory.Config()
        let waypoints = FigureEightTrajectory.waypoints(config: config)

        XCTAssertEqual(waypoints.count, 240)
        XCTAssertEqual(waypoints.first?.acceptanceRadius ?? -1, 0.25, accuracy: 0.001)
        XCTAssertEqual(waypoints.last?.acceptanceRadius ?? -1, 0.25, accuracy: 0.001)
    }

    func testWaypointsStayWithinConfiguredHorizontalInfinityDimensions() {
        let config = FigureEightTrajectory.Config(segmentCount: 720)
        let waypoints = FigureEightTrajectory.waypoints(config: config)

        let maxAbsX = waypoints.map { abs($0.x) }.max() ?? 0
        let maxAbsZ = waypoints.map { abs($0.z) }.max() ?? 0
        let hasLeft = waypoints.contains(where: { $0.x < 0 })
        let hasRight = waypoints.contains(where: { $0.x > 0 })
        let hasTop = waypoints.contains(where: { $0.z > 0 })
        let hasBottom = waypoints.contains(where: { $0.z < 0 })

        XCTAssertEqual(maxAbsX, config.length / 2, accuracy: 0.02)
        XCTAssertEqual(maxAbsZ, config.width / 2, accuracy: 0.02)
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
