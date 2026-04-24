import Foundation
import CoreBluetooth
import Combine

/// Decodes the FE62 frame stream from OPENOTTER-MCP and exposes the latest
/// frame plus a derived scan rate to SwiftUI.
///
/// Frame wire format authority:
///   firmware/stm32-mcp/Core/Inc/tof_l1.h (TofL1_Frame_t, 76 B fixed, LE)
///
/// Status payload authority:
///   firmware/stm32-mcp/Core/Inc/ble_tof.h (BLE_TofStatusPayload_t, 4 B)
public final class STM32TofService: NSObject, ObservableObject {

    public static let shared = STM32TofService()

    @Published public private(set) var latestFrame: TofFrame?
    @Published public private(set) var state: TofState = .unknown
    @Published public private(set) var lastError: UInt8 = 0
    @Published public private(set) var scanHz: UInt8 = 0
    @Published public private(set) var droppedFrameChunks: UInt32 = 0

    private weak var peripheral: CBPeripheral?
    private weak var configChar: CBCharacteristic?
    private var preferredConfig = TofConfig(sensor: .vl53l5cx,
                                            layout: 4,
                                            distMode: 1,
                                            budgetUs: 0,
                                            frequencyHz: 10,
                                            integrationMs: 20)

    public override init() { super.init() }

    /// Wire characteristics discovered by STM32BleManager into the service.
    public func attach(peripheral: CBPeripheral,
                       frameChar: CBCharacteristic,
                       configChar: CBCharacteristic,
                       statusChar: CBCharacteristic) {
        self.peripheral = peripheral
        self.configChar = configChar

        if frameChar.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: frameChar)
        }
        if statusChar.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: statusChar)
        }
    }

    /// Drop characteristic refs on disconnect so we don't write to a dead session.
    public func detach() {
        peripheral = nil
        configChar = nil
        DispatchQueue.main.async {
            self.latestFrame = nil
            self.state = .unknown
            self.lastError = 0
            self.scanHz = 0
            self.droppedFrameChunks = 0
        }
    }

    /// Send an 8-byte FE61 config write.
    public func sendConfig(layout: UInt8, distMode: UInt8, budgetUs: UInt32) {
        let budgetMs = UInt16(min(UInt32(UInt16.max), budgetUs / 1000))
        sendConfig(sensor: preferredConfig.sensor,
                   layout: layout,
                   profile: distMode,
                   frequencyHz: preferredConfig.frequencyHz,
                   integrationMs: preferredConfig.integrationMs,
                   budgetMs: budgetMs)
    }

    public func sendConfig(sensor: TofSensorType,
                           layout: UInt8,
                           profile: UInt8,
                           frequencyHz: UInt8,
                           integrationMs: UInt16,
                           budgetMs: UInt16) {
        guard let peripheral, let configChar else { return }

        let payload = Self.makeConfigPayload(sensor: sensor,
                                             layout: layout,
                                             profile: profile,
                                             frequencyHz: frequencyHz,
                                             integrationMs: integrationMs,
                                             budgetMs: budgetMs)

        let writeType: CBCharacteristicWriteType =
            configChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(payload, for: configChar, type: writeType)
    }

    public static func makeConfigPayload(sensor: TofSensorType,
                                         layout: UInt8,
                                         profile: UInt8,
                                         frequencyHz: UInt8,
                                         integrationMs: UInt16,
                                         budgetMs: UInt16) -> Data {
        var payload = Data(count: 8)
        payload.withUnsafeMutableBytes { raw in
            let p = raw.baseAddress!
            p.storeBytes(of: sensor.rawValue, toByteOffset: 0, as: UInt8.self)
            p.storeBytes(of: layout, toByteOffset: 1, as: UInt8.self)
            p.storeBytes(of: profile, toByteOffset: 2, as: UInt8.self)
            p.storeBytes(of: frequencyHz, toByteOffset: 3, as: UInt8.self)
            p.storeBytes(of: integrationMs.littleEndian, toByteOffset: 4, as: UInt16.self)
            p.storeBytes(of: budgetMs.littleEndian, toByteOffset: 6, as: UInt16.self)
        }
        return payload
    }

    /// Reassembly buffer for the FE62 chunk stream. BlueNRG-MS is locked to
    /// ATT_MTU=23, capping a notify PDU at 20 B. The 76-byte TofL1_Frame_t
    /// arrives as 4 chunks: 1 header byte (idx in low 7 bits, 0x80 = last)
    /// + 19 payload bytes. We parse only after the chunk with the last bit.
    private var rxBuf = [UInt8](repeating: 0, count: 76)
    private var rxNext: UInt8 = 0
    private var rxV2Buf = [UInt8](repeating: 0, count: 272)
    private var rxV2Next: UInt8 = 0
    private var rxV2SeqLow: UInt8 = 0
    private var rxMode: RxMode = .unknown

    private enum RxMode {
        case unknown
        case v1
        case v2
    }

    public func handleFrameNotification(_ data: Data) {
        guard data.count == 20 else { return }
        let bytes = [UInt8](data)
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
                DispatchQueue.main.async {
                    self.latestFrame = frame
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
        guard dst + 18 <= rxV2Buf.count else {
            rxV2Next = 0
            rxMode = .unknown
            droppedFrameChunks += 1
            return
        }

        for i in 0..<18 { rxV2Buf[dst + i] = bytes[2 + i] }
        rxV2Next &+= 1

        if last {
            let copied = dst + 18
            let frameLen: Int
            if copied >= 14 {
                frameLen = Int(UInt16(rxV2Buf[12]) | (UInt16(rxV2Buf[13]) << 8))
            } else {
                frameLen = copied
            }
            if frameLen <= copied,
               let frame = Self.parseFrameV2(Data(rxV2Buf.prefix(frameLen))) {
                DispatchQueue.main.async {
                    self.latestFrame = frame
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
        let bytes = [UInt8](data)
        DispatchQueue.main.async {
            self.state     = TofState(raw: bytes[0])
            self.lastError = bytes[1]
            self.scanHz    = bytes[2]
        }
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
