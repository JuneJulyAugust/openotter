import XCTest
import Combine
import CoreBluetooth
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

    func testConnectedDebugViewReassertsDebugOncePerConnection() {
        XCTAssertTrue(STM32ControlViewModel.shouldReassertDebugOnConnection(
            status: .connected,
            firmwareMode: .debug,
            alreadyReasserted: false))
        XCTAssertFalse(STM32ControlViewModel.shouldReassertDebugOnConnection(
            status: .connected,
            firmwareMode: .debug,
            alreadyReasserted: true))
    }

    func testNonDebugOrDisconnectedStateDoesNotReassertDebug() {
        XCTAssertFalse(STM32ControlViewModel.shouldReassertDebugOnConnection(
            status: .connected,
            firmwareMode: .drive,
            alreadyReasserted: false))
        XCTAssertFalse(STM32ControlViewModel.shouldReassertDebugOnConnection(
            status: .scanning,
            firmwareMode: .debug,
            alreadyReasserted: false))
    }

    func testDiscoveryRejectsRememberedPeripheralWithoutFreshOpenOtterEvidence() {
        let id = UUID()

        XCTAssertFalse(STM32DiscoveryPolicy.isTargetPeripheral(
            cachedName: "BlueNRG",
            advertisedName: "",
            peripheralID: id,
            rememberedPeripheralID: id.uuidString))
    }

    func testDiscoveryAcceptsRememberedPeripheralWithFreshOpenOtterService() {
        let id = UUID()

        XCTAssertTrue(STM32DiscoveryPolicy.isTargetPeripheral(
            cachedName: "BlueNRG",
            advertisedName: "",
            peripheralID: id,
            rememberedPeripheralID: id.uuidString,
            advertisedServiceUUIDs: ["FE40"]))
    }

    func testDiscoveryRejectsUnnamedUnrememberedPeripheral() {
        XCTAssertFalse(STM32DiscoveryPolicy.isTargetPeripheral(
            cachedName: "BlueNRG",
            advertisedName: "",
            peripheralID: UUID(),
            rememberedPeripheralID: nil))
    }

    func testDiscoveryAcceptsAdvertisedOpenOtterServiceUUID() {
        XCTAssertTrue(STM32DiscoveryPolicy.isTargetPeripheral(
            cachedName: "BlueNRG",
            advertisedName: "",
            peripheralID: UUID(),
            rememberedPeripheralID: nil,
            advertisedServiceUUIDs: ["FE60"]))
    }

    func testDiscoveryAcceptsBlueNRGOnlyDuringManualFallback() {
        let id = UUID()

        XCTAssertFalse(STM32DiscoveryPolicy.isTargetPeripheral(
            cachedName: "BlueNRG",
            advertisedName: "",
            peripheralID: id,
            rememberedPeripheralID: nil,
            acceptBlueNRGFallback: false))
        XCTAssertTrue(STM32DiscoveryPolicy.isTargetPeripheral(
            cachedName: "BlueNRG",
            advertisedName: "",
            peripheralID: id,
            rememberedPeripheralID: nil,
            acceptBlueNRGFallback: true))
    }

    func testDiscoveryAcceptsAdvertisedOpenOtterName() {
        XCTAssertTrue(STM32DiscoveryPolicy.isTargetPeripheral(
            cachedName: "BlueNRG",
            advertisedName: "OPENOTTER-MCP",
            peripheralID: UUID(),
            rememberedPeripheralID: nil))
    }

    func testRefreshScanUsesDuplicateAdvertisements() {
        XCTAssertFalse(STM32DiscoveryPolicy.scanOptions(allowDuplicates: false).values.contains { value in
            (value as? Bool) == true
        })
        XCTAssertEqual(
            STM32DiscoveryPolicy.scanOptions(allowDuplicates: true)[CBCentralManagerScanOptionAllowDuplicatesKey] as? Bool,
            true)
    }

    func testManualRefreshUsesFreshCentral() {
        XCTAssertTrue(STM32DiscoveryPolicy.shouldResetCentralForManualReconnect())
    }

    func testRepeatedScanTimeoutUsesFreshCentral() {
        XCTAssertFalse(STM32DiscoveryPolicy.shouldResetCentralAfterScanTimeout(
            scanAttemptCount: 1,
            hasRememberedPeripheral: false))
        XCTAssertFalse(STM32DiscoveryPolicy.shouldResetCentralAfterScanTimeout(
            scanAttemptCount: 2,
            hasRememberedPeripheral: false))
        XCTAssertTrue(STM32DiscoveryPolicy.shouldResetCentralAfterScanTimeout(
            scanAttemptCount: 3,
            hasRememberedPeripheral: false))
        XCTAssertTrue(STM32DiscoveryPolicy.shouldResetCentralAfterScanTimeout(
            scanAttemptCount: 1,
            hasRememberedPeripheral: true))
    }

    func testScanTimeoutDoesNotBlindConnectRememberedPeripheral() {
        XCTAssertFalse(STM32DiscoveryPolicy.shouldTryRememberedPeripheralOnScanTimeout(
            hasRememberedPeripheral: true,
            status: .scanning))
        XCTAssertFalse(STM32DiscoveryPolicy.shouldTryRememberedPeripheralOnScanTimeout(
            hasRememberedPeripheral: false,
            status: .scanning))
        XCTAssertFalse(STM32DiscoveryPolicy.shouldTryRememberedPeripheralOnScanTimeout(
            hasRememberedPeripheral: true,
            status: .connected))
    }

    func testRememberedPeripheralFastPathIsDisabledAfterResetHardening() {
        XCTAssertFalse(STM32DiscoveryPolicy.shouldUseRememberedPeripheralFastPath())
    }

    func testConnectionTimeoutForRememberedPeripheralForgetsStaleID() {
        XCTAssertTrue(STM32DiscoveryPolicy.shouldForgetRememberedPeripheralAfterConnectionTimeout(
            timedOutPeripheralID: "2D5EB700-0000-0000-0000-000000000000",
            rememberedPeripheralID: "2D5EB700-0000-0000-0000-000000000000"))
        XCTAssertFalse(STM32DiscoveryPolicy.shouldForgetRememberedPeripheralAfterConnectionTimeout(
            timedOutPeripheralID: "2D5EB700-0000-0000-0000-000000000000",
            rememberedPeripheralID: "B0812F63-0000-0000-0000-000000000000"))
        XCTAssertFalse(STM32DiscoveryPolicy.shouldForgetRememberedPeripheralAfterConnectionTimeout(
            timedOutPeripheralID: nil,
            rememberedPeripheralID: "2D5EB700-0000-0000-0000-000000000000"))
    }

    func testUnexpectedDisconnectTimeoutForgetsRememberedPeripheral() {
        XCTAssertTrue(STM32DiscoveryPolicy.shouldForgetRememberedPeripheralAfterDisconnect(
            errorDescription: "Error Domain=CBErrorDomain Code=6 \"The connection has timed out unexpectedly.\""))
        XCTAssertTrue(STM32DiscoveryPolicy.shouldForgetRememberedPeripheralAfterDisconnect(
            errorDescription: "The connection has timed out unexpectedly."))
        XCTAssertFalse(STM32DiscoveryPolicy.shouldForgetRememberedPeripheralAfterDisconnect(
            errorDescription: nil))
        XCTAssertFalse(STM32DiscoveryPolicy.shouldForgetRememberedPeripheralAfterDisconnect(
            errorDescription: "Error Domain=CBErrorDomain Code=7 \"Peripheral disconnected\""))
    }

    func testCoreBluetoothCallbackGuardsRejectStaleObjects() {
        XCTAssertTrue(STM32DiscoveryPolicy.shouldAcceptCoreBluetoothCallback(isCurrentObject: true))
        XCTAssertFalse(STM32DiscoveryPolicy.shouldAcceptCoreBluetoothCallback(isCurrentObject: false))
    }

    func testBleDebugTraceKeepsRecentEvents() {
        var trace = STM32BleDebugTrace(limit: 3)

        XCTAssertEqual(trace.append("scan 1"), "scan 1")
        _ = trace.append("ignored MacBook")
        _ = trace.append("scan timeout")
        let text = trace.append("connect remembered")

        XCTAssertFalse(text.contains("scan 1"))
        XCTAssertTrue(text.contains("ignored MacBook"))
        XCTAssertTrue(text.contains("scan timeout"))
        XCTAssertTrue(text.contains("connect remembered"))
    }

    func testBleConsoleLogPolicyThrottlesIgnoredAdvertisementsOnly() {
        XCTAssertFalse(STM32BleConsoleLogPolicy.shouldLog(event: "ignored advertisement", sequence: 9))
        XCTAssertTrue(STM32BleConsoleLogPolicy.shouldLog(event: "ignored advertisement", sequence: 10))
        XCTAssertTrue(STM32BleConsoleLogPolicy.shouldLog(event: "matched advertisement", sequence: 11))
        XCTAssertTrue(STM32BleConsoleLogPolicy.shouldLog(event: "connect timeout", sequence: 12))
    }

    func testVL53L8CXConfigEncodesFE61V2() {
        let payload = STM32TofService.makeConfigPayload(
            sensor: .vl53l8cx,
            layout: 8,
            profile: 1,
            frequencyHz: 10,
            integrationMs: 20,
            budgetMs: 0,
            role: .rear
        )

        XCTAssertEqual([UInt8](payload), [2, 8, 1, 10, 20, 0, 0, 0, 0])
    }

    func testVL53L8CXConfigEncodesFrontDebugRole() {
        let payload = STM32TofService.makeConfigPayload(
            sensor: .vl53l8cx,
            layout: 4,
            profile: 1,
            frequencyHz: 30,
            integrationMs: 20,
            budgetMs: 0,
            role: .front
        )

        XCTAssertEqual([UInt8](payload), [2, 4, 1, 30, 20, 0, 0, 0, 1])
    }

    func testStatusPayloadDecodesSelectedRoleAndAvailableMask() {
        let service = STM32TofService()

        service.handleStatusNotification(Data([1, 0, 31, 0x31]))

        XCTAssertEqual(service.state, .running)
        XCTAssertEqual(service.scanHz, 31)
        XCTAssertEqual(service.selectedSensorRole, .front)
        XCTAssertEqual(service.availableSensorRoles, [.rear, .front])
    }

    func testStatusPayloadDecodesRearOnlyAvailability() {
        let service = STM32TofService()

        service.handleStatusNotification(Data([1, 0, 29, 0x10]))

        XCTAssertEqual(service.selectedSensorRole, .rear)
        XCTAssertEqual(service.availableSensorRoles, [.rear])
        XCTAssertFalse(service.availableSensorRoles.contains(.front))
    }

    func testStatusPayloadDecodesFrontSelectedButUnavailable() {
        let service = STM32TofService()

        service.handleStatusNotification(Data([1, 0, 0, 0x01]))

        XCTAssertEqual(service.selectedSensorRole, .front)
        XCTAssertTrue(service.availableSensorRoles.isEmpty)
    }

    func testConfigSentBeforeAttachIsRemembered() {
        let service = STM32TofService()

        service.sendConfig(sensor: .vl53l8cx,
                           layout: 8,
                           profile: 1,
                           frequencyHz: 1,
                           integrationMs: 100,
                           budgetMs: 0,
                           role: .front)

        XCTAssertEqual(service.preferredConfigForTesting.sensor, .vl53l8cx)
        XCTAssertEqual(service.preferredConfigForTesting.layout, 8)
        XCTAssertEqual(service.preferredConfigForTesting.frequencyHz, 1)
        XCTAssertEqual(service.preferredConfigForTesting.integrationMs, 100)
        XCTAssertEqual(service.preferredConfigForTesting.role, .front)
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

    func testTofConfigWaitsForBothNotificationAcks() {
        XCTAssertFalse(STM32TofStreamStartupPolicy.canWriteConfig(
            debugStreamingEnabled: true,
            hasPeripheral: true,
            hasConfigCharacteristic: true,
            frameNotificationsEnabled: false,
            statusNotificationsEnabled: true))
        XCTAssertFalse(STM32TofStreamStartupPolicy.canWriteConfig(
            debugStreamingEnabled: true,
            hasPeripheral: true,
            hasConfigCharacteristic: true,
            frameNotificationsEnabled: true,
            statusNotificationsEnabled: false))
        XCTAssertTrue(STM32TofStreamStartupPolicy.canWriteConfig(
            debugStreamingEnabled: true,
            hasPeripheral: true,
            hasConfigCharacteristic: true,
            frameNotificationsEnabled: true,
            statusNotificationsEnabled: true))
    }

    func testTofStartupDoesNotWriteConfigOutsideDebug() {
        XCTAssertFalse(STM32TofStreamStartupPolicy.canWriteConfig(
            debugStreamingEnabled: false,
            hasPeripheral: true,
            hasConfigCharacteristic: true,
            frameNotificationsEnabled: true,
            statusNotificationsEnabled: true))
    }

    func testTofStartupForcesReconnectWhenNotifyAckNeverArrives() {
        XCTAssertTrue(STM32TofStreamStartupPolicy.shouldForceReconnect(
            debugStreamingEnabled: true,
            attached: true,
            frameNotificationsEnabled: false,
            statusNotificationsEnabled: true,
            chunksAtActivation: 0,
            chunksNow: 0,
            statusAtActivation: 0,
            statusNow: 0,
            elapsedSeconds: STM32TofStreamStartupPolicy.notifyAckGraceSeconds + 0.1))
    }

    func testTofStartupForcesReconnectWhenStreamIsSilentAfterGrace() {
        XCTAssertTrue(STM32TofStreamStartupPolicy.shouldForceReconnect(
            debugStreamingEnabled: true,
            attached: true,
            frameNotificationsEnabled: true,
            statusNotificationsEnabled: true,
            chunksAtActivation: 4,
            chunksNow: 4,
            statusAtActivation: 1,
            statusNow: 1,
            elapsedSeconds: STM32TofStreamStartupPolicy.streamTrafficGraceSeconds + 0.1))
    }

    func testTofStartupKeepsConnectionWhenTrafficArrives() {
        XCTAssertFalse(STM32TofStreamStartupPolicy.shouldForceReconnect(
            debugStreamingEnabled: true,
            attached: true,
            frameNotificationsEnabled: true,
            statusNotificationsEnabled: true,
            chunksAtActivation: 4,
            chunksNow: 5,
            statusAtActivation: 1,
            statusNow: 1,
            elapsedSeconds: STM32TofStreamStartupPolicy.streamTrafficGraceSeconds + 0.1))
        XCTAssertFalse(STM32TofStreamStartupPolicy.shouldForceReconnect(
            debugStreamingEnabled: true,
            attached: true,
            frameNotificationsEnabled: true,
            statusNotificationsEnabled: true,
            chunksAtActivation: 4,
            chunksNow: 4,
            statusAtActivation: 1,
            statusNow: 2,
            elapsedSeconds: STM32TofStreamStartupPolicy.streamTrafficGraceSeconds + 0.1))
    }

    func testVL53L8CXValidFarRangeClassifiesAsClear() {
        XCTAssertEqual(ZoneReading(rangeMm: 4300,
                                   status: VL53L1RangeStatus(raw: 5),
                                   flags: 1).vl53l8cxClass,
                       .clear)
    }

    func testVL53L8CXNonOkFarRangeStaysInvalid() {
        XCTAssertEqual(ZoneReading(rangeMm: 4300,
                                   status: VL53L1RangeStatus(raw: 2),
                                   flags: 1).vl53l8cxClass,
                       .invalid)
        XCTAssertEqual(ZoneReading(rangeMm: 0,
                                   status: VL53L1RangeStatus(raw: 2),
                                   flags: 0).vl53l8cxClass,
                       .invalid)
    }

    func testVL53L8CXNearStatus2StaysInvalid() {
        XCTAssertEqual(ZoneReading(rangeMm: 1000,
                                   status: VL53L1RangeStatus(raw: 2),
                                   flags: 1).vl53l8cxClass,
                       .invalid)
    }

    func testParseV2FourByFourFrame() {
        let payload = makeV2Payload(layout: 4)
        let frame = STM32TofService.parseFrameV2(Data(payload))

        XCTAssertEqual(frame?.sensor, .vl53l8cx)
        XCTAssertEqual(frame?.layout, 4)
        XCTAssertEqual(frame?.numZones, 16)
        XCTAssertEqual(frame?.zones.count, 16)
        XCTAssertEqual(frame?.zones[0].rangeMm, 100)
        XCTAssertEqual(frame?.zones[15].rangeMm, 115)
    }

    func testParseV2EightByEightFrame() {
        let payload = makeV2Payload(layout: 8)
        let frame = STM32TofService.parseFrameV2(Data(payload))

        XCTAssertEqual(frame?.sensor, .vl53l8cx)
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
                XCTAssertEqual(frame.role, .rear)
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

    func testChangingRoleClearsStaleDepthFrame() {
        let service = STM32TofService()
        publishV2Frame(on: service, layout: 4, seqLow: 0x7A)
        XCTAssertNotNil(service.latestFrame)
        XCTAssertEqual(service.latestFrame?.role, .rear)

        let update = expectation(description: "stale frame cleared")
        service.$latestFrame
            .dropFirst()
            .sink { frame in
                if frame == nil { update.fulfill() }
            }
            .store(in: &cancellables)

        service.sendConfig(sensor: .vl53l8cx,
                           layout: 4,
                           profile: 1,
                           frequencyHz: 10,
                           integrationMs: 20,
                           budgetMs: 0,
                           role: .front)

        wait(for: [update], timeout: 1.0)
        XCTAssertNil(service.latestFrame)
        XCTAssertEqual(service.scanHz, 0)
        XCTAssertEqual(service.selectedSensorRole, .front)
    }

    func testInOrderV2ChunksPublishSelectedFrontRole() {
        let service = STM32TofService()
        let payload = makeV2Payload(layout: 4)
        let chunks = makeChunks(payload: payload, seqLow: 0x79)
        let update = expectation(description: "front frame update")

        service.handleStatusNotification(Data([1, 0, 30, 0x31]))
        service.$latestFrame
            .compactMap { $0 }
            .sink { frame in
                XCTAssertEqual(frame.role, .front)
                XCTAssertEqual(frame.layout, 4)
                update.fulfill()
            }
            .store(in: &cancellables)

        for chunk in chunks {
            service.handleFrameNotification(Data(chunk))
        }

        wait(for: [update], timeout: 1.0)
        XCTAssertEqual(service.droppedFrameChunks, 0)
    }

    private func publishV2Frame(on service: STM32TofService,
                                layout: UInt8,
                                seqLow: UInt8) {
        let payload = makeV2Payload(layout: layout)
        let chunks = makeChunks(payload: payload, seqLow: seqLow)
        let update = expectation(description: "frame update")

        service.$latestFrame
            .compactMap { $0 }
            .sink { _ in update.fulfill() }
            .store(in: &cancellables)

        for chunk in chunks {
            service.handleFrameNotification(Data(chunk))
        }

        wait(for: [update], timeout: 1.0)
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
