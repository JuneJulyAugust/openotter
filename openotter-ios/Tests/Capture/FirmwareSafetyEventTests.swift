import XCTest
@testable import openotter

/// Tests the 20-byte 0xFE43 Safety payload parser.
final class FirmwareSafetyEventTests: XCTestCase {

    // MARK: - Helpers

    private func makePayload(
        seq: UInt32 = 0,
        timestampMs: UInt32 = 0,
        state: UInt8 = 0,
        cause: UInt8 = 0,
        velocityMmS: Int16 = 0,
        depthMm: UInt16 = 0,
        criticalMm: UInt16 = 0,
        latchedMmS: UInt16 = 0
    ) -> Data {
        var data = Data(count: 20)
        data.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: seq.littleEndian,        toByteOffset:  0, as: UInt32.self)
            ptr.storeBytes(of: timestampMs.littleEndian, toByteOffset: 4, as: UInt32.self)
            ptr.storeBytes(of: state,                   toByteOffset:  8, as: UInt8.self)
            ptr.storeBytes(of: cause,                   toByteOffset:  9, as: UInt8.self)
            // bytes 10-11: padding (zero-initialized)
            ptr.storeBytes(of: velocityMmS.littleEndian, toByteOffset: 12, as: Int16.self)
            ptr.storeBytes(of: depthMm.littleEndian,     toByteOffset: 14, as: UInt16.self)
            ptr.storeBytes(of: criticalMm.littleEndian,  toByteOffset: 16, as: UInt16.self)
            ptr.storeBytes(of: latchedMmS.littleEndian,  toByteOffset: 18, as: UInt16.self)
        }
        return data
    }

    // MARK: - Rejection tests

    func testRejectsTruncatedPayload() {
        XCTAssertNil(FirmwareSafetyEvent.parse(from: Data(count: 19)))
        XCTAssertNil(FirmwareSafetyEvent.parse(from: Data()))
    }

    func testAcceptsExactly20Bytes() {
        XCTAssertNotNil(FirmwareSafetyEvent.parse(from: makePayload()))
    }

    func testAcceptsMoreThan20Bytes() {
        var extra = makePayload()
        extra.append(contentsOf: [0xFF, 0xFF])
        XCTAssertNotNil(FirmwareSafetyEvent.parse(from: extra))
    }

    // MARK: - Field parsing

    func testSequenceNumber() {
        let data = makePayload(seq: 42)
        let event = FirmwareSafetyEvent.parse(from: data)!
        XCTAssertEqual(event.seq, 42)
    }

    func testTimestamp() {
        let data = makePayload(timestampMs: 123_456)
        let event = FirmwareSafetyEvent.parse(from: data)!
        XCTAssertEqual(event.timestampMs, 123_456)
    }

    func testStateSafe() {
        let event = FirmwareSafetyEvent.parse(from: makePayload(state: 0))!
        XCTAssertEqual(event.state, .safe)
    }

    func testStateBrake() {
        let event = FirmwareSafetyEvent.parse(from: makePayload(state: 1))!
        XCTAssertEqual(event.state, .brake)
    }

    func testStateUnknown() {
        let event = FirmwareSafetyEvent.parse(from: makePayload(state: 99))!
        XCTAssertEqual(event.state, .unknown)
    }

    func testCauseObstacle() {
        let event = FirmwareSafetyEvent.parse(from: makePayload(state: 1, cause: 1))!
        XCTAssertEqual(event.cause, .obstacle)
    }

    func testCauseTofBlind() {
        let event = FirmwareSafetyEvent.parse(from: makePayload(state: 1, cause: 2))!
        XCTAssertEqual(event.cause, .tofBlind)
    }

    func testCauseFrameGap() {
        let event = FirmwareSafetyEvent.parse(from: makePayload(state: 1, cause: 3))!
        XCTAssertEqual(event.cause, .frameGap)
    }

    func testCauseDriverDead() {
        let event = FirmwareSafetyEvent.parse(from: makePayload(state: 1, cause: 4))!
        XCTAssertEqual(event.cause, .driverDead)
    }

    // MARK: - Unit conversion

    func testTriggerVelocityNegative() {
        // -500 mm/s → -0.5 m/s
        let data = makePayload(velocityMmS: -500)
        let event = FirmwareSafetyEvent.parse(from: data)!
        XCTAssertEqual(event.triggerVelocityMps, -0.5, accuracy: 1e-4)
    }

    func testTriggerDepth() {
        // 870 mm → 0.87 m
        let data = makePayload(depthMm: 870)
        let event = FirmwareSafetyEvent.parse(from: data)!
        XCTAssertEqual(event.triggerDepthM, 0.870, accuracy: 1e-4)
    }

    func testCriticalDistance() {
        // 450 mm → 0.45 m
        let data = makePayload(criticalMm: 450)
        let event = FirmwareSafetyEvent.parse(from: data)!
        XCTAssertEqual(event.criticalDistanceM, 0.45, accuracy: 1e-4)
    }

    func testLatchedSpeed() {
        // 1000 mm/s → 1.0 m/s
        let data = makePayload(latchedMmS: 1000)
        let event = FirmwareSafetyEvent.parse(from: data)!
        XCTAssertEqual(event.latchedSpeedMps, 1.0, accuracy: 1e-4)
    }

    // MARK: - Known brake snapshot

    func testKnownBrakeSnapshot() {
        // Craft a 20-byte packet as the firmware would emit for an obstacle brake:
        //   seq=3, timestamp=5000ms, state=BRAKE, cause=obstacle,
        //   velocity=-500mm/s, depth=300mm, critical=473mm, latched=500mm/s
        let data = makePayload(
            seq: 3,
            timestampMs: 5000,
            state: 1,
            cause: 1,
            velocityMmS: -500,
            depthMm: 300,
            criticalMm: 473,
            latchedMmS: 500
        )
        let event = FirmwareSafetyEvent.parse(from: data)!
        XCTAssertEqual(event.seq, 3)
        XCTAssertEqual(event.timestampMs, 5000)
        XCTAssertEqual(event.state, .brake)
        XCTAssertEqual(event.cause, .obstacle)
        XCTAssertEqual(event.triggerVelocityMps, -0.5, accuracy: 1e-4)
        XCTAssertEqual(event.triggerDepthM, 0.3, accuracy: 1e-4)
        XCTAssertEqual(event.criticalDistanceM, 0.473, accuracy: 1e-4)
        XCTAssertEqual(event.latchedSpeedMps, 0.5, accuracy: 1e-4)
    }
}
