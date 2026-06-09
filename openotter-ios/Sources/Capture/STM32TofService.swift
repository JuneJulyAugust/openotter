import Foundation
import CoreBluetooth
import Combine

struct STM32TofStreamStartupPolicy {
    static let notifyAckGraceSeconds: TimeInterval = 5.0
    static let streamTrafficGraceSeconds: TimeInterval = 12.0

    static func canWriteConfig(debugStreamingEnabled: Bool,
                               hasPeripheral: Bool,
                               hasConfigCharacteristic: Bool,
                               frameNotificationsEnabled: Bool,
                               statusNotificationsEnabled: Bool) -> Bool {
        debugStreamingEnabled &&
        hasPeripheral &&
        hasConfigCharacteristic &&
        frameNotificationsEnabled &&
        statusNotificationsEnabled
    }

    static func shouldForceReconnect(debugStreamingEnabled: Bool,
                                     attached: Bool,
                                     frameNotificationsEnabled: Bool,
                                     statusNotificationsEnabled: Bool,
                                     chunksAtActivation: UInt32,
                                     chunksNow: UInt32,
                                     statusAtActivation: UInt32,
                                     statusNow: UInt32,
                                     elapsedSeconds: TimeInterval) -> Bool {
        guard debugStreamingEnabled, attached else { return false }
        if elapsedSeconds >= notifyAckGraceSeconds &&
            (!frameNotificationsEnabled || !statusNotificationsEnabled) {
            return true
        }
        if elapsedSeconds >= streamTrafficGraceSeconds &&
            chunksNow == chunksAtActivation &&
            statusNow == statusAtActivation {
            return true
        }
        return false
    }
}

/// Decodes the FE62 frame stream from OPENOTTER-MCP and exposes the latest
/// frame plus a derived scan rate to SwiftUI.
///
/// Frame wire format authority:
///   firmware/stm32-mcp/Core/Inc/tof_frame_codec.h
///   firmware/stm32-mcp/Core/Inc/tof_types.h
///
/// Status payload authority:
///   firmware/stm32-mcp/Core/Inc/ble_tof.h (BLE_TofStatusPayload_t, 4 B)
public final class STM32TofService: NSObject, ObservableObject {

    public static let shared = STM32TofService()

    @Published public private(set) var latestFrame: TofFrame?
    @Published public private(set) var state: TofState = .unknown
    @Published public private(set) var lastError: UInt8 = 0
    @Published public private(set) var scanHz: UInt8 = 0
    @Published public private(set) var selectedSensorRole: TofSensorRole = .rear
    @Published public private(set) var availableSensorRoles: Set<TofSensorRole> = []
    @Published public private(set) var droppedFrameChunks: UInt32 = 0
    @Published public private(set) var framesParsed: UInt32 = 0
    @Published public private(set) var chunksReceived: UInt32 = 0
    @Published public private(set) var debugSummary: String = "ToF BLE idle"

    private weak var peripheral: CBPeripheral?
    private weak var frameChar: CBCharacteristic?
    private weak var configChar: CBCharacteristic?
    private weak var statusChar: CBCharacteristic?
    private var debugStreamingEnabled = false
    private var frameNotificationsEnabled = false
    private var statusNotificationsEnabled = false
    private var statusNotificationsReceived: UInt32 = 0
    private var configWritesQueued: UInt32 = 0
    private var configWriteAcks: UInt32 = 0
    private var streamWatchdogGeneration: UInt64 = 0
    private var streamWatchdog: DispatchWorkItem?
    public var onStreamStale: ((String) -> Void)?
    private var preferredConfig = TofConfig(sensor: .vl53l8cx,
                                            layout: 4,
                                            distMode: 1,
                                            budgetUs: 0,
                                            frequencyHz: 10,
                                            integrationMs: 20,
                                            role: .rear)
    var preferredConfigForTesting: TofConfig { preferredConfig }
    var debugStreamingEnabledForTesting: Bool { debugStreamingEnabled }
    var frameNotificationsEnabledForTesting: Bool { frameNotificationsEnabled }
    var statusNotificationsEnabledForTesting: Bool { statusNotificationsEnabled }

