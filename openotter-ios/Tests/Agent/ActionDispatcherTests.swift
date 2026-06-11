import XCTest
@testable import openotter

private final class MockGoalReceiver: GoalReceiving {
    var lastGoal: PlannerGoal?
    var didReset = false

    func setGoal(_ goal: PlannerGoal) { lastGoal = goal }
    func reset() { didReset = true }
}

private struct StubStatusProvider: StatusProviding {
    var statusText: String = "Speed: 0.0 m/s"
    func currentStatus() -> String { statusText }
}

final class ActionDispatcherTests: XCTestCase {

    private var goalReceiver: MockGoalReceiver!
    private var interpreter: KeywordInterpreter!
    private var dispatcher: ActionDispatcher!

    override func setUp() {
        super.setUp()
        goalReceiver = MockGoalReceiver()
        interpreter = KeywordInterpreter()
        dispatcher = ActionDispatcher(
            goalReceiver: goalReceiver,
            statusProvider: StubStatusProvider(),
            interpreter: interpreter
        )
    }

    func testMoveForwardSetsConstantThrottleGoal() {
        let result = dispatcher.dispatch(.move(direction: .forward, throttle: 0.4))
        XCTAssertTrue(result.success)
        if case .constantThrottle(let t) = goalReceiver.lastGoal {
            XCTAssertEqual(t, 0.4, accuracy: 0.001)
        } else {
            XCTFail("Expected constantThrottle goal, got \(String(describing: goalReceiver.lastGoal))")
        }
    }

    func testMoveBackwardSetsNegativeThrottle() {
        let result = dispatcher.dispatch(.move(direction: .backward, throttle: 0.4))
        XCTAssertTrue(result.success)
        if case .constantThrottle(let t) = goalReceiver.lastGoal {
            XCTAssertEqual(t, -0.4, accuracy: 0.001)
        } else {
            XCTFail("Expected constantThrottle goal")
        }
    }

    func testStopResetsOrchestrator() {
        let result = dispatcher.dispatch(.stop)
        XCTAssertTrue(result.success)
        XCTAssertTrue(goalReceiver.didReset)
    }


    func testQueryStatusReturnsStatusText() {
        let result = dispatcher.dispatch(.queryStatus)
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.message.contains("0.0 m/s"))
    }

    func testUnknownCommandFails() {
        let result = dispatcher.dispatch(.unknown(raw: "dance"))
        XCTAssertFalse(result.success)
    }

    func testFigureEightDispatchesWaypointMission() {
        let result = dispatcher.dispatch(.figureEight)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.message, "Starting figure-8 mission")

        if case .followFigureEight(let config, let maxThrottle) = goalReceiver.lastGoal {
            XCTAssertEqual(maxThrottle, 1.0, accuracy: 0.001)
            XCTAssertEqual(config.segmentCount, 240)
            XCTAssertEqual(config.length, 4.0, accuracy: 0.001)
            XCTAssertEqual(config.width, 2.0, accuracy: 0.001)
            XCTAssertEqual(config.acceptanceRadius, 0.25, accuracy: 0.001)
        } else {
            XCTFail("Expected followFigureEight goal")
        }
    }

    func testFigureEightBoostsCustomSpeedByTwoWithCap() {
        _ = dispatcher.dispatch(.setSpeed(throttle: 0.3))
        _ = dispatcher.dispatch(.figureEight)

        if case .followFigureEight(_, let maxThrottle) = goalReceiver.lastGoal {
            XCTAssertEqual(maxThrottle, 0.6, accuracy: 0.001)
        } else {
            XCTFail("Expected followFigureEight goal")
        }

        _ = dispatcher.dispatch(.setSpeed(throttle: 0.8))
        _ = dispatcher.dispatch(.figureEight)

        if case .followFigureEight(_, let maxThrottle) = goalReceiver.lastGoal {
            XCTAssertEqual(maxThrottle, 1.0, accuracy: 0.001)
        } else {
            XCTFail("Expected followFigureEight goal")
        }
    }

    // MARK: - Set Speed

    func testSetSpeedUpdatesInterpreterThrottle() {
        let result = dispatcher.dispatch(.setSpeed(throttle: 0.7))
        XCTAssertTrue(result.success)
        XCTAssertEqual(interpreter.currentThrottle, 0.7, accuracy: 0.001)
        XCTAssertTrue(result.message.contains("0.7"))
    }

    func testSetSpeedClamps() {
        _ = dispatcher.dispatch(.setSpeed(throttle: 5.0))
        XCTAssertEqual(interpreter.currentThrottle, 1.0, accuracy: 0.001)
    }

    func testMoveAfterSetSpeedUsesNewThrottle() {
        _ = dispatcher.dispatch(.setSpeed(throttle: 0.8))
        // Now interpret a drive command — should use the updated throttle
        let action = interpreter.interpret("drive")
        let result = dispatcher.dispatch(action)
        XCTAssertTrue(result.success)
        if case .constantThrottle(let t) = goalReceiver.lastGoal {
            XCTAssertEqual(t, 0.8, accuracy: 0.001)
        } else {
            XCTFail("Expected constantThrottle goal")
        }
    }

    // MARK: - Help

    func testHelpReturnsCommandList() {
        let result = dispatcher.dispatch(.help)
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.message.contains("drive"))
        XCTAssertTrue(result.message.contains("speed"))
        XCTAssertTrue(result.message.contains("help"))
    }
}
