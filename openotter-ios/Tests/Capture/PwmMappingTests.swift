import XCTest
@testable import openotter

final class PwmMappingTests: XCTestCase {

    // MARK: - Constants pinning

    func testConstantsMatchFirmware() {
        // These mirror firmware/stm32-mcp/Core/Inc/pwm_control.h. If the
        // firmware values change, the wire contract is broken and this
        // test must be updated alongside the firmware change.
        XCTAssertEqual(PwmMapping.neutralUs, 1500)
        XCTAssertEqual(PwmMapping.minUs, 1000)
        XCTAssertEqual(PwmMapping.maxUs, 2000)
    }

    // MARK: - toPulseWidth

    func testZeroMapsToNeutral() {
        XCTAssertEqual(PwmMapping.toPulseWidth(0.0), 1500)
    }

    func testPositiveOneMapsToMax() {
        XCTAssertEqual(PwmMapping.toPulseWidth(1.0), 2000)
    }

    func testNegativeOneMapsToMin() {
        XCTAssertEqual(PwmMapping.toPulseWidth(-1.0), 1000)
    }

    func testHalfThrottleMapsToHalfwayPoint() {
        XCTAssertEqual(PwmMapping.toPulseWidth(0.5), 1750)
        XCTAssertEqual(PwmMapping.toPulseWidth(-0.5), 1250)
    }

    func testOutOfRangeIsClamped() {
        XCTAssertEqual(PwmMapping.toPulseWidth(2.5), 2000)
        XCTAssertEqual(PwmMapping.toPulseWidth(-3.0), 1000)
    }

    func testNonFiniteCollapsesToNeutral() {
        XCTAssertEqual(PwmMapping.toPulseWidth(.nan), 1500)
        XCTAssertEqual(PwmMapping.toPulseWidth(.infinity), 1500)
        XCTAssertEqual(PwmMapping.toPulseWidth(-.infinity), 1500)
    }

    // MARK: - clampPulse

    func testClampPulseInRangeIsUnchanged() {
        XCTAssertEqual(PwmMapping.clampPulse(1500), 1500)
        XCTAssertEqual(PwmMapping.clampPulse(1750), 1750)
    }

    func testClampPulseClampsOutOfRange() {
        XCTAssertEqual(PwmMapping.clampPulse(800), 1000)
        XCTAssertEqual(PwmMapping.clampPulse(2200), 2000)
        XCTAssertEqual(PwmMapping.clampPulse(Int16.min), 1000)
        XCTAssertEqual(PwmMapping.clampPulse(Int16.max), 2000)
    }
}
