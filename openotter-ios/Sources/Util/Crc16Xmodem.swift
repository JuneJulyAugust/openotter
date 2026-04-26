import Foundation

/// CRC-16/XMODEM checksum.
///
/// Polynomial `0x1021`, initial value `0`, no reflection, no final XOR.
/// Used by the ESC telemetry framing — extracted from `ESCBleManager`
/// so it can be host-tested independently and reused by any other
/// code that speaks the same framing.
public enum Crc16Xmodem {

    /// Compute the CRC-16/XMODEM of `bytes`.
    public static func compute(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc &<< 1) ^ 0x1021
                } else {
                    crc = crc &<< 1
                }
            }
        }
        return crc
    }

    /// Convenience overload accepting any `Sequence<UInt8>`.
    public static func compute<S: Sequence>(_ bytes: S) -> UInt16
    where S.Element == UInt8 {
        compute(Array(bytes))
    }
}
