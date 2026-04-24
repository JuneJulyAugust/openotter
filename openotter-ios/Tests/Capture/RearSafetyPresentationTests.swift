import XCTest
@testable import openotter

final class RearSafetyPresentationTests: XCTestCase {

    private func makeEvent(
        state: FirmwareSafetyState,
        cause: FirmwareSafetyCause,
        velocity: Float = -0.5,
        depth: Float = 0.30,
        critical: Float = 0.55
    ) -> FirmwareSafetyEvent {
        let velocityMmS = Int16((velocity * 1000).rounded())
        let depthMm = UInt16((depth * 1000).rounded())
        let criticalMm = UInt16((critical * 1000).rounded())

        var data = Data(count: 20)
        data.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: UInt32(9).littleEndian, toByteOffset: 0, as: UInt32.self)
            ptr.storeBytes(of: UInt32(1234).littleEndian, toByteOffset: 4, as: UInt32.self)
            ptr.storeBytes(of: state.rawValue, toByteOffset: 8, as: UInt8.self)
            ptr.storeBytes(of: cause.rawValue, toByteOffset: 9, as: UInt8.self)
            ptr.storeBytes(of: velocityMmS.littleEndian, toByteOffset: 12, as: Int16.self)
            ptr.storeBytes(of: depthMm.littleEndian, toByteOffset: 14, as: UInt16.self)
            ptr.storeBytes(of: criticalMm.littleEndian, toByteOffset: 16, as: UInt16.self)
            ptr.storeBytes(of: UInt16(abs(velocityMmS)).littleEndian, toByteOffset: 18, as: UInt16.self)
        }
        return try! FirmwareSafetyEvent(data: data)
    }

    func testBrakePresentationExplainsObstacleStop() {
        let event = makeEvent(state: .brake, cause: .obstacle, velocity: -0.7, depth: 0.34, critical: 0.58)
        let presentation = RearSafetyPresentation(
            event: event,
            receivedAt: Date(timeIntervalSince1970: 10),
            now: Date(timeIntervalSince1970: 12),
            currentSpeedMps: 0.18
        )

        XCTAssertEqual(presentation.title, "Rear Safety Brake")
        XCTAssertEqual(presentation.statusText, "BRAKE")
        XCTAssertTrue(presentation.detail.contains("Obstacle"))
        XCTAssertTrue(presentation.detail.contains("0.34"))
        XCTAssertTrue(presentation.detail.contains("0.58"))
        XCTAssertEqual(presentation.metricsLine, "Trig 0.34m  |  Dcrit 0.58m  |  v 0.70m/s")
        XCTAssertEqual(presentation.timingLine, "Brake 2.0s  |  Current 0.18m/s")
    }

    func testSafePresentationShowsRecovery() {
        let event = makeEvent(state: .safe, cause: .none, velocity: 0.0, depth: 0.0, critical: 0.0)
        let presentation = RearSafetyPresentation(
            event: event,
            receivedAt: Date(timeIntervalSince1970: 10),
            now: Date(timeIntervalSince1970: 12),
            currentSpeedMps: 0.0
        )

        XCTAssertEqual(presentation.title, "Rear Path Clear")
        XCTAssertEqual(presentation.statusText, "SAFE")
        XCTAssertTrue(presentation.detail.contains("Reverse path clear"))
        XCTAssertNil(presentation.timingLine)
    }
}
