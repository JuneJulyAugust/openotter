# Agent Runtime & Telegram Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Telegram-based remote command interface to metalbot-ios with TTS voice feedback, backed by an OpenClaw-inspired agent architecture with stub interfaces for future LLM/skill/memory.

**Architecture:** TelegramGateway (long polling) feeds raw text to AgentRuntime, which pipes it through a swappable CommandInterpreter protocol, dispatches the resulting AgentAction through the existing PlannerOrchestrator/SafetySupervisor stack, and outputs responses via both Telegram reply and AVSpeechSynthesizer TTS.

**Tech Stack:** Swift 5.9, SwiftUI, URLSession (Telegram Bot API), AVSpeechSynthesizer, iOS Keychain (Security framework), XCTest.

**Design Spec:** `docs/superpowers/specs/2026-04-05-agent-runtime-telegram-design.md`

---

## File Map

### New files — `metalbot-ios/Sources/Agent/`

| File | Responsibility |
|:-----|:---------------|
| `AgentAction.swift` | `MoveDirection` enum, `AgentAction` enum, `ActionResult` struct |
| `CommandInterpreter.swift` | `CommandInterpreter` protocol |
| `KeywordInterpreter.swift` | v1 keyword-matching implementation of `CommandInterpreter` |
| `ActionDispatcher.swift` | `ActionDispatching` protocol + `ActionDispatcher` class (routes to `PlannerOrchestrator`) |
| `ResponseBuilder.swift` | `ResponseBuilding` protocol + `ResponseBuilder` implementation |
| `SpeechOutput.swift` | `SpeechOutputting` protocol + `SpeechOutput` (AVSpeechSynthesizer wrapper) |
| `KeychainHelper.swift` | Read/write/delete strings in iOS Keychain |
| `TelegramGateway.swift` | `TelegramMessage` model, `TelegramGatewayDelegate` protocol, long-poll loop, `sendReply()` |
| `AgentRuntime.swift` | Orchestrates interpreter → dispatcher → response builder → speech + reply |
| `SkillRegistry.swift` | `SkillProviding`/`SkillRegistering` protocols + `NoOpSkillRegistry` |
| `MemoryStore.swift` | `MemoryStoring` protocol + `NoOpMemoryStore` |

### New files — `metalbot-ios/Sources/Views/`

| File | Responsibility |
|:-----|:---------------|
| `AgentDebugView.swift` | Diagnostic UI: token input, connection status, message log, manual test input, TTS toggle |

### New files — `metalbot-ios/Tests/Agent/`

| File | Responsibility |
|:-----|:---------------|
| `KeywordInterpreterTests.swift` | Tests for keyword → AgentAction mapping |
| `ActionDispatcherTests.swift` | Tests for action → planner goal routing |
| `ResponseBuilderTests.swift` | Tests for action + result → response text |
| `TelegramGatewayTests.swift` | Tests for JSON parsing of Telegram API responses |
| `AgentRuntimeTests.swift` | Integration tests for full interpret → dispatch → respond pipeline |
| `KeychainHelperTests.swift` | Tests for Keychain read/write/delete |

### Modified files

| File | Change |
|:-----|:-------|
| `metalbot-ios/Sources/Views/HomeView.swift` | Add "Agent Diagnostics" entry to `DiagnosticsView` |
| `metalbot-ios/project.yml` | No change needed — `Sources` and `Tests` directories are auto-included |

---

## Task 1: AgentAction and CommandInterpreter Protocol

**Files:**
- Create: `metalbot-ios/Sources/Agent/AgentAction.swift`
- Create: `metalbot-ios/Sources/Agent/CommandInterpreter.swift`

- [ ] **Step 1: Create AgentAction.swift**

```swift
// metalbot-ios/Sources/Agent/AgentAction.swift
import Foundation

enum MoveDirection: String, Equatable {
    case forward, backward, left, right
}

enum AgentAction: Equatable {
    case move(direction: MoveDirection, throttle: Float)
    case stop
    case queryStatus
    case unknown(raw: String)
}

struct ActionResult: Equatable {
    let success: Bool
    let message: String
}
```

- [ ] **Step 2: Create CommandInterpreter.swift**

```swift
// metalbot-ios/Sources/Agent/CommandInterpreter.swift
import Foundation

protocol CommandInterpreter {
    func interpret(_ text: String) -> AgentAction
}
```