    public override init() { super.init() }

    /// Wire characteristics discovered by STM32BleManager into the service.
    public func attach(peripheral: CBPeripheral,
                       frameChar: CBCharacteristic,
                       configChar: CBCharacteristic,
                       statusChar: CBCharacteristic) {
        self.peripheral = peripheral
        self.frameChar = frameChar
        self.configChar = configChar
        self.statusChar = statusChar
        frameNotificationsEnabled = false
        statusNotificationsEnabled = false
        resetFrameReassembly()
        updateDebug("attached", detail: readinessSummary)

        applyDebugStreamingState()
    }

    /// Drop characteristic refs on disconnect so we don't write to a dead session.
    public func detach() {
        cancelStreamWatchdog()
        peripheral = nil
        frameChar = nil
        configChar = nil
        statusChar = nil
        frameNotificationsEnabled = false
        statusNotificationsEnabled = false
        statusNotificationsReceived = 0
        configWritesQueued = 0
        configWriteAcks = 0
        resetFrameReassembly()
        updateOnMain {
            self.latestFrame = nil
            self.state = .unknown
            self.lastError = 0
            self.scanHz = 0
            self.selectedSensorRole = .rear
            self.availableSensorRoles = []
            self.droppedFrameChunks = 0
            self.framesParsed = 0
            self.chunksReceived = 0
            self.debugSummary = "ToF BLE detached"
        }
    }

    public func setDebugStreamingEnabled(_ enabled: Bool) {
        debugStreamingEnabled = enabled
        updateDebug(enabled ? "debug stream requested" : "debug stream stopped",
                    detail: readinessSummary)
        if !enabled {
            cancelStreamWatchdog()
        }
        applyDebugStreamingState()
    }

    /// Send an 8-byte FE61 config write.
    public func sendConfig(layout: UInt8, distMode: UInt8, budgetUs: UInt32) {
        let budgetMs = UInt16(min(UInt32(UInt16.max), budgetUs / 1000))
        sendConfig(sensor: preferredConfig.sensor,
                   layout: layout,
                   profile: distMode,
                   frequencyHz: preferredConfig.frequencyHz,
                   integrationMs: preferredConfig.integrationMs,
                   budgetMs: budgetMs,
                   role: preferredConfig.role)
    }

    public func sendConfig(sensor: TofSensorType,
                           layout: UInt8,
                           profile: UInt8,
                           frequencyHz: UInt8,
                           integrationMs: UInt16,
                           budgetMs: UInt16,
                           role: TofSensorRole) {
        let previousRole = preferredConfig.role
        preferredConfig = TofConfig(sensor: sensor,
                                    layout: layout,
                                    distMode: profile,
                                    budgetUs: UInt32(budgetMs) * 1000,
                                    frequencyHz: frequencyHz,
                                    integrationMs: integrationMs,
                                    role: role)
        if previousRole != role {
            resetFrameReassembly()
            updateOnMain {
                self.latestFrame = nil
                self.scanHz = 0
                self.selectedSensorRole = role
            }
        }
        writePreferredConfig(reason: "user config", force: true)
    }

