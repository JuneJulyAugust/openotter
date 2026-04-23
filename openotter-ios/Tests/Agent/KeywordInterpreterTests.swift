import XCTest
@testable import openotter

final class KeywordInterpreterTests: XCTestCase {

    private var interpreter: KeywordInterpreter!

    override func setUp() {
        super.setUp()
        interpreter = KeywordInterpreter()
    }

    // MARK: - Move commands use current throttle

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

    // MARK: - Speed commands

    func testSpeedCommand() {
        let action = interpreter.interpret("speed 0.6")
        XCTAssertEqual(action, .setSpeed(throttle: 0.6))
    }

    func testSlashSpeedCommand() {
        let action = interpreter.interpret("/speed 0.3")
        XCTAssertEqual(action, .setSpeed(throttle: 0.3))
    }

    func testSpeedClampedHigh() {
        let action = interpreter.interpret("speed 1.5")
        XCTAssertEqual(action, .setSpeed(throttle: 1.0))
    }

    func testSpeedClampedLow() {
        let action = interpreter.interpret("speed 0.0")
        XCTAssertEqual(action, .setSpeed(throttle: 0.1))
    }

    func testSlowButtonParsesAsSetSpeed() {
        let action = interpreter.interpret("🐢 Slow")
        XCTAssertEqual(action, .setSpeed(throttle: 0.2))
    }

    func testNormalButtonParsesAsSetSpeed() {
        let action = interpreter.interpret("🚗 Normal")
        XCTAssertEqual(action, .setSpeed(throttle: 0.4))
    }

    func testFastButtonParsesAsSetSpeed() {
        let action = interpreter.interpret("🐇 Fast")
        XCTAssertEqual(action, .setSpeed(throttle: 0.8))
    }

    // MARK: - Help

    func testHelpCommand() {
        XCTAssertEqual(interpreter.interpret("help"), .help)
    }

    func testSlashHelpCommand() {
        XCTAssertEqual(interpreter.interpret("/help"), .help)
    }

    func testHelpButtonWithEmoji() {
        XCTAssertEqual(interpreter.interpret("❓ Help"), .help)
    }

    // MARK: - Throttle state

    func testMoveUsesUpdatedThrottleAfterSetThrottle() {
        interpreter.setThrottle(0.7)
        let action = interpreter.interpret("drive")
        XCTAssertEqual(action, .move(direction: .forward, throttle: 0.7))
    }

    func testSetThrottleClampsRange() {
        interpreter.setThrottle(2.0)
        XCTAssertEqual(interpreter.currentThrottle, 1.0, accuracy: 0.001)
        interpreter.setThrottle(-0.5)
        XCTAssertEqual(interpreter.currentThrottle, 0.1, accuracy: 0.001)
    }
}