- [ ] **Step 3: Verify build**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add metalbot-ios/Sources/Agent/AgentAction.swift metalbot-ios/Sources/Agent/CommandInterpreter.swift
git commit -m "feat(agent): Add AgentAction model and CommandInterpreter protocol"
```

---

## Task 2: KeywordInterpreter with TDD

**Files:**
- Create: `metalbot-ios/Sources/Agent/KeywordInterpreter.swift`
- Create: `metalbot-ios/Tests/Agent/KeywordInterpreterTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// metalbot-ios/Tests/Agent/KeywordInterpreterTests.swift
import XCTest
@testable import metalbot

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh test`
Expected: FAIL — `KeywordInterpreter` not defined

- [ ] **Step 3: Implement KeywordInterpreter**

```swift
// metalbot-ios/Sources/Agent/KeywordInterpreter.swift
import Foundation

struct KeywordInterpreter: CommandInterpreter {

    private static let defaultThrottle: Float = 0.4

    func interpret(_ text: String) -> AgentAction {
        let command = text.trimmingCharacters(in: .whitespaces).lowercased()
        switch command {
        case "/forward":
            return .move(direction: .forward, throttle: Self.defaultThrottle)
        case "/backward":
            return .move(direction: .backward, throttle: Self.defaultThrottle)
        case "/left":
            return .move(direction: .left, throttle: Self.defaultThrottle)
        case "/right":
            return .move(direction: .right, throttle: Self.defaultThrottle)
        case "/stop":
            return .stop
        case "/status":
            return .queryStatus
        default:
            return .unknown(raw: text)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh test`
Expected: All `KeywordInterpreterTests` PASS

- [ ] **Step 5: Commit**

```bash
git add metalbot-ios/Sources/Agent/KeywordInterpreter.swift metalbot-ios/Tests/Agent/KeywordInterpreterTests.swift
git commit -m "feat(agent): Add KeywordInterpreter with TDD tests"
```

---

## Task 3: ResponseBuilder with TDD

**Files:**
- Create: `metalbot-ios/Sources/Agent/ResponseBuilder.swift`
- Create: `metalbot-ios/Tests/Agent/ResponseBuilderTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// metalbot-ios/Tests/Agent/ResponseBuilderTests.swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh test`
Expected: FAIL — `ResponseBuilder` not defined

- [ ] **Step 3: Implement ResponseBuilder**

```swift
// metalbot-ios/Sources/Agent/ResponseBuilder.swift
import Foundation

protocol ResponseBuilding {
    func build(action: AgentAction, result: ActionResult) -> String
}

struct ResponseBuilder: ResponseBuilding {

    func build(action: AgentAction, result: ActionResult) -> String {
        switch action {
        case .move(let direction, let throttle):
            if result.success {
                let pct = Int(throttle * 100)
                return "Moving \(direction.rawValue) at \(pct)% throttle."
            } else {
                return "Cannot move \(direction.rawValue): \(result.message)."
            }

        case .stop:
            if result.success {
                return "Stopped. All actuators neutral."
            } else {
                return "Stop failed: \(result.message)."
            }

        case .queryStatus:
            return result.message

        case .unknown(let raw):
            return "Unknown command: \"\(raw)\". Use /forward, /backward, /stop, or /status."
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh test`
Expected: All `ResponseBuilderTests` PASS

- [ ] **Step 5: Commit**

```bash
git add metalbot-ios/Sources/Agent/ResponseBuilder.swift metalbot-ios/Tests/Agent/ResponseBuilderTests.swift
git commit -m "feat(agent): Add ResponseBuilder with TDD tests"
```

---

## Task 4: ActionDispatcher with TDD

**Files:**
- Create: `metalbot-ios/Sources/Agent/ActionDispatcher.swift`
- Create: `metalbot-ios/Tests/Agent/ActionDispatcherTests.swift`

- [ ] **Step 1: Write failing tests**

The `ActionDispatcher` needs to route actions to a `PlannerOrchestrator`. For testability, we inject a protocol rather than the concrete class. We also need a status provider for querying car state.

```swift
// metalbot-ios/Tests/Agent/ActionDispatcherTests.swift
import XCTest
@testable import metalbot

// MARK: - Test Doubles

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

// MARK: - Tests

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh test`
Expected: FAIL — `ActionDispatcher`, `GoalReceiving`, `StatusProviding` not defined

- [ ] **Step 3: Implement ActionDispatcher**

```swift
// metalbot-ios/Sources/Agent/ActionDispatcher.swift
import Foundation

/// Narrow interface for setting planner goals — satisfied by PlannerOrchestrator.
protocol GoalReceiving: AnyObject {
    func setGoal(_ goal: PlannerGoal)
    func reset()
}

extension PlannerOrchestrator: GoalReceiving {}

/// Narrow interface for querying car status.
protocol StatusProviding {
    func currentStatus() -> String
}

protocol ActionDispatching {
    func dispatch(_ action: AgentAction) -> ActionResult
}

final class ActionDispatcher: ActionDispatching {

    private weak var goalReceiver: (any GoalReceiving)?
    private let statusProvider: any StatusProviding

    init(goalReceiver: any GoalReceiving, statusProvider: any StatusProviding) {
        self.goalReceiver = goalReceiver
        self.statusProvider = statusProvider
    }

    func dispatch(_ action: AgentAction) -> ActionResult {
        switch action {
        case .move(let direction, let throttle):
            let signedThrottle: Float
            switch direction {
            case .forward:  signedThrottle = throttle
            case .backward: signedThrottle = -throttle
            case .left:     signedThrottle = throttle  // steering handled separately in future
            case .right:    signedThrottle = throttle
            }
            goalReceiver?.setGoal(.constantThrottle(targetThrottle: signedThrottle))
            return ActionResult(success: true, message: "Throttle set to \(signedThrottle)")

        case .stop:
            goalReceiver?.reset()
            return ActionResult(success: true, message: "Stopped")

        case .queryStatus:
            let status = statusProvider.currentStatus()
            return ActionResult(success: true, message: status)

        case .unknown(let raw):
            return ActionResult(success: false, message: "Unrecognized command: \(raw)")
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh test`
Expected: All `ActionDispatcherTests` PASS

- [ ] **Step 5: Commit**

```bash
git add metalbot-ios/Sources/Agent/ActionDispatcher.swift metalbot-ios/Tests/Agent/ActionDispatcherTests.swift
git commit -m "feat(agent): Add ActionDispatcher with GoalReceiving/StatusProviding DIP"
```

---

## Task 5: SpeechOutput

**Files:**
- Create: `metalbot-ios/Sources/Agent/SpeechOutput.swift`

- [ ] **Step 1: Implement SpeechOutput**

```swift
// metalbot-ios/Sources/Agent/SpeechOutput.swift
import AVFoundation

protocol SpeechOutputting {
    func speak(_ text: String)
    var isEnabled: Bool { get set }
}

final class SpeechOutput: SpeechOutputting {

    var isEnabled: Bool = true

    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        guard isEnabled else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}

/// Silent implementation for tests and debug.
final class MuteSpeechOutput: SpeechOutputting {
    var isEnabled: Bool = false
    var lastSpoken: String?

    func speak(_ text: String) {
        lastSpoken = text
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add metalbot-ios/Sources/Agent/SpeechOutput.swift
git commit -m "feat(agent): Add SpeechOutput with AVSpeechSynthesizer and mute double"
```

---

## Task 6: KeychainHelper with TDD

**Files:**
- Create: `metalbot-ios/Sources/Agent/KeychainHelper.swift`
- Create: `metalbot-ios/Tests/Agent/KeychainHelperTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// metalbot-ios/Tests/Agent/KeychainHelperTests.swift
import XCTest
@testable import metalbot

final class KeychainHelperTests: XCTestCase {

    private let testService = "com.metalbot.test.keychain"
    private let testKey = "test-token"

    override func tearDown() {
        super.tearDown()
        KeychainHelper.delete(key: testKey, service: testService)
    }

    func testSaveAndRead() {
        let saved = KeychainHelper.save(key: testKey, value: "abc123", service: testService)
        XCTAssertTrue(saved)
        let read = KeychainHelper.read(key: testKey, service: testService)
        XCTAssertEqual(read, "abc123")
    }

    func testReadMissingKeyReturnsNil() {
        let read = KeychainHelper.read(key: "nonexistent", service: testService)
        XCTAssertNil(read)
    }

    func testOverwriteExistingValue() {
        KeychainHelper.save(key: testKey, value: "old", service: testService)
        KeychainHelper.save(key: testKey, value: "new", service: testService)
        let read = KeychainHelper.read(key: testKey, service: testService)
        XCTAssertEqual(read, "new")
    }

    func testDeleteRemovesValue() {
        KeychainHelper.save(key: testKey, value: "toDelete", service: testService)
        KeychainHelper.delete(key: testKey, service: testService)
        let read = KeychainHelper.read(key: testKey, service: testService)
        XCTAssertNil(read)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh test`
Expected: FAIL — `KeychainHelper` not defined

- [ ] **Step 3: Implement KeychainHelper**

```swift
// metalbot-ios/Sources/Agent/KeychainHelper.swift
import Foundation
import Security

enum KeychainHelper {

    static let defaultService = "com.metalbot.agent"

    @discardableResult
    static func save(key: String, value: String, service: String = defaultService) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete any existing item first.
        delete(key: key, service: service)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func read(key: String, service: String = defaultService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(key: String, service: String = defaultService) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh test`
Expected: All `KeychainHelperTests` PASS

Note: Keychain tests may only pass on the iOS Simulator (not on device without proper entitlements). This is expected and fine for CI.

- [ ] **Step 5: Commit**

```bash
git add metalbot-ios/Sources/Agent/KeychainHelper.swift metalbot-ios/Tests/Agent/KeychainHelperTests.swift
git commit -m "feat(agent): Add KeychainHelper for secure token storage with TDD tests"
```

---

## Task 7: TelegramGateway with TDD

**Files:**
- Create: `metalbot-ios/Sources/Agent/TelegramGateway.swift`
- Create: `metalbot-ios/Tests/Agent/TelegramGatewayTests.swift`

- [ ] **Step 1: Write failing tests for JSON parsing**

The Telegram Bot API returns JSON like:
```json
{"ok":true,"result":[{"update_id":123,"message":{"message_id":1,"from":{"id":456,"first_name":"Fang","username":"fangxu"},"chat":{"id":456},"date":1712300000,"text":"/forward"}}]}
```

Test the parsing layer, not the network.

```swift
// metalbot-ios/Tests/Agent/TelegramGatewayTests.swift
import XCTest
@testable import metalbot

final class TelegramGatewayTests: XCTestCase {

    func testParseValidUpdate() throws {
        let json = """
        {
            "ok": true,
            "result": [{
                "update_id": 100,
                "message": {
                    "message_id": 1,
                    "from": {"id": 456, "first_name": "Fang", "username": "fangxu"},
                    "chat": {"id": 789},
                    "date": 1712300000,
                    "text": "/forward"
                }
            }]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TelegramUpdateResponse.self, from: json)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.result.count, 1)

        let update = response.result[0]
        XCTAssertEqual(update.updateId, 100)
        XCTAssertEqual(update.message?.text, "/forward")
        XCTAssertEqual(update.message?.chat.id, 789)
        XCTAssertEqual(update.message?.from?.username, "fangxu")
    }

    func testParseEmptyResult() throws {
        let json = """
        {"ok": true, "result": []}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TelegramUpdateResponse.self, from: json)
        XCTAssertTrue(response.ok)
        XCTAssertTrue(response.result.isEmpty)
    }

    func testParseUpdateWithoutMessage() throws {
        let json = """
        {"ok": true, "result": [{"update_id": 101}]}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TelegramUpdateResponse.self, from: json)
        XCTAssertEqual(response.result.count, 1)
        XCTAssertNil(response.result[0].message)
    }

    func testTelegramMessageConversion() {
        let chatMsg = TelegramChat(id: 789)
        let fromUser = TelegramUser(id: 456, firstName: "Fang", username: "fangxu")
        let apiMsg = TelegramAPIMessage(
            messageId: 1,
            from: fromUser,
            chat: chatMsg,
            date: 1712300000,
            text: "/forward"
        )

        let msg = TelegramMessage(from: apiMsg)
        XCTAssertEqual(msg.chatId, 789)
        XCTAssertEqual(msg.text, "/forward")
        XCTAssertEqual(msg.fromUsername, "fangxu")
    }

    func testChatIdWhitelistFiltering() {
        let gateway = TelegramGateway(token: "fake")
        gateway.allowedChatIds = [789]

        XCTAssertTrue(gateway.isChatAllowed(789))
        XCTAssertFalse(gateway.isChatAllowed(999))
    }

    func testEmptyWhitelistAllowsNobody() {
        let gateway = TelegramGateway(token: "fake")
        gateway.allowedChatIds = []

        XCTAssertFalse(gateway.isChatAllowed(789))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh test`
Expected: FAIL — Telegram types not defined

- [ ] **Step 3: Implement TelegramGateway**

```swift
// metalbot-ios/Sources/Agent/TelegramGateway.swift
import Foundation

// MARK: - Telegram API Models (Decodable)

struct TelegramUser: Decodable {
    let id: Int64
    let firstName: String
    let username: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case username
    }
}

struct TelegramChat: Decodable {
    let id: Int64
}

struct TelegramAPIMessage: Decodable {
    let messageId: Int
    let from: TelegramUser?
    let chat: TelegramChat
    let date: Int
    let text: String?

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case from, chat, date, text
    }
}

struct TelegramUpdate: Decodable {
    let updateId: Int
    let message: TelegramAPIMessage?

    enum CodingKeys: String, CodingKey {
        case updateId = "update_id"
        case message
    }
}

struct TelegramUpdateResponse: Decodable {
    let ok: Bool
    let result: [TelegramUpdate]
}

// MARK: - App-level message model

struct TelegramMessage {
    let chatId: Int64
    let text: String
    let fromUsername: String?
    let date: Date

    init(from apiMessage: TelegramAPIMessage) {
        self.chatId = apiMessage.chat.id
        self.text = apiMessage.text ?? ""
        self.fromUsername = apiMessage.from?.username
        self.date = Date(timeIntervalSince1970: TimeInterval(apiMessage.date))
    }
}

// MARK: - Delegate

protocol TelegramGatewayDelegate: AnyObject {
    func gateway(_ gateway: TelegramGateway, didReceive message: TelegramMessage)
}

// MARK: - Gateway

final class TelegramGateway: ObservableObject {

    weak var delegate: TelegramGatewayDelegate?

    @Published var isPolling: Bool = false
    @Published var pollCount: Int = 0
    @Published var lastPollTime: Date?
    @Published var lastError: String?

    var allowedChatIds: Set<Int64> = []

    private let token: String
    private let session: URLSession
    private let pollTimeout: Int = 30
    private var offset: Int = 0
    private var pollTask: Task<Void, Never>?

    // Exponential backoff state
    private var backoffSeconds: TimeInterval = 0
    private let maxBackoff: TimeInterval = 30

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    deinit {
        stopPolling()
    }

    // MARK: - Polling

    func startPolling() {
        guard pollTask == nil else { return }
        isPolling = true
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            if backoffSeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
            }

            do {
                let updates = try await fetchUpdates()
                backoffSeconds = 0

                for update in updates {
                    offset = update.updateId + 1
                    guard let apiMessage = update.message else { continue }
                    let message = TelegramMessage(from: apiMessage)

                    guard isChatAllowed(message.chatId) else { continue }

                    await MainActor.run {
                        self.delegate?.gateway(self, didReceive: message)
                    }
                }

                await MainActor.run {
                    self.pollCount += 1
                    self.lastPollTime = Date()
                    self.lastError = nil
                }
            } catch {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.lastError = error.localizedDescription
                }
                backoffSeconds = min(max(backoffSeconds * 2, 1), maxBackoff)
            }
        }

        await MainActor.run {
            self.isPolling = false
        }
    }

    private func fetchUpdates() async throws -> [TelegramUpdate] {
        let urlString = "https://api.telegram.org/bot\(token)/getUpdates?offset=\(offset)&timeout=\(pollTimeout)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(TelegramUpdateResponse.self, from: data)
        return response.result
    }

    // MARK: - Send Reply

    func sendReply(chatId: Int64, text: String) async throws {
        let urlString = "https://api.telegram.org/bot\(token)/sendMessage"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["chat_id": chatId, "text": text]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, _) = try await session.data(for: request)
    }

    // MARK: - Authorization

    func isChatAllowed(_ chatId: Int64) -> Bool {
        allowedChatIds.contains(chatId)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh test`
Expected: All `TelegramGatewayTests` PASS

- [ ] **Step 5: Commit**

```bash
git add metalbot-ios/Sources/Agent/TelegramGateway.swift metalbot-ios/Tests/Agent/TelegramGatewayTests.swift
git commit -m "feat(agent): Add TelegramGateway with long polling and JSON parsing tests"
```

---

## Task 8: Stub Protocols (SkillRegistry and MemoryStore)

**Files:**
- Create: `metalbot-ios/Sources/Agent/SkillRegistry.swift`
- Create: `metalbot-ios/Sources/Agent/MemoryStore.swift`

- [ ] **Step 1: Implement SkillRegistry stub**

```swift
// metalbot-ios/Sources/Agent/SkillRegistry.swift
import Foundation

protocol SkillProviding {
    var name: String { get }
    var description: String { get }
    func execute(parameters: [String: Any]) -> ActionResult
}

protocol SkillRegistering {
    func register(_ skill: any SkillProviding)
    func skill(named name: String) -> (any SkillProviding)?
    var allSkills: [any SkillProviding] { get }
}

/// No-op stub for v1. Skills plug in here in future versions.
final class NoOpSkillRegistry: SkillRegistering {
    func register(_ skill: any SkillProviding) {}
    func skill(named name: String) -> (any SkillProviding)? { nil }
    var allSkills: [any SkillProviding] { [] }
}
```

- [ ] **Step 2: Implement MemoryStore stub**

```swift
// metalbot-ios/Sources/Agent/MemoryStore.swift
import Foundation

protocol MemoryStoring {
    func store(key: String, value: String)
    func recall(key: String) -> String?
    func allEntries() -> [(key: String, value: String)]
}

/// No-op stub for v1. Persistent memory in future versions.
final class NoOpMemoryStore: MemoryStoring {
    func store(key: String, value: String) {}
    func recall(key: String) -> String? { nil }
    func allEntries() -> [(key: String, value: String)] { [] }
}
```

- [ ] **Step 3: Verify build**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add metalbot-ios/Sources/Agent/SkillRegistry.swift metalbot-ios/Sources/Agent/MemoryStore.swift
git commit -m "feat(agent): Add SkillRegistry and MemoryStore stub protocols for future extension"
```

---

## Task 9: AgentRuntime with TDD

**Files:**
- Create: `metalbot-ios/Sources/Agent/AgentRuntime.swift`
- Create: `metalbot-ios/Tests/Agent/AgentRuntimeTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// metalbot-ios/Tests/Agent/AgentRuntimeTests.swift
import XCTest
@testable import metalbot

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
        let dispatcher = ActionDispatcher(
            goalReceiver: goalReceiver,
            statusProvider: StubStatusProvider()
        )
        runtime = AgentRuntime(
            interpreter: KeywordInterpreter(),
            dispatcher: dispatcher,
            responseBuilder: ResponseBuilder(),
            speech: speech
        )
    }

    func testForwardCommandProducesGoalAndSpeech() {
        let response = runtime.handleMessage("/forward")
        XCTAssertTrue(response.contains("forward"))
        XCTAssertEqual(speech.lastSpoken, response)
        if case .constantThrottle(let t) = goalReceiver.lastGoal {
            XCTAssertEqual(t, 0.4, accuracy: 0.001)
        } else {
            XCTFail("Expected constantThrottle goal")
        }
    }

    func testStopCommandResetsAndSpeaks() {
        let response = runtime.handleMessage("/stop")
        XCTAssertTrue(response.lowercased().contains("stop"))
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh test`
Expected: FAIL — `AgentRuntime` not defined

- [ ] **Step 3: Implement AgentRuntime**

```swift
// metalbot-ios/Sources/Agent/AgentRuntime.swift
import Foundation
import Combine

/// Orchestrates the full command pipeline: interpret → dispatch → respond → speak.
final class AgentRuntime: ObservableObject {

    // MARK: - Components

    private let interpreter: any CommandInterpreter
    private let dispatcher: any ActionDispatching
    private let responseBuilder: any ResponseBuilding
    private let speech: any SpeechOutputting

    // MARK: - Published State

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let rawText: String
        let action: AgentAction
        let response: String
    }

    @Published var log: [LogEntry] = []

    private let maxLogEntries = 20

    // MARK: - Init

    init(
        interpreter: any CommandInterpreter,
        dispatcher: any ActionDispatching,
        responseBuilder: any ResponseBuilding,
        speech: any SpeechOutputting
    ) {
        self.interpreter = interpreter
        self.dispatcher = dispatcher
        self.responseBuilder = responseBuilder
        self.speech = speech
    }

    // MARK: - Message Handling

    /// Process a raw text command and return the response string.
    @discardableResult
    func handleMessage(_ text: String) -> String {
        let action = interpreter.interpret(text)
        let result = dispatcher.dispatch(action)
        let response = responseBuilder.build(action: action, result: result)

        speech.speak(response)

        let entry = LogEntry(
            timestamp: Date(),
            rawText: text,
            action: action,
            response: response
        )
        appendLog(entry)

        return response
    }

    func clearLog() {
        log.removeAll()
    }

    private func appendLog(_ entry: LogEntry) {
        log.append(entry)
        if log.count > maxLogEntries {
            log.removeFirst(log.count - maxLogEntries)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh test`
Expected: All `AgentRuntimeTests` PASS

- [ ] **Step 5: Commit**

```bash
git add metalbot-ios/Sources/Agent/AgentRuntime.swift metalbot-ios/Tests/Agent/AgentRuntimeTests.swift
git commit -m "feat(agent): Add AgentRuntime orchestrator with full pipeline tests"
```

---

## Task 10: AgentDebugView

**Files:**
- Create: `metalbot-ios/Sources/Views/AgentDebugView.swift`

- [ ] **Step 1: Implement AgentDebugView**

This view follows the same forced-landscape, card-based pattern as `RaspberryPiControlView` and `STM32ControlView`. It uses the existing `GroupBox` card layout.

```swift
// metalbot-ios/Sources/Views/AgentDebugView.swift
import SwiftUI

struct AgentDebugView: View {

    @StateObject private var gateway: TelegramGateway
    @StateObject private var runtime: AgentRuntime
    private let speech: SpeechOutput

    @State private var tokenInput: String = ""
    @State private var manualInput: String = ""
    @State private var chatIdInput: String = ""
    @State private var isTokenSaved: Bool = false

    init() {
        let token = KeychainHelper.read(key: "telegram-bot-token") ?? ""
        let speechOutput = SpeechOutput()
        let gw = TelegramGateway(token: token)

        // In isolated debug mode, use a stub goal receiver.
        let dispatcher = ActionDispatcher(
            goalReceiver: StubGoalReceiver(),
            statusProvider: StubCarStatusProvider()
        )
        let rt = AgentRuntime(
            interpreter: KeywordInterpreter(),
            dispatcher: dispatcher,
            responseBuilder: ResponseBuilder(),
            speech: speechOutput
        )

        self._gateway = StateObject(wrappedValue: gw)
        self._runtime = StateObject(wrappedValue: rt)
        self.speech = speechOutput
        self._isTokenSaved = State(initialValue: !token.isEmpty)
    }

    var body: some View {
        List {
            tokenSection
            connectionSection
            lastMessageSection
            commandLogSection
            manualTestSection
        }
        .navigationTitle("Agent Diagnostics")
        .onAppear {
            gateway.delegate = GatewayBridge(runtime: runtime, gateway: gateway)
            loadAllowedChatIds()
        }
        .onDisappear {
            gateway.stopPolling()
        }
    }

    // MARK: - Sections

    private var tokenSection: some View {
        Section("Bot Token") {
            HStack {
                SecureField("Paste token from @BotFather", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Set") {
                    KeychainHelper.save(key: "telegram-bot-token", value: tokenInput)
                    isTokenSaved = true
                    tokenInput = ""
                }
                .disabled(tokenInput.isEmpty)
            }
            if isTokenSaved {
                Label("Token saved in Keychain", systemImage: "checkmark.shield.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
            HStack {
                TextField("Chat ID to allow", text: $chatIdInput)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                Button("Add") {
                    if let id = Int64(chatIdInput) {
                        gateway.allowedChatIds.insert(id)
                        saveChatIds()
                        chatIdInput = ""
                    }
                }
                .disabled(chatIdInput.isEmpty)
            }
            if !gateway.allowedChatIds.isEmpty {
                Text("Allowed: \(gateway.allowedChatIds.map(String.init).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            HStack {
                Circle()
                    .fill(gateway.isPolling ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(gateway.isPolling ? "Polling" : "Stopped")
                Spacer()
                Button(gateway.isPolling ? "Stop" : "Start") {
                    if gateway.isPolling {
                        gateway.stopPolling()
                    } else {
                        gateway.startPolling()
                    }
                }
                .disabled(!isTokenSaved)
            }
            MetricRow(label: "Poll Count", value: "\(gateway.pollCount)")
            if let time = gateway.lastPollTime {
                MetricRow(label: "Last Poll", value: timeString(time))
            }
            if let error = gateway.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var lastMessageSection: some View {
        Section("Last Message") {
            if let last = runtime.log.last {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Input: \(last.rawText)")
                        .font(.system(.body, design: .monospaced))
                    Text("Action: \(actionDescription(last.action))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Response: \(last.response)")
                        .font(.caption)
                }
            } else {
                Text("No messages yet")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var commandLogSection: some View {
        Section("Command Log") {
            if runtime.log.isEmpty {
                Text("Empty")
                    .foregroundColor(.secondary)
            } else {
                ForEach(runtime.log.reversed()) { entry in
                    HStack {
                        Text(timeString(entry.timestamp))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(entry.rawText)
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text(actionDescription(entry.action))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Button("Clear Log") {
                runtime.clearLog()
            }
        }
    }

    private var manualTestSection: some View {
        Section("Manual Test") {
            HStack {
                TextField("Type command (e.g. /forward)", text: $manualInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Send") {
                    runtime.handleMessage(manualInput)
                    manualInput = ""
                }
                .disabled(manualInput.isEmpty)
            }
            Toggle("TTS Enabled", isOn: Binding(
                get: { speech.isEnabled },
                set: { speech.isEnabled = $0 }
            ))
        }
    }

    // MARK: - Helpers

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }

    private func actionDescription(_ action: AgentAction) -> String {
        switch action {
        case .move(let dir, let t): return "move(\(dir.rawValue), \(t))"
        case .stop: return "stop"
        case .queryStatus: return "queryStatus"
        case .unknown(let raw): return "unknown(\(raw))"
        }
    }

    private func saveChatIds() {
        let ids = gateway.allowedChatIds.map(String.init).joined(separator: ",")
        KeychainHelper.save(key: "telegram-allowed-chats", value: ids)
    }

    private func loadAllowedChatIds() {
        guard let raw = KeychainHelper.read(key: "telegram-allowed-chats") else { return }
        let ids = raw.split(separator: ",").compactMap { Int64($0) }
        gateway.allowedChatIds = Set(ids)
    }
}

// MARK: - Stub dependencies for isolated debug mode

private final class StubGoalReceiver: GoalReceiving {
    func setGoal(_ goal: PlannerGoal) {}
    func reset() {}
}

private struct StubCarStatusProvider: StatusProviding {
    func currentStatus() -> String {
        "Debug mode — no hardware connected"
    }
}

// MARK: - Bridge: TelegramGatewayDelegate → AgentRuntime

private final class GatewayBridge: TelegramGatewayDelegate {
    let runtime: AgentRuntime
    let gateway: TelegramGateway

    init(runtime: AgentRuntime, gateway: TelegramGateway) {
        self.runtime = runtime
        self.gateway = gateway
    }

    func gateway(_ gw: TelegramGateway, didReceive message: TelegramMessage) {
        let response = runtime.handleMessage(message.text)
        Task {
            try? await gw.sendReply(chatId: message.chatId, text: response)
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add metalbot-ios/Sources/Views/AgentDebugView.swift
git commit -m "feat(agent): Add AgentDebugView for isolated subsystem testing"
```

---

## Task 11: Add Agent Diagnostics to HomeView

**Files:**
- Modify: `metalbot-ios/Sources/Views/HomeView.swift:140-205` (DiagnosticsView)

- [ ] **Step 1: Add Agent Diagnostics entry to DiagnosticsView**

In `HomeView.swift`, add a new section to `DiagnosticsView` after the "Control" section:

```swift
// Add this section inside DiagnosticsView's List, after the "Control" section:
Section("Agent") {
    diagRow(
        title: "Agent Diagnostics",
        subtitle: "Telegram bot & command pipeline",
        icon: "bubble.left.and.bubble.right.fill",
        color: .teal,
        destination: AgentDebugView()
    )
}
```

- [ ] **Step 2: Verify build**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add metalbot-ios/Sources/Views/HomeView.swift
git commit -m "feat(agent): Add Agent Diagnostics entry to HomeView DiagnosticsView"
```

---

## Task 12: Regenerate Xcode project and run full test suite

**Files:**
- Regenerate: `metalbot-ios/metalbot.xcodeproj`

- [ ] **Step 1: Regenerate Xcode project**

The new `Sources/Agent/` directory and `Tests/Agent/` directory need to be picked up by XcodeGen.

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh generate`
Expected: `metalbot.xcodeproj` regenerated with new Agent source and test files

- [ ] **Step 2: Run full test suite**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh test`
Expected: All tests pass — existing planner/safety tests plus all new Agent tests

- [ ] **Step 3: Build for device**

Run: `cd /Users/fxu/Projects/metalbot/metalbot-ios && ./build.sh build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit generated project if changed**

```bash
git add metalbot-ios/metalbot.xcodeproj
git commit -m "chore: Regenerate Xcode project with Agent sources and tests"
```
