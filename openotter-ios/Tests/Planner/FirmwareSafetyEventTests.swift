import XCTest
@testable import openotter

final class FirmwareSafetyEventTests: XCTestCase {

    func testParsesBrakeObstaclePayload() throws {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 7                                       // seq = 7
        bytes[4] = 0x78; bytes[5] = 0x56                   // timestamp low
        bytes[6] = 0x34; bytes[7] = 0x12                   // timestamp high
        bytes[8] = 1                                       // state = BRAKE
        bytes[9] = 1                                       // cause = obstacle
        bytes[12] = 0x18; bytes[13] = 0xFC                 // velocity = -1000 mm/s
        bytes[14] = 0x2C; bytes[15] = 0x01                 // depth = 300 mm
        bytes[16] = 0x66; bytes[17] = 0x03                 // critical = 870 mm
        bytes[18] = 0xE8; bytes[19] = 0x03                 // latched = 1000 mm/s

        let event = try FirmwareSafetyEvent(data: Data(bytes))
        XCTAssertEqual(event.seq, 7)
        XCTAssertEqual(event.timestampMs, 0x12345678)
        XCTAssertEqual(event.state, .brake)
        XCTAssertEqual(event.cause, .obstacle)
        XCTAssertEqual(event.triggerVelocityMPS, -1.0, accuracy: 1e-3)
        XCTAssertEqual(event.triggerDepthM,       0.300, accuracy: 1e-3)
        XCTAssertEqual(event.criticalDistanceM,   0.870, accuracy: 1e-3)
        XCTAssertEqual(event.latchedSpeedMPS,     1.0,   accuracy: 1e-3)
    }

    func testRejectsShortPayload() {
        let data = Data(repeating: 0, count: 19)
        XCTAssertThrowsError(try FirmwareSafetyEvent(data: data))
    }

    func testMapsUnknownCauseToNone() throws {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[8] = 0
        bytes[9] = 42  // unknown cause -> defaults to .none
        let event = try FirmwareSafetyEvent(data: Data(bytes))
        XCTAssertEqual(event.cause, .none)
    }
}