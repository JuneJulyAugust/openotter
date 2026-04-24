import XCTest
@testable import openotter

final class SelfDrivingEmergencyAlertTests: XCTestCase {

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

    func testReverseBrakeCreatesSelfDrivingEmergencyAlert() {
        let rearPresentation = RearSafetyPresentation(
            event: makeEvent(state: .brake, cause: .obstacle, velocity: -0.7, depth: 0.34, critical: 0.58),
            receivedAt: Date(timeIntervalSince1970: 10),
            now: Date(timeIntervalSince1970: 12),
            currentSpeedMps: 0.18
        )

        let alert = SelfDrivingEmergencyAlert.current(
            forwardEvent: nil,
            forwardRecord: nil,
            rearPresentation: rearPresentation
        )

        XCTAssertEqual(alert?.title, "REAR EMERGENCY BRAKE")
        XCTAssertEqual(alert?.detail, rearPresentation.detail)
        XCTAssertEqual(alert?.metricsLine, rearPresentation.metricsLine)
        XCTAssertEqual(alert?.secondaryLine, rearPresentation.timingLine)
    }

    func testReverseBrakeTakesPriorityOverForwardBrake() {
        let rearPresentation = RearSafetyPresentation(
            event: makeEvent(state: .brake, cause: .obstacle),
            receivedAt: Date(timeIntervalSince1970: 10),
            now: Date(timeIntervalSince1970: 12),
            currentSpeedMps: 0.0
        )
        let pose = PoseEntry(timestamp: 1, x: 0, y: 0, z: 0, yaw: 0, confidence: 1)
        let trigger = SafetyBrakeTrigger(
            timestamp: 1.0,
            pose: pose,
            speed: 0.8,
            depth: 0.42,
            criticalDistance: 0.60,
            motorSpeed: 0.8,
            arkitSpeed: 0.7
        )
        let forwardEvent = SafetySupervisorEvent(
            timestamp: 1.0,
            rawDepth: 0.40,
            smoothedDepth: 0.42,
            speed: 0.8,
            criticalDistance: 0.60,
            isBraking: true,
            reason: "obstacle"
        )

        let alert = SelfDrivingEmergencyAlert.current(
            forwardEvent: forwardEvent,
            forwardRecord: SafetyBrakeRecord(trigger: trigger, stop: nil),
            rearPresentation: rearPresentation
        )

        XCTAssertEqual(alert?.title, "REAR EMERGENCY BRAKE")
    }
}
