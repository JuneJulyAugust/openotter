import Foundation

/// Decoded ESC telemetry packet.
///
/// Pure value type — extracted from the previously-private
/// `TelemetryPacket` struct in `ESCBleManager` so the wire-format
/// parsing can be unit-tested independently of CoreBluetooth.
///
/// Wire format (79 bytes, big-endian fields):
///   bytes[0..3]  framing: 0x02 0x4A 0x04 0x01
///   bytes[3..4]  ESC temperature, signed 16, units 0.1 °C
///   bytes[5..6]  motor temperature, signed 16, units 0.1 °C
///   bytes[25..28] eRPM, signed 32 big-endian
///   bytes[29..30] battery voltage, unsigned 16, units 0.1 V
///   bytes[N-3..N-2] CRC-16/XMODEM over bytes[2..N-3]
///   bytes[N-1]   trailing 0x03
public struct ESCTelemetryPacket: Equatable {
    public let escTemperatureC: Double
    public let motorTemperatureC: Double
    public let voltageV: Double
    public let rpm: Int

    /// Default magnetic-pole count for the supported motor.
    public static let defaultPoleCount: Int = 4

    /// Decode a 79-byte ESC packet. Returns `nil` for any framing,
    /// length, or CRC mismatch.
    ///
    /// - Parameters:
    ///   - data: raw bytes received from the ESC notify characteristic.
    ///   - poleCount: motor pole count used to convert eRPM to wheel RPM.
    public init?(_ data: Data, poleCount: Int = ESCTelemetryPacket.defaultPoleCount) {
        let bytes = [UInt8](data)
        guard bytes.count == 79 else { return nil }
        guard bytes[0] == 0x02, bytes[1] == 0x4A,
              bytes[2] == 0x04, bytes[3] == 0x01 else { return nil }
        guard poleCount > 0 else { return nil }

        let payload = Array(bytes[2..<(bytes.count - 3)])
        let expectedChecksum = (UInt16(bytes[bytes.count - 3]) << 8)
            | UInt16(bytes[bytes.count - 2])
        guard Crc16Xmodem.compute(payload) == expectedChecksum else { return nil }

        self.escTemperatureC =
            Double(Self.signed16BE(bytes[3], bytes[4])) / 10.0
        self.motorTemperatureC =
            Double(Self.signed16BE(bytes[5], bytes[6])) / 10.0

        let erpmRaw = Self.signed32BE(bytes[25], bytes[26], bytes[27], bytes[28])
        self.rpm = Int((Double(erpmRaw) * 2.0) / Double(poleCount))

        let voltageRaw = (UInt16(bytes[29]) << 8) | UInt16(bytes[30])
        self.voltageV = Double(voltageRaw) / 10.0
    }

    /// Memberwise initializer for tests / fixtures.
    public init(escTemperatureC: Double, motorTemperatureC: Double,
                voltageV: Double, rpm: Int) {
        self.escTemperatureC = escTemperatureC
        self.motorTemperatureC = motorTemperatureC
        self.voltageV = voltageV
        self.rpm = rpm
    }

    private static func signed16BE(_ high: UInt8, _ low: UInt8) -> Int {
        Int(Int16(bitPattern: (UInt16(high) << 8) | UInt16(low)))
    }

    private static func signed32BE(_ b0: UInt8, _ b1: UInt8,
                                   _ b2: UInt8, _ b3: UInt8) -> Int {
        let value = (UInt32(b0) << 24) | (UInt32(b1) << 16)
            | (UInt32(b2) << 8) | UInt32(b3)
        return Int(Int32(bitPattern: value))
    }
}
