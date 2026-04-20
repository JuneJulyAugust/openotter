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

    private weak var peripheral: CBPeripheral?
    private weak var configChar: CBCharacteristic?

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
        }
    }

    /// Send an 8-byte FE61 config write.
    public func sendConfig(layout: UInt8, distMode: UInt8, budgetUs: UInt32) {
        guard let peripheral, let configChar else { return }

        var payload = Data(count: 8)
        payload.withUnsafeMutableBytes { raw in
            let p = raw.baseAddress!
            p.storeBytes(of: layout,     toByteOffset: 0, as: UInt8.self)
            p.storeBytes(of: distMode,   toByteOffset: 1, as: UInt8.self)
            p.storeBytes(of: UInt8(0),   toByteOffset: 2, as: UInt8.self)
            p.storeBytes(of: UInt8(0),   toByteOffset: 3, as: UInt8.self)
            p.storeBytes(of: budgetUs.littleEndian, toByteOffset: 4, as: UInt32.self)
        }

        let writeType: CBCharacteristicWriteType =
            configChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(payload, for: configChar, type: writeType)
    }

    /// Reassembly buffer for the FE62 chunk stream. BlueNRG-MS is locked to
    /// ATT_MTU=23, capping a notify PDU at 20 B. The 76-byte TofL1_Frame_t
    /// arrives as 4 chunks: 1 header byte (idx in low 7 bits, 0x80 = last)
    /// + 19 payload bytes. We parse only after the chunk with the last bit.
    private var rxBuf = [UInt8](repeating: 0, count: 76)
    private var rxNext: UInt8 = 0

    public func handleFrameNotification(_ data: Data) {
        guard data.count == 20 else { return }
        let bytes = [UInt8](data)
        let hdr   = bytes[0]
        let idx   = hdr & 0x7F
        let last  = (hdr & 0x80) != 0

        // Restart on chunk 0; otherwise enforce in-order delivery.
        if idx == 0 {
            rxNext = 0
        }
        guard idx == rxNext, idx < 4 else {
            rxNext = 0
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

        return TofFrame(seq: seq,
                        budgetUsPerZone: budgetUsPerZone,
                        layout: layout,
                        distMode: distMode,
                        numZones: numZones,
                        zones: zones)
    }
}