    private func writePreferredConfig(reason: String, force: Bool = false) {
        guard STM32TofStreamStartupPolicy.canWriteConfig(
            debugStreamingEnabled: debugStreamingEnabled,
            hasPeripheral: peripheral != nil,
            hasConfigCharacteristic: configChar != nil,
            frameNotificationsEnabled: frameNotificationsEnabled,
            statusNotificationsEnabled: statusNotificationsEnabled
        ) else {
            updateDebug("waiting to write FE61", detail: "\(reason)\n\(readinessSummary)")
            if debugStreamingEnabled { scheduleStreamWatchdog(reason: "waiting FE61") }
            return
        }
        guard let peripheral, let configChar else { return }

        let payload = Self.makeConfigPayload(
            sensor: preferredConfig.sensor,
            layout: preferredConfig.layout,
            profile: preferredConfig.distMode,
            frequencyHz: preferredConfig.frequencyHz,
            integrationMs: preferredConfig.integrationMs,
            budgetMs: UInt16(min(UInt32(UInt16.max), preferredConfig.budgetUs / 1000)),
            role: preferredConfig.role
        )

        let writeType: CBCharacteristicWriteType =
            configChar.properties.contains(.write) ? .withResponse : .withoutResponse
        configWritesQueued &+= 1
        updateDebug("write FE61 \(configWritesQueued)",
                    detail: "\(reason)\n\(readinessSummary)")
        peripheral.writeValue(payload, for: configChar, type: writeType)
        if writeType == .withoutResponse {
            configWriteAcks &+= 1
        }
        scheduleStreamWatchdog(reason: force ? "forced FE61" : "FE61")
    }

