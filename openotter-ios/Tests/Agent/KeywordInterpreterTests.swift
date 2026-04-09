import XCTest
@testable import openotter

final class KeywordInterpreterTests: XCTestCase {

    private let interpreter = KeywordInterpreter()

    func testForwardCommand() {
        let action = interpreter.interpret("/forward")
        XCTAssertEqual(action, .move(direction: .forward, throttle: 0.4))
    }

    func testBackwardCommand() {
        let action = interpreter.interpret("/backward")
        XCTAssertEqual(action, .move(direction: .backward, throttle: 0.4))
    }

    func testStopCommand() {
        let action = interpreter.interpret("/stop")
        XCTAssertEqual(action, .stop)
    }

    func testStatusCommand() {
        let action = interpreter.interpret("/status")
        XCTAssertEqual(action, .queryStatus)
    }

    func testUnknownCommand() {
        let action = interpreter.interpret("hello there")
        XCTAssertEqual(action, .unknown(raw: "hello there"))
    }

    func testCommandIsCaseInsensitive() {
        let action = interpreter.interpret("/FORWARD")
        XCTAssertEqual(action, .move(direction: .forward, throttle: 0.4))
    }

    func testCommandWithLeadingTrailingWhitespace() {
        let action = interpreter.interpret("  /stop  ")
        XCTAssertEqual(action, .stop)
    }

    func testLeftCommand() {
        let action = interpreter.interpret("/left")
        XCTAssertEqual(action, .move(direction: .left, throttle: 0.4))
    }

    func testRightCommand() {
        let action = interpreter.interpret("/right")
        XCTAssertEqual(action, .move(direction: .right, throttle: 0.4))
    }
}
