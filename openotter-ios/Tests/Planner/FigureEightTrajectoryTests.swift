import XCTest
@testable import openotter

final class FigureEightTrajectoryTests: XCTestCase {

    func testDefaultConfigGeneratesExpectedCountAndAcceptanceRadius() {
        let config = FigureEightTrajectory.Config()
        let waypoints = FigureEightTrajectory.waypoints(config: config)

        XCTAssertEqual(waypoints.count, 72)
        XCTAssertEqual(waypoints.first?.acceptanceRadius ?? -1, 0.18, accuracy: 0.001)
        XCTAssertEqual(waypoints.last?.acceptanceRadius ?? -1, 0.18, accuracy: 0.001)
    }

    func testWaypointsStayWithinConfiguredDimensions() {
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

        XCTAssertEqual(maxAbsX, config.length / 2, accuracy: 0.02)
        XCTAssertEqual(maxAbsZ, config.width / 2, accuracy: 0.02)
        XCTAssertTrue(hasLeft)
        XCTAssertTrue(hasRight)
        XCTAssertTrue(hasTop)
        XCTAssertTrue(hasBottom)
    }

    func testPathFormsContinuousLoop() {
        let config = FigureEightTrajectory.Config(segmentCount: 144, length: 0.8, width: 0.5)
        let waypoints = FigureEightTrajectory.waypoints(config: config)
        let first = waypoints.first!
        let last = waypoints.last!

        XCTAssertLessThanOrEqual(abs(last.x - first.x), 0.03)
        XCTAssertLessThanOrEqual(abs(last.z - first.z), 0.03)
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
