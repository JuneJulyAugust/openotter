import Foundation

/// Parsed payload of the STM32 firmware safety characteristic (0xFE43).
/// Wire layout is defined in
/// docs/superpowers/specs/2026-04-23-stm32-reverse-safety-and-protocol-design.md §3.6.
public struct FirmwareSafetyEvent: Equatable {

    public enum State: UInt8 {
        case safe = 0
        case brake = 1
    }

    public enum Cause: UInt8 {
        case none        = 0
        case obstacle    = 1
        case tofBlind    = 2
        case frameGap    = 3
        case driverDead  = 4
    }

    public let seq: UInt32
    public let timestampMs: UInt32
    public let state: State
    public let cause: Cause
    public let triggerVelocityMPS: Float
    public let triggerDepthM: Float
    public let criticalDistanceM: Float
    public let latchedSpeedMPS: Float

    public enum ParseError: Error { case shortPayload }

    public init(data: Data) throws {
        guard data.count >= 20 else { throw ParseError.shortPayload }
        func u32(_ offset: Int) -> UInt32 {
            return data.subdata(in: offset..<(offset+4))
                .withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        }
        func u16(_ offset: Int) -> UInt16 {
            return data.subdata(in: offset..<(offset+2))
                .withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
        }
        func i16(_ offset: Int) -> Int16 {
            return Int16(bitPattern: u16(offset))
        }
        self.seq           = u32(0)
        self.timestampMs   = u32(4)
        self.state         = State(rawValue: data[8]) ?? .safe
        self.cause         = Cause(rawValue: data[9]) ?? .none
        self.triggerVelocityMPS = Float(i16(12)) / 1000.0
        self.triggerDepthM      = Float(u16(14)) / 1000.0
        self.criticalDistanceM  = Float(u16(16)) / 1000.0
        self.latchedSpeedMPS    = Float(u16(18)) / 1000.0
    }
}