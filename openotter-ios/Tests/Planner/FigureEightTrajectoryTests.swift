import XCTest
@testable import openotter

final class FigureEightTrajectoryTests: XCTestCase {

    func testDefaultConfigGeneratesExpectedCountAndAcceptanceRadius() {
        let config = FigureEightTrajectory.Config()
        let waypoints = FigureEightTrajectory.waypoints(config: config)

        XCTAssertEqual(waypoints.count, 120)
        XCTAssertEqual(waypoints.first?.acceptanceRadius ?? -1, 0.22, accuracy: 0.001)
        XCTAssertEqual(waypoints.last?.acceptanceRadius ?? -1, 0.22, accuracy: 0.001)
    }

    func testWaypointsStayWithinConfiguredEnvelope() {
        let config = FigureEightTrajectory.Config(
            segmentCount: 720,
            length: 1.2,
            width: 0.8,
            acceptanceRadius: 0.12
        )
        let waypoints = FigureEightTrajectory.waypoints(config: config)

        let maxAbsX = waypoints.map { abs($0.x) }.max() ?? 0
        let maxAbsZ = waypoints.map { abs($0.z) }.max() ?? 0
        let hasLeft = waypoints.contains(where: { $0.x < 0 })
        let hasRight = waypoints.contains(where: { $0.x > 0 })
        let hasTop = waypoints.contains(where: { $0.z > 0 })
        let hasBottom = waypoints.contains(where: { $0.z < 0 })
        let envelopeRadius = hypotf(config.length / 2, config.width / 2)

        XCTAssertLessThanOrEqual(maxAbsX, envelopeRadius + 0.02)
        XCTAssertLessThanOrEqual(maxAbsZ, envelopeRadius + 0.02)
        XCTAssertTrue(hasLeft)
        XCTAssertTrue(hasRight)
        XCTAssertTrue(hasTop)
        XCTAssertTrue(hasBottom)
    }

    func testAnchoredPathStartsAtAnchorAndInitialSegmentIsForward() {
        let anchor = PoseEntry(timestamp: 0, x: 4, y: 0, z: -2, yaw: 0, confidence: 1)
        let config = FigureEightTrajectory.Config(
            segmentCount: 120,
            length: 1.5,
            width: 1.0,
            acceptanceRadius: 0.2
        )

        let waypoints = FigureEightTrajectory.waypoints(config: config, anchor: anchor)

        XCTAssertEqual(waypoints.first?.x ?? -1, anchor.x, accuracy: 0.001)
        XCTAssertEqual(waypoints.first?.z ?? -1, anchor.z, accuracy: 0.001)

        let next = waypoints[1]
        XCTAssertGreaterThan(next.x, anchor.x)
        XCTAssertLessThan(abs(next.z - anchor.z), 0.02)
    }

    func testAnchoredPathRotatesWithAnchorYaw() {
        let anchor = PoseEntry(timestamp: 0, x: 1, y: 0, z: 1, yaw: .pi / 2, confidence: 1)
        let waypoints = FigureEightTrajectory.waypoints(
            config: .init(segmentCount: 120, length: 1.5, width: 1.0, acceptanceRadius: 0.2),
            anchor: anchor
        )

        let next = waypoints[1]

        XCTAssertLessThan(next.z, anchor.z)
        XCTAssertLessThan(abs(next.x - anchor.x), 0.02)
    }

    func testPathFormsContinuousLoop() {
        let config = FigureEightTrajectory.Config(segmentCount: 144, length: 1.5, width: 1.0)
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
