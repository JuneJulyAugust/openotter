import Foundation

/// State of the reverse collision-avoidance supervisor on the firmware.
public enum FirmwareSafetyState: UInt8 {
    case safe  = 0
    case brake = 1
    case unknown
}

/// Cause for the most recent BRAKE transition reported by the firmware.
public enum FirmwareSafetyCause: UInt8 {
    case none        = 0
    case obstacle    = 1
    case tofBlind    = 2
    case frameGap    = 3
    case driverDead  = 4
    case unknown
}

/// Parsed 20-byte payload from characteristic 0xFE43 (Safety Notify / Read).
///
/// Wire layout (little-endian, all fields packed):
/// ```
/// Offset  Size  Field
/// 0       4     sequence number (UInt32)
/// 4       4     trigger timestamp, ms (UInt32)
/// 8       1     state  (0=SAFE, 1=BRAKE)
/// 9       1     cause  (FirmwareSafetyCause raw value)
/// 10      2     _pad
/// 12      2     trigger velocity, mm/s signed (Int16)
/// 14      2     trigger depth, mm (UInt16)
/// 16      2     critical distance, mm (UInt16)
/// 18      2     latched speed, mm/s (UInt16)
/// ```
public struct FirmwareSafetyEvent: Equatable {
    public let seq: UInt32
    public let timestampMs: UInt32
    public let state: FirmwareSafetyState
    public let cause: FirmwareSafetyCause
    public let triggerVelocityMps: Float
    public let triggerDepthM: Float
    public let criticalDistanceM: Float
    public let latchedSpeedMps: Float

    public enum ParseError: Error {
        case shortPayload
    }

    /// Parse 20 bytes from the firmware's 0xFE43 characteristic.
    public init(data: Data) throws {
        guard data.count >= 20 else { throw ParseError.shortPayload }
        let parsed = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            (
                ptr.load(fromByteOffset: 0, as: UInt32.self).littleEndian,
                ptr.load(fromByteOffset: 4, as: UInt32.self).littleEndian,
                ptr.load(fromByteOffset: 8, as: UInt8.self),
                ptr.load(fromByteOffset: 9, as: UInt8.self),
                ptr.load(fromByteOffset: 12, as: Int16.self).littleEndian,
                ptr.load(fromByteOffset: 14, as: UInt16.self).littleEndian,
                ptr.load(fromByteOffset: 16, as: UInt16.self).littleEndian,
                ptr.load(fromByteOffset: 18, as: UInt16.self).littleEndian
            )
        }
        self.seq = parsed.0
        self.timestampMs = parsed.1
        self.state = FirmwareSafetyState(rawValue: parsed.2) ?? .unknown
        self.cause = FirmwareSafetyCause(rawValue: parsed.3) ?? .unknown
        self.triggerVelocityMps = Float(parsed.4) / 1000.0
        self.triggerDepthM = Float(parsed.5) / 1000.0
        self.criticalDistanceM = Float(parsed.6) / 1000.0
        self.latchedSpeedMps = Float(parsed.7) / 1000.0
    }

    /// Parse 20 bytes from the firmware's 0xFE43 characteristic.
    /// Returns `nil` when `data` is shorter than 20 bytes.
    public static func parse(from data: Data) -> FirmwareSafetyEvent? {
        try? FirmwareSafetyEvent(data: data)
    }
}
