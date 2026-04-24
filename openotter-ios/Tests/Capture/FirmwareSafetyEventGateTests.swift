import XCTest
@testable import openotter

final class FirmwareSafetyEventGateTests: XCTestCase {

    private func makeEvent(seq: UInt32 = 1, state: FirmwareSafetyState) -> FirmwareSafetyEvent {
        var data = Data(count: 20)
        data.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: seq.littleEndian, toByteOffset: 0, as: UInt32.self)
            ptr.storeBytes(of: UInt32(100).littleEndian, toByteOffset: 4, as: UInt32.self)
            ptr.storeBytes(of: state.rawValue, toByteOffset: 8, as: UInt8.self)
            ptr.storeBytes(of: FirmwareSafetyCause.obstacle.rawValue, toByteOffset: 9, as: UInt8.self)
            ptr.storeBytes(of: Int16(-400).littleEndian, toByteOffset: 12, as: Int16.self)
            ptr.storeBytes(of: UInt16(300).littleEndian, toByteOffset: 14, as: UInt16.self)
            ptr.storeBytes(of: UInt16(500).littleEndian, toByteOffset: 16, as: UInt16.self)
            ptr.storeBytes(of: UInt16(400).littleEndian, toByteOffset: 18, as: UInt16.self)
        }
        return try! FirmwareSafetyEvent(data: data)
    }

    func testParkClearsCachedBrakeAndDropsLateBrakeEvents() {
        var gate = FirmwareSafetyEventGate()
        XCTAssertEqual(gate.ingest(makeEvent(state: .brake))?.state, .brake)

        XCTAssertNil(gate.setOperatingMode(.park))
        XCTAssertNil(gate.lastSafetyEvent)
        XCTAssertNil(gate.ingest(makeEvent(seq: 2, state: .brake)))
        XCTAssertNil(gate.lastSafetyEvent)
    }

    func testDriveAcceptsBrakeAfterPark() {
        var gate = FirmwareSafetyEventGate()
        _ = gate.setOperatingMode(.park)
        XCTAssertNil(gate.ingest(makeEvent(seq: 1, state: .brake)))

        _ = gate.setOperatingMode(.drive)

        XCTAssertEqual(gate.ingest(makeEvent(seq: 2, state: .brake))?.state, .brake)
        XCTAssertEqual(gate.lastSafetyEvent?.state, .brake)
    }
}
