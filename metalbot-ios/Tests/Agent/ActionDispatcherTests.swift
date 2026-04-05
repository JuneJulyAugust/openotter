import XCTest
@testable import metalbot

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
    private var dispatcher: ActionDispatcher!

    override func setUp() {
        super.setUp()
        goalReceiver = MockGoalReceiver()
        dispatcher = ActionDispatcher(
            goalReceiver: goalReceiver,
            statusProvider: StubStatusProvider()
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
}
