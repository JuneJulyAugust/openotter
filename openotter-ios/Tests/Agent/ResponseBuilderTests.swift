import XCTest
@testable import openotter

final class ResponseBuilderTests: XCTestCase {

    private let builder = ResponseBuilder()

    func testMoveForwardSuccess() {
        let result = ActionResult(success: true, message: "Throttle set")
        let text = builder.build(action: .move(direction: .forward, throttle: 0.4), result: result)
        XCTAssertEqual(text, "Drive")
    }

    func testMoveBackwardSuccess() {
        let result = ActionResult(success: true, message: "Throttle set")
        let text = builder.build(action: .move(direction: .backward, throttle: 0.4), result: result)
        XCTAssertEqual(text, "Reverse")
    }

    func testMoveBlocked() {
        let result = ActionResult(success: false, message: "Obstacle detected ahead")
        let text = builder.build(action: .move(direction: .forward, throttle: 0.4), result: result)
        XCTAssertTrue(text.lowercased().contains("obstacle"))
    }

    func testStopSuccess() {
        let result = ActionResult(success: true, message: "Stopped")
        let text = builder.build(action: .stop, result: result)
        XCTAssertEqual(text, "Park")
    }

    func testQueryStatus() {
        let result = ActionResult(success: true, message: "Speed: 0.5 m/s, Heading: 12°")
        let text = builder.build(action: .queryStatus, result: result)
        XCTAssertTrue(text.contains("0.5 m/s"))
    }

    func testSetSpeedPassesResultMessage() {
        let result = ActionResult(success: true, message: "Speed set to 0.6 (60%)")
        let text = builder.build(action: .setSpeed(throttle: 0.6), result: result)
        XCTAssertTrue(text.contains("0.6"))
    }

    func testHelpPassesResultMessage() {
        let result = ActionResult(success: true, message: "🤖 OpenOtter Commands\n...")
        let text = builder.build(action: .help, result: result)
        XCTAssertTrue(text.contains("OpenOtter"))
    }

    func testUnknownCommand() {
        let result = ActionResult(success: false, message: "Unrecognized")
        let text = builder.build(action: .unknown(raw: "dance"), result: result)
        XCTAssertTrue(text.lowercased().contains("unrecognized"))
    }
}
