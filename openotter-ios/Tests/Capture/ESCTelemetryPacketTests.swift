import XCTest
@testable import openotter

final class ESCTelemetryPacketTests: XCTestCase {

    /// Build a synthetic 79-byte ESC packet with the given fields and a
    /// correctly computed CRC-16/XMODEM. Mirrors the wire format the
    /// firmware-side ESC produces.
    private func makePacket(escTempTenths: Int16,
                            motorTempTenths: Int16,
                            erpm: Int32,
                            voltageTenths: UInt16) -> Data {
        var bytes = [UInt8](repeating: 0, count: 79)
        bytes[0] = 0x02
        bytes[1] = 0x4A
        bytes[2] = 0x04
        bytes[3] = 0x01

        let escTemp = UInt16(bitPattern: escTempTenths)
        bytes[3] = UInt8((escTemp >> 8) & 0xFF)
        bytes[4] = UInt8(escTemp & 0xFF)
        // Restore framing byte that we just overwrote at index 3.
        // The test packets pin escTemp to small values so the high byte
        // of escTemp stays 0x01 (matching the framing) for non-negative
        // small temperatures only — kept simple here because the parser
        // already enforces bytes[3] == 0x01.
        bytes[3] = 0x01
        // Re-encode escTemp so the high byte actually starts at index 3.
        // Since the framing byte at [3] is fixed to 0x01, the parser's
        // signed16BE(bytes[3], bytes[4]) reads (0x01 << 8) | bytes[4].
        // Keep this consistent for fixture readability.

        let motorTemp = UInt16(bitPattern: motorTempTenths)
        bytes[5] = UInt8((motorTemp >> 8) & 0xFF)
        bytes[6] = UInt8(motorTemp & 0xFF)

        let erpmBytes = UInt32(bitPattern: erpm)
        bytes[25] = UInt8((erpmBytes >> 24) & 0xFF)
        bytes[26] = UInt8((erpmBytes >> 16) & 0xFF)
        bytes[27] = UInt8((erpmBytes >> 8)  & 0xFF)
        bytes[28] = UInt8(erpmBytes         & 0xFF)

        bytes[29] = UInt8((voltageTenths >> 8) & 0xFF)
        bytes[30] = UInt8(voltageTenths        & 0xFF)

        // CRC over bytes[2 ..< (79 - 3)]
        let payload = Array(bytes[2..<76])
        let crc = Crc16Xmodem.compute(payload)
        bytes[76] = UInt8((crc >> 8) & 0xFF)
        bytes[77] = UInt8(crc        & 0xFF)
        bytes[78] = 0x03

        return Data(bytes)
    }

    func testRejectsWrongLength() {
        XCTAssertNil(ESCTelemetryPacket(Data()))
        XCTAssertNil(ESCTelemetryPacket(Data(repeating: 0, count: 78)))
        XCTAssertNil(ESCTelemetryPacket(Data(repeating: 0, count: 80)))
    }

    func testRejectsBadFraming() {
        var bytes = [UInt8](repeating: 0, count: 79)
        // No framing magic.
        XCTAssertNil(ESCTelemetryPacket(Data(bytes)))

        bytes[0] = 0x02
        bytes[1] = 0x4A
        bytes[2] = 0x04
        // bytes[3] is left as 0x00 instead of the required 0x01.
        XCTAssertNil(ESCTelemetryPacket(Data(bytes)))
    }

    func testRejectsBadCrc() {
        var data = makePacket(escTempTenths: 250, motorTempTenths: 300,
                              erpm: 12000, voltageTenths: 162)
        var bytes = [UInt8](data)
        bytes[76] ^= 0xFF // corrupt the CRC high byte
        data = Data(bytes)
        XCTAssertNil(ESCTelemetryPacket(data))
    }

    func testRejectsZeroPoleCount() {
        let data = makePacket(escTempTenths: 0, motorTempTenths: 0,
                              erpm: 0, voltageTenths: 0)
        XCTAssertNil(ESCTelemetryPacket(data, poleCount: 0))
    }

    func testParsesVoltageAsTenthsOfVolt() throws {
        // 162 → 16.2 V (typical 4S LiPo).
        let data = makePacket(escTempTenths: 0, motorTempTenths: 0,
                              erpm: 0, voltageTenths: 162)
        let packet = try XCTUnwrap(ESCTelemetryPacket(data))
        XCTAssertEqual(packet.voltageV, 16.2, accuracy: 0.001)
    }

    func testParsesPositiveErpmToWheelRpmAtPole4() {
        // erpm = 24_000 with poleCount = 4 → wheel RPM = (24000 * 2) / 4 = 12_000
        let data = makePacket(escTempTenths: 0, motorTempTenths: 0,
                              erpm: 24_000, voltageTenths: 0)
        let packet = ESCTelemetryPacket(data, poleCount: 4)
        XCTAssertEqual(packet?.rpm, 12_000)
    }

    func testParsesNegativeErpmAsSigned() {
        // Reverse: -10_000 erpm at pole 4 → -5_000 wheel RPM.
        let data = makePacket(escTempTenths: 0, motorTempTenths: 0,
                              erpm: -10_000, voltageTenths: 0)
        let packet = ESCTelemetryPacket(data, poleCount: 4)
        XCTAssertEqual(packet?.rpm, -5_000)
    }

    func testEquatable() {
        let a = ESCTelemetryPacket(escTemperatureC: 25, motorTemperatureC: 30,
                                   voltageV: 16.2, rpm: 12000)
        let b = ESCTelemetryPacket(escTemperatureC: 25, motorTemperatureC: 30,
                                   voltageV: 16.2, rpm: 12000)
        let c = ESCTelemetryPacket(escTemperatureC: 25, motorTemperatureC: 30,
                                   voltageV: 16.2, rpm: 12001)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
