import XCTest
@testable import openotter

final class RobotGeometryTests: XCTestCase {

    func testYawZeroAxesMatchPlannerConvention() {
        let forward = forwardVector(yaw: 0)
        let right = rightVector(yaw: 0)

        XCTAssertEqual(forward.x, 1, accuracy: 1e-5)
        XCTAssertEqual(forward.z, 0, accuracy: 1e-5)
        XCTAssertEqual(right.x, 0, accuracy: 1e-5)
        XCTAssertEqual(right.z, 1, accuracy: 1e-5)
    }

    func testLocalPointTransformsThroughPoseYaw() {
        let pose = PoseEntry(timestamp: 0, x: 2, y: 0, z: 3, yaw: .pi / 2, confidence: 1)

        let point = worldPoint(localX: 1, localZ: 0, anchor: pose)

        XCTAssertEqual(point.x, 2, accuracy: 1e-5)
        XCTAssertEqual(point.z, 2, accuracy: 1e-5)
    }
}
