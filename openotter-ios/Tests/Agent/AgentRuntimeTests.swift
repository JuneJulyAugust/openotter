import XCTest
@testable import openotter

private final class MockGoalReceiver: GoalReceiving {
    var lastGoal: PlannerGoal?
    var didReset = false
    func setGoal(_ goal: PlannerGoal) { lastGoal = goal }
    func reset() { didReset = true }
}

private struct StubStatusProvider: StatusProviding {
    func currentStatus() -> String { "Speed: 1.2 m/s, BLE: Connected" }
}

final class AgentRuntimeTests: XCTestCase {

    private var runtime: AgentRuntime!
    private var speech: MuteSpeechOutput!
    private var goalReceiver: MockGoalReceiver!

    override func setUp() {
        super.setUp()
        goalReceiver = MockGoalReceiver()
        speech = MuteSpeechOutput()
        let interpreter = KeywordInterpreter()
        let dispatcher = ActionDispatcher(
            goalReceiver: goalReceiver,
            statusProvider: StubStatusProvider(),
            interpreter: interpreter
        )
        runtime = AgentRuntime(
            interpreter: interpreter,
            dispatcher: dispatcher,
            responseBuilder: ResponseBuilder(),
            speech: speech
        )
    }

    func testForwardCommandProducesGoalAndSpeech() {
        let response = runtime.handleMessage("/forward")
        XCTAssertEqual(response, "Drive")
        XCTAssertEqual(speech.lastSpoken, response)
        if case .constantThrottle(let t) = goalReceiver.lastGoal {
            XCTAssertEqual(t, 0.4, accuracy: 0.001)
        } else {
            XCTFail("Expected constantThrottle goal")
        }
    }

    func testStopCommandResetsAndSpeaks() {
        let response = runtime.handleMessage("/stop")
        XCTAssertEqual(response, "Park")
        XCTAssertTrue(goalReceiver.didReset)
        XCTAssertEqual(speech.lastSpoken, response)
    }

    func testStatusCommandReturnsTelemetry() {
        let response = runtime.handleMessage("/status")
        XCTAssertTrue(response.contains("1.2 m/s"))
    }

    func testUnknownCommandReturnHelp() {
        let response = runtime.handleMessage("dance")
        XCTAssertTrue(response.lowercased().contains("unknown"))
    }

    func testHelpCommandSuppressesSpeech() {
        speech.lastSpoken = nil
        let response = runtime.handleMessage("/help")
        // Response is non-empty (sent via Telegram) but TTS must be silent.
        XCTAssertTrue(response.contains("OpenOtter"))
        XCTAssertNil(speech.lastSpoken, "Help response should not be spoken")
    }
}
