import XCTest
@testable import metalbot

final class ResponseBuilderTests: XCTestCase {

    private let builder = ResponseBuilder()

    func testMoveForwardSuccess() {
        let result = ActionResult(success: true, message: "Throttle set")
        let text = builder.build(action: .move(direction: .forward, throttle: 0.4), result: result)
        XCTAssertTrue(text.lowercased().contains("forward"))
        XCTAssertTrue(text.contains("40%"))
    }

    func testMoveBackwardSuccess() {
        let result = ActionResult(success: true, message: "Throttle set")
        let text = builder.build(action: .move(direction: .backward, throttle: 0.4), result: result)
        XCTAssertTrue(text.lowercased().contains("backward"))
    }

    func testMoveBlocked() {
        let result = ActionResult(success: false, message: "Obstacle detected ahead")
        let text = builder.build(action: .move(direction: .forward, throttle: 0.4), result: result)
        XCTAssertTrue(text.lowercased().contains("obstacle"))
    }

    func testStopSuccess() {
        let result = ActionResult(success: true, message: "Stopped")
        let text = builder.build(action: .stop, result: result)
        XCTAssertTrue(text.lowercased().contains("stop"))
    }

    func testQueryStatus() {
        let result = ActionResult(success: true, message: "Speed: 0.5 m/s, Heading: 12°")
        let text = builder.build(action: .queryStatus, result: result)
        XCTAssertTrue(text.contains("0.5 m/s"))
    }

    func testUnknownCommand() {
        let result = ActionResult(success: false, message: "Unrecognized")
        let text = builder.build(action: .unknown(raw: "dance"), result: result)
        XCTAssertTrue(text.lowercased().contains("unknown"))
        XCTAssertTrue(text.contains("dance"))
    }
}