    private func applyDebugStreamingState() {
        guard let peripheral else { return }
        let frameProps = frameChar?.properties.rawValue ?? 0
        let statusProps = statusChar?.properties.rawValue ?? 0
        let configProps = configChar?.properties.rawValue ?? 0
        NSLog("[TOF] applyDebugStreamingState enabled=\(debugStreamingEnabled) "
              + "frameProps=0x\(String(frameProps, radix: 16)) "
              + "statusProps=0x\(String(statusProps, radix: 16)) "
              + "configProps=0x\(String(configProps, radix: 16))")
        if let frameChar, frameChar.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: frameChar)
            frameNotificationsEnabled = frameChar.isNotifying
            NSLog("[TOF] setNotifyValue(true) requested for FE62 frame")
        } else {
            NSLog("[TOF] FE62 frame char missing or lacks .notify")
        }
        if let statusChar, statusChar.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: statusChar)
            statusNotificationsEnabled = statusChar.isNotifying
            NSLog("[TOF] setNotifyValue(true) requested for FE63 status")
        } else {
            NSLog("[TOF] FE63 status char missing or lacks .notify")
        }
        if debugStreamingEnabled {
            writePreferredConfig(reason: "apply stream state")
        }
    }

    public func handleNotificationState(_ characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == frameChar?.uuid {
            frameNotificationsEnabled = error == nil && characteristic.isNotifying
            updateDebug("FE62 notify \(frameNotificationsEnabled ? "on" : "off")",
                        detail: error.map { "\($0)" } ?? readinessSummary)
        } else if characteristic.uuid == statusChar?.uuid {
            statusNotificationsEnabled = error == nil && characteristic.isNotifying
            updateDebug("FE63 notify \(statusNotificationsEnabled ? "on" : "off")",
                        detail: error.map { "\($0)" } ?? readinessSummary)
        }
        if debugStreamingEnabled {
            writePreferredConfig(reason: "notify ack")
        }
    }

    public func handleConfigWriteAck(error: Error?) {
        if error == nil {
            configWriteAcks &+= 1
        }
        updateDebug(error == nil ? "FE61 write ack" : "FE61 write failed",
                    detail: error.map { "\($0)" } ?? readinessSummary)
    }

    public static func makeConfigPayload(sensor: TofSensorType,
                                         layout: UInt8,
                                         profile: UInt8,
                                         frequencyHz: UInt8,
                                         integrationMs: UInt16,
                                         budgetMs: UInt16,
                                         role: TofSensorRole) -> Data {
        var payload = Data(count: 9)
        payload.withUnsafeMutableBytes { raw in
            let p = raw.baseAddress!
            p.storeBytes(of: sensor.rawValue, toByteOffset: 0, as: UInt8.self)
            p.storeBytes(of: layout, toByteOffset: 1, as: UInt8.self)
            p.storeBytes(of: profile, toByteOffset: 2, as: UInt8.self)
            p.storeBytes(of: frequencyHz, toByteOffset: 3, as: UInt8.self)
            p.storeBytes(of: integrationMs.littleEndian, toByteOffset: 4, as: UInt16.self)
            p.storeBytes(of: budgetMs.littleEndian, toByteOffset: 6, as: UInt16.self)
            p.storeBytes(of: role.rawValue, toByteOffset: 8, as: UInt8.self)
        }
        return payload
    }

    /// Reassembly buffer for the FE62 chunk stream. BlueNRG-MS is locked to
    /// ATT_MTU=23, capping a notify PDU at 20 B. The 76-byte TofL1_Frame_t
    /// arrives as 4 chunks: 1 header byte (idx in low 7 bits, 0x80 = last)
    /// + 19 payload bytes. We parse only after the chunk with the last bit.
    private var rxBuf = [UInt8](repeating: 0, count: 76)
    private var rxNext: UInt8 = 0
    /// V2 reassembly buffer. Must be chunk-aligned: ceil(maxPayload / 18) × 18.
    /// Max payload is 272 bytes (8×8 = 64 zones); ceil(272/18)=16 chunks × 18 = 288.
    private var rxV2Buf = [UInt8](repeating: 0, count: 288)
    private var rxV2Next: UInt8 = 0
    private var rxV2SeqLow: UInt8 = 0
    private var rxMode: RxMode = .unknown

    private enum RxMode {
        case unknown
        case v1
        case v2
    }

    private func resetFrameReassembly() {
        rxNext = 0
        rxV2Next = 0
        rxV2SeqLow = 0
        rxMode = .unknown
    }

    private var readinessSummary: String {
        let attached = peripheral != nil && frameChar != nil && configChar != nil && statusChar != nil
        return [
            "attached \(attached ? "yes" : "no") debug \(debugStreamingEnabled ? "on" : "off")",
            "notify FE62 \(frameNotificationsEnabled ? "on" : "off") FE63 \(statusNotificationsEnabled ? "on" : "off")",
            "cfg writes \(configWritesQueued) ack \(configWriteAcks)",
            "rx chunks \(chunksReceived) frames \(framesParsed) status \(statusNotificationsReceived)"
        ].joined(separator: "\n")
    }

    private func updateDebug(_ event: String, detail: String = "") {
        let text = ([event] + detail.split(separator: "\n").map(String.init))
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        updateOnMain {
            self.debugSummary = text
        }
    }

    private func cancelStreamWatchdog() {
        streamWatchdogGeneration &+= 1
        streamWatchdog?.cancel()
        streamWatchdog = nil
    }

    private func scheduleStreamWatchdog(reason: String) {
        guard debugStreamingEnabled, peripheral != nil else { return }
        streamWatchdogGeneration &+= 1
        let generation = streamWatchdogGeneration
        let startedAt = Date()
        let chunksAtActivation = chunksReceived
        let statusAtActivation = statusNotificationsReceived

        streamWatchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.evaluateStreamWatchdog(generation: generation,
                                         startedAt: startedAt,
                                         chunksAtActivation: chunksAtActivation,
                                         statusAtActivation: statusAtActivation,
                                         reason: reason)
        }
        streamWatchdog = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + STM32TofStreamStartupPolicy.streamTrafficGraceSeconds,
            execute: item)
    }

    private func evaluateStreamWatchdog(generation: UInt64,
                                        startedAt: Date,
                                        chunksAtActivation: UInt32,
                                        statusAtActivation: UInt32,
                                        reason: String) {
        guard generation == streamWatchdogGeneration else { return }
        let attached = peripheral != nil && frameChar != nil && configChar != nil && statusChar != nil
        let elapsed = Date().timeIntervalSince(startedAt)
        if STM32TofStreamStartupPolicy.shouldForceReconnect(
            debugStreamingEnabled: debugStreamingEnabled,
            attached: attached,
            frameNotificationsEnabled: frameNotificationsEnabled,
            statusNotificationsEnabled: statusNotificationsEnabled,
            chunksAtActivation: chunksAtActivation,
            chunksNow: chunksReceived,
            statusAtActivation: statusAtActivation,
            statusNow: statusNotificationsReceived,
            elapsedSeconds: elapsed
        ) {
            let detail = "\(reason)\n\(readinessSummary)"
            updateDebug("ToF stream stale", detail: detail)
            onStreamStale?(detail)
            return
        }

        if debugStreamingEnabled && attached && chunksReceived == chunksAtActivation {
            writePreferredConfig(reason: "watchdog retry", force: true)
        }
    }

    private func updateOnMain(_ update: @escaping () -> Void) {
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    public func handleFrameNotification(_ data: Data) {
        guard data.count >= 2 else { return }
        chunksReceived &+= 1
        if chunksReceived == 1 {
            updateDebug("FE62 first chunk", detail: readinessSummary)
        }
        if chunksReceived <= 3 || chunksReceived & 0x3F == 0 {
            NSLog("[TOF] FE62 chunk #\(chunksReceived) len=\(data.count) "
                  + "hdr=0x\(String(data[0], radix: 16)) seqLow=0x\(String(data[1], radix: 16))")
        }
        var bytes = [UInt8](data)
        if bytes.count < 20 {
            bytes.append(contentsOf: [UInt8](repeating: 0, count: 20 - bytes.count))
        }
        let hdr   = bytes[0]
        let idx   = hdr & 0x7F
        let last  = (hdr & 0x80) != 0

        if idx == 0 && bytes[2] == 2 {
            rxMode = .v2
            rxV2Next = 0
            rxV2SeqLow = bytes[1]
        } else if idx == 0 {
            rxMode = .v1
        }

        if rxMode == .v2 {
            handleV2Chunk(bytes: bytes, idx: idx, last: last)
            return
        }

        // Restart on chunk 0; otherwise enforce in-order delivery.
        if idx == 0 {
            rxNext = 0
        }
        guard idx == rxNext, idx < 4 else {
            rxNext = 0
            droppedFrameChunks += 1
            return
        }

        let dst = Int(idx) * 19
        for i in 0..<19 { rxBuf[dst + i] = bytes[1 + i] }
        rxNext &+= 1

        if last {
            if let frame = STM32TofService.parseFrame(Data(rxBuf)) {
                let taggedFrame = frame.tagged(role: selectedSensorRole)
                framesParsed &+= 1
                updateOnMain {
                    self.latestFrame = taggedFrame
                }
            }
            rxNext = 0
        }
    }

    private func handleV2Chunk(bytes: [UInt8], idx: UInt8, last: Bool) {
        guard idx == rxV2Next, bytes[1] == rxV2SeqLow else {
            rxV2Next = 0
            rxMode = .unknown
            droppedFrameChunks += 1
            return
        }

        let dst = Int(idx) * 18
        let bytesToCopy = min(18, rxV2Buf.count - dst)
        guard bytesToCopy > 0 else {
            rxV2Next = 0
            rxMode = .unknown
            droppedFrameChunks += 1
            return
        }

        for i in 0..<bytesToCopy { rxV2Buf[dst + i] = bytes[2 + i] }
        rxV2Next &+= 1

        if last {
            let copied = dst + bytesToCopy
            let frameLen: Int
            if copied >= 14 {
                frameLen = Int(UInt16(rxV2Buf[12]) | (UInt16(rxV2Buf[13]) << 8))
            } else {
                frameLen = copied
            }
            if frameLen <= copied,
               let frame = Self.parseFrameV2(Data(rxV2Buf.prefix(frameLen))) {
                let taggedFrame = frame.tagged(role: selectedSensorRole)
                framesParsed &+= 1
                updateOnMain {
                    self.latestFrame = taggedFrame
                }
            } else {
                droppedFrameChunks += 1
            }
            rxV2Next = 0
            rxMode = .unknown
        }
    }

    public func handleStatusNotification(_ data: Data) {
        guard data.count >= 4 else { return }
        statusNotificationsReceived &+= 1
        let bytes = [UInt8](data)
        let role = TofSensorRole(raw: bytes[3] & 0x03)
        let available = Self.decodeAvailableRoles(mask: (bytes[3] >> 4) & 0x03)
        if statusNotificationsReceived == 1 {
            updateDebug("FE63 first status", detail: readinessSummary)
        }
        updateOnMain {
            self.state     = TofState(raw: bytes[0])
            self.lastError = bytes[1]
            self.scanHz    = bytes[2]
            self.selectedSensorRole = role
            self.availableSensorRoles = available
        }
    }

    private static func decodeAvailableRoles(mask: UInt8) -> Set<TofSensorRole> {
        var roles = Set<TofSensorRole>()
        if (mask & 0x01) != 0 { roles.insert(.rear) }
        if (mask & 0x02) != 0 { roles.insert(.front) }
        return roles
    }

    // MARK: - Pure parser (testable)

    /// Decode 76 B little-endian wire payload into TofFrame, or nil if invalid.
    public static func parseFrame(_ data: Data) -> TofFrame? {
        guard data.count == 76 else { return nil }
        let bytes = [UInt8](data)

        func u16(_ offset: Int) -> UInt16 {
            UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
        }

        let seq             = u32(0)
        let budgetUsPerZone = u16(4)
        let layout          = bytes[6]
        let distMode        = bytes[7]
        let numZones        = bytes[8]
        // bytes[9..11] = padding
        // zones start at offset 12: 16 × 4 B

        guard layout == 1 || layout == 3 || layout == 4 else { return nil }
        guard numZones <= 16, Int(numZones) == Int(layout) * Int(layout) else { return nil }

        var zones: [ZoneReading] = []
        zones.reserveCapacity(Int(numZones))
        for i in 0..<Int(numZones) {
            let base = 12 + i * 4
            let r = u16(base)
            let s = bytes[base + 2]
            zones.append(ZoneReading(rangeMm: r, status: VL53L1RangeStatus(raw: s)))
        }

        return TofFrame(sensor: .vl53l1cb,
                        seq: seq,
                        budgetUsPerZone: budgetUsPerZone,
                        layout: layout,
                        distMode: distMode,
                        numZones: numZones,
                        zones: zones)
    }

    /// Decode V2 variable-length payload. Wire format authority:
    /// `firmware/stm32-mcp/Core/Inc/tof_frame_codec.h`.
    public static func parseFrameV2(_ data: Data) -> TofFrame? {
        guard data.count >= 16 else { return nil }
        let bytes = [UInt8](data)

        func u16(_ offset: Int) -> UInt16 {
            UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
        }

        guard bytes[0] == 2 else { return nil }
        let sensor = TofSensorType(raw: bytes[1])
        let layout = bytes[2]
        let zoneCount = bytes[3]
        let seq = u32(4)
        let frameLen = Int(u16(12))
        let profile = bytes[14]

        guard sensor != .unknown, sensor != .none else { return nil }
        guard layout == 1 || layout == 3 || layout == 4 || layout == 8 else { return nil }
        guard zoneCount <= 64, Int(zoneCount) == Int(layout) * Int(layout) else { return nil }
        guard frameLen == 16 + Int(zoneCount) * 4, data.count >= frameLen else { return nil }

        var zones: [ZoneReading] = []
        zones.reserveCapacity(Int(zoneCount))
        for i in 0..<Int(zoneCount) {
            let base = 16 + i * 4
            zones.append(ZoneReading(rangeMm: u16(base),
                                     status: VL53L1RangeStatus(raw: bytes[base + 2]),
                                     flags: bytes[base + 3]))
        }

        return TofFrame(sensor: sensor,
                        seq: seq,
                        budgetUsPerZone: 0,
                        layout: layout,
                        distMode: profile,
                        numZones: zoneCount,
                        zones: zones)
    }
}
