import XCTest
import Combine
@testable import openotter

final class STM32TofServiceTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    func testDebugModeRefreshesTofConfig() {
        XCTAssertTrue(STM32ControlViewModel.shouldRefreshTofConfig(afterModeChangeTo: .debug))
    }

    func testDriveAndParkDoNotRefreshTofConfig() {
        XCTAssertFalse(STM32ControlViewModel.shouldRefreshTofConfig(afterModeChangeTo: .drive))
        XCTAssertFalse(STM32ControlViewModel.shouldRefreshTofConfig(afterModeChangeTo: .park))
    }

    func testVL53L5CXConfigEncodesFE61V2() {
        let payload = STM32TofService.makeConfigPayload(
            sensor: .vl53l5cx,
            layout: 8,
            profile: 1,
            frequencyHz: 10,
            integrationMs: 20,
            budgetMs: 0
        )

        XCTAssertEqual([UInt8](payload), [2, 8, 1, 10, 20, 0, 0, 0])
    }

    func testConfigSentBeforeAttachIsRemembered() {
        let service = STM32TofService()

        service.sendConfig(sensor: .vl53l5cx,
                           layout: 8,
                           profile: 1,
                           frequencyHz: 1,
                           integrationMs: 100,
                           budgetMs: 0)

        XCTAssertEqual(service.preferredConfigForTesting.sensor, .vl53l5cx)
        XCTAssertEqual(service.preferredConfigForTesting.layout, 8)
        XCTAssertEqual(service.preferredConfigForTesting.frequencyHz, 1)
        XCTAssertEqual(service.preferredConfigForTesting.integrationMs, 100)
    }

    func testDebugStreamingDefaultsDisabled() {
        let service = STM32TofService()

        XCTAssertFalse(service.debugStreamingEnabledForTesting)
    }

    func testDebugStreamingCanBeEnabledForControlView() {
        let service = STM32TofService()

        service.setDebugStreamingEnabled(true)

        XCTAssertTrue(service.debugStreamingEnabledForTesting)
    }

    func testVL53L5CXFarStatus2ClassifiesAsClear() {
        XCTAssertEqual(ZoneReading(rangeMm: 4300,
                                   status: VL53L1RangeStatus(raw: 2),
                                   flags: 1).vl53l5cxClass,
                       .clear)
        XCTAssertEqual(ZoneReading(rangeMm: 0,
                                   status: VL53L1RangeStatus(raw: 2),
                                   flags: 0).vl53l5cxClass,
                       .clear)
    }

    func testVL53L5CXNearStatus2StaysInvalid() {
        XCTAssertEqual(ZoneReading(rangeMm: 1000,
                                   status: VL53L1RangeStatus(raw: 2),
                                   flags: 1).vl53l5cxClass,
                       .invalid)
    }

    func testParseV2FourByFourFrame() {
        let payload = makeV2Payload(layout: 4)
        let frame = STM32TofService.parseFrameV2(Data(payload))

        XCTAssertEqual(frame?.sensor, .vl53l5cx)
        XCTAssertEqual(frame?.layout, 4)
        XCTAssertEqual(frame?.numZones, 16)
        XCTAssertEqual(frame?.zones.count, 16)
        XCTAssertEqual(frame?.zones[0].rangeMm, 100)
        XCTAssertEqual(frame?.zones[15].rangeMm, 115)
    }

    func testParseV2EightByEightFrame() {
        let payload = makeV2Payload(layout: 8)
        let frame = STM32TofService.parseFrameV2(Data(payload))

        XCTAssertEqual(frame?.sensor, .vl53l5cx)
        XCTAssertEqual(frame?.layout, 8)
        XCTAssertEqual(frame?.numZones, 64)
        XCTAssertEqual(frame?.zones.count, 64)
        XCTAssertEqual(frame?.zones[63].rangeMm, 163)
    }

    func testOutOfOrderV2ChunkIsDropped() {
        let service = STM32TofService()
        let payload = makeV2Payload(layout: 4)
        let chunks = makeChunks(payload: payload, seqLow: 0x78)
        let update = expectation(description: "no frame update")
        update.isInverted = true

        service.$latestFrame
            .dropFirst()
            .sink { _ in update.fulfill() }
            .store(in: &cancellables)

        service.handleFrameNotification(Data(chunks[1]))

        wait(for: [update], timeout: 0.2)
        XCTAssertNil(service.latestFrame)
        XCTAssertEqual(service.droppedFrameChunks, 1)
    }

    func testInOrderV2ChunksPublishFrame() {
        let service = STM32TofService()
        let payload = makeV2Payload(layout: 4)
        let chunks = makeChunks(payload: payload, seqLow: 0x78)
        let update = expectation(description: "frame update")

        service.$latestFrame
            .compactMap { $0 }
            .sink { frame in
                XCTAssertEqual(frame.layout, 4)
                XCTAssertEqual(frame.numZones, 16)
                update.fulfill()
            }
            .store(in: &cancellables)

        for chunk in chunks {
            service.handleFrameNotification(Data(chunk))
        }

        wait(for: [update], timeout: 1.0)
        XCTAssertEqual(service.droppedFrameChunks, 0)
    }

    private func makeV2Payload(layout: UInt8) -> [UInt8] {
        let zoneCount = Int(layout) * Int(layout)
        let len = UInt16(16 + zoneCount * 4)
        var bytes = [UInt8](repeating: 0, count: Int(len))
        bytes[0] = 2
        bytes[1] = 2
        bytes[2] = layout
        bytes[3] = UInt8(zoneCount)
        put32(0x12345678, into: &bytes, at: 4)
        put32(0x01020304, into: &bytes, at: 8)
        put16(len, into: &bytes, at: 12)
        bytes[14] = 1
        bytes[15] = 0
        for i in 0..<zoneCount {
            let offset = 16 + i * 4
            put16(UInt16(100 + i), into: &bytes, at: offset)
            bytes[offset + 2] = UInt8(i & 0xFF)
            bytes[offset + 3] = 0x80
        }
        return bytes
    }

    private func makeChunks(payload: [UInt8], seqLow: UInt8) -> [[UInt8]] {
        let chunkData = 18
        let count = (payload.count + chunkData - 1) / chunkData
        return (0..<count).map { idx in
            var chunk = [UInt8](repeating: 0, count: 20)
            chunk[0] = UInt8(idx)
            if idx == count - 1 { chunk[0] |= 0x80 }
            chunk[1] = seqLow
            let start = idx * chunkData
            let n = min(chunkData, payload.count - start)
            for i in 0..<n {
                chunk[2 + i] = payload[start + i]
            }
            return chunk
        }
    }

    private func put16(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8(value >> 8)
    }

    private func put32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}
