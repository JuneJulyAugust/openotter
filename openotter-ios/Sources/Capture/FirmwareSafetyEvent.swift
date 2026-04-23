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
    /// Velocity at BRAKE entry (m/s). Meaningful only when `state == .brake`.
    public let triggerVelocityMps: Float
    /// Smoothed center-zone depth at BRAKE entry (m). Meaningful only when
    /// `state == .brake`.
    public let triggerDepthM: Float
    /// `criticalDistance(|v_latched|)` at BRAKE entry (m). Meaningful only
    /// when `state == .brake`; in SAFE payloads the firmware reports the
    /// bare rear margin (~0.17 m) because `latched_speed` is zero.
    public let criticalDistanceM: Float
    /// `|v|` latched at BRAKE entry (m/s). Meaningful only when
    /// `state == .brake`.
    public let latchedSpeedMps: Float

    /// Parse 20 bytes from the firmware's 0xFE43 characteristic.
    /// Returns `nil` when `data` is shorter than 20 bytes.
    public static func parse(from data: Data) -> FirmwareSafetyEvent? {
        guard data.count >= 20 else { return nil }
        return data.withUnsafeBytes { ptr in
            let seq                = ptr.load(fromByteOffset:  0, as: UInt32.self).littleEndian
            let timestampMs        = ptr.load(fromByteOffset:  4, as: UInt32.self).littleEndian
            let stateRaw           = ptr.load(fromByteOffset:  8, as: UInt8.self)
            let causeRaw           = ptr.load(fromByteOffset:  9, as: UInt8.self)
            // offsets 10-11 are padding
            let velocityMmS        = ptr.load(fromByteOffset: 12, as: Int16.self).littleEndian
            let depthMm            = ptr.load(fromByteOffset: 14, as: UInt16.self).littleEndian
            let criticalMm         = ptr.load(fromByteOffset: 16, as: UInt16.self).littleEndian
            let latchedMmS         = ptr.load(fromByteOffset: 18, as: UInt16.self).littleEndian

            let state  = FirmwareSafetyState(rawValue: stateRaw)  ?? .unknown
            let cause  = FirmwareSafetyCause(rawValue: causeRaw)  ?? .unknown
            return FirmwareSafetyEvent(
                seq:                seq,
                timestampMs:        timestampMs,
                state:              state,
                cause:              cause,
                triggerVelocityMps: Float(velocityMmS) / 1000.0,
                triggerDepthM:      Float(depthMm)     / 1000.0,
                criticalDistanceM:  Float(criticalMm)  / 1000.0,
                latchedSpeedMps:    Float(latchedMmS)  / 1000.0
            )
        }
    }
}
