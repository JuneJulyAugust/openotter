import XCTest
@testable import openotter

final class Crc16XmodemTests: XCTestCase {

    /// Standard CRC-16/XMODEM check vector: ASCII "123456789" → 0x31C3.
    /// Source: https://reveng.sourceforge.io/crc-catalogue/16.htm#crc.cat.crc-16-xmodem
    func testStandardCheckVector() {
        let bytes: [UInt8] = Array("123456789".utf8)
        XCTAssertEqual(Crc16Xmodem.compute(bytes), 0x31C3)
    }

    func testEmptyInputIsZero() {
        XCTAssertEqual(Crc16Xmodem.compute([]), 0x0000)
    }

    func testSingleByteMatchesPolynomial() {
        // CRC of [0x01] = 0x1021 (one shift, top bit = 0, then XOR with poly).
        XCTAssertEqual(Crc16Xmodem.compute([0x01]), 0x1021)
    }

    func testSequenceOverloadMatchesArrayOverload() {
        let bytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0x42]
        let arrayResult = Crc16Xmodem.compute(bytes)
        let sliceResult = Crc16Xmodem.compute(bytes[...])
        XCTAssertEqual(arrayResult, sliceResult)
    }

    func testDifferentInputsProduceDifferentChecksums() {
        XCTAssertNotEqual(Crc16Xmodem.compute([0x00]),
                          Crc16Xmodem.compute([0x01]))
        XCTAssertNotEqual(Crc16Xmodem.compute([0x01, 0x02]),
                          Crc16Xmodem.compute([0x02, 0x01]))
    }
}
