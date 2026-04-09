# Agent Runtime & Telegram Gateway — Design Spec

**Date:** 2026-04-05
**Status:** Draft
**Scope:** Add a Telegram-based remote command interface to openotter-ios, with an OpenClaw-inspired agent architecture that supports future LLM, skill, and memory subsystems.

---

## 1. Problem

The iPhone is mounted on the RC car. To arm/disarm or send commands, the user must physically walk to the car. We need a way to control the car remotely from another phone over the internet, without building a second app or hosting a webpage.

## 2. Solution Overview

Run a Telegram bot inside the openotter-ios app. The bot receives commands from Telegram (via long polling), interprets them through a swappable `CommandInterpreter`, dispatches actions through the existing planner/safety stack, and responds via both Telegram reply and on-device text-to-speech.

The architecture follows OpenClaw's pattern: messaging platform as UI, agent runtime as the brain, with placeholder interfaces for LLM interpretation, skills, and memory.

## 3. Design Principles

- **Agent as input source, not control path.** Every movement command flows through `PlannerOrchestrator` and `SafetySupervisor`. The safety stack is never bypassed.
- **No arm/disarm.** The system is always under software control. Commands are requests that the agent evaluates and dispatches.
- **Swap the parser, not the plumbing.** `CommandInterpreter` is a protocol. v1 uses keyword matching. Future versions swap in an LLM interpreter without changing any other component.
- **Develop in isolation, then integrate.** A standalone `AgentDebugView` tests the entire agent subsystem before wiring it into the main app flow.

## 4. System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                       openotter-ios app                           │
│                                                                  │
│  ┌─────────────────┐   ┌──────────────────────────────────────┐  │
│  │ TelegramGateway │   │           AgentRuntime               │  │
│  │                 │   │                                      │  │
│  │  pollLoop()   ──┼──▶│  ┌─────────────────────────────────┐ │  │
│  │  sendReply()  ◀─┼───│  │  CommandInterpreter (protocol)  │ │  │
│  │                 │   │  │   ├ KeywordInterpreter           │ │  │
│  │  Config:        │   │  │   └ LLMInterpreter (future)     │ │  │
│  │   token: Keychain   │  └──────────────┬──────────────────┘ │  │
│  │   timeout: 30s  │   │                 │                    │  │
│  │   interval: 0s  │   │  ┌──────────────▼──────────────────┐ │  │
│  │   (back-to-back)│   │  │  ActionDispatcher               │ │  │
│  └─────────────────┘   │  │   routes AgentAction to:        │ │  │
│                         │  │    • PlannerOrchestrator        │ │  │
│  ┌─────────────────┐   │  │    • Status queries             │ │  │
│  │  SpeechOutput   │   │  └──────────────┬──────────────────┘ │  │
│  │  (AVSpeech)     │◀──│                 │                    │  │
│  └─────────────────┘   │  ┌──────────────▼──────────────────┐ │  │
│                         │  │  ResponseBuilder                │ │  │
│  ┌─────────────────┐   │  │   formats result text           │─┼─▶ TTS + Reply
│  │ SkillRegistry   │   │  └─────────────────────────────────┘ │  │
│  │ (stub)          │◀──│                                      │  │
│  └─────────────────┘   │  ┌─────────────────────────────────┐ │  │
│                         │  │  MemoryStore (stub)             │ │  │
│  ┌─────────────────┐   │  └─────────────────────────────────┘ │  │
│  │ AgentDebugView  │   └──────────────────────────────────────┘  │
│  │  (diagnostic UI)│                                             │
│  └─────────────────┘                                             │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │                    App Core Layer                         │    │
│  │  PlannerOrchestrator ──▶ SafetySupervisor                │    │
│  │  STM32BleManager / ESCBleManager / ARKit Pose            │    │
│  └──────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

## 5. Data Flow

A command like "go forward" follows this path:

1. User sends `/forward` on Telegram from another phone.
2. `TelegramGateway` receives it via long poll, passes raw text to `AgentRuntime`.
3. `CommandInterpreter.interpret("/forward")` returns `AgentAction.move(direction: .forward, throttle: 0.4)`.
4. `ActionDispatcher` sets `PlannerGoal.constantThrottle(0.4)` on the orchestrator.
5. `PlannerOrchestrator` + `SafetySupervisor` handle execution (may reject if unsafe).
6. `ResponseBuilder` produces "Moving forward at 40% throttle" (or "Blocked: obstacle ahead, can only go backward").
7. `SpeechOutput` speaks the response aloud on the car's iPhone.
8. `TelegramGateway.sendReply()` sends the same text back to the Telegram chat.

## 6. Component Interfaces

### 6.1 AgentAction

```swift
enum MoveDirection {
    case forward, backward, left, right
}

enum AgentAction {
    case move(direction: MoveDirection, throttle: Float)
    case stop
    case queryStatus
    case unknown(raw: String)
}
```

### 6.2 CommandInterpreter (protocol)

```swift
protocol CommandInterpreter {
    func interpret(_ text: String) -> AgentAction
}
```

**v1: `KeywordInterpreter`** — maps slash commands to actions:

| Command     | AgentAction                             |
|:------------|:----------------------------------------|
| `/forward`  | `.move(direction: .forward, throttle: 0.4)` |
| `/backward` | `.move(direction: .backward, throttle: 0.4)` |
| `/stop`     | `.stop`                                 |
| `/status`   | `.queryStatus`                          |
| anything else | `.unknown(raw: text)`                |

**Future: `LLMInterpreter`** — sends text to a cloud LLM API, parses structured response into `AgentAction`. Same protocol, swapped in via dependency injection.

### 6.3 ActionDispatcher

```swift
struct ActionResult {
    let success: Bool
    let message: String
}

protocol ActionDispatching {
    func dispatch(_ action: AgentAction) -> ActionResult
}
```

Routes `AgentAction` to the App Core Layer. For movement actions, sets `PlannerGoal` on the orchestrator. For status queries, reads from ESC telemetry, ARKit pose, BLE connection state, etc.

### 6.4 TelegramGateway

```swift
protocol TelegramGatewayDelegate: AnyObject {
    func gateway(_ gateway: TelegramGateway, didReceive message: TelegramMessage)
}

struct TelegramMessage {
    let chatId: Int64
    let text: String
    let fromUsername: String?
    let date: Date
}
```

Owns the polling loop and send/reply. Pure I/O — no command logic.

### 6.5 ResponseBuilder

```swift
protocol ResponseBuilding {
    func build(action: AgentAction, result: ActionResult) -> String
}
```

Formats human-readable text from action + result. Separate from dispatch so the response style can evolve independently (e.g., terse for Telegram, verbose for TTS, or LLM-generated in the future).

### 6.6 SpeechOutput

```swift
protocol SpeechOutputting {
    func speak(_ text: String)
    var isEnabled: Bool { get set }
}
```

Wraps `AVSpeechSynthesizer`. Toggle-able for testing. Speaks on the car's iPhone speaker so the user nearby hears confirmations.

### 6.7 SkillRegistry (stub)

```swift
protocol SkillProviding {
    var name: String { get }
    var description: String { get }
    func execute(parameters: [String: Any]) -> ActionResult
}

protocol SkillRegistering {
    func register(_ skill: SkillProviding)
    func skill(named: String) -> SkillProviding?
    var allSkills: [SkillProviding] { get }
}
```

No-op implementation for v1. The interface exists so `AgentRuntime` can reference it, and future skills plug in without modifying existing code (OCP).

### 6.8 MemoryStore (stub)

```swift
protocol MemoryStoring {
    func store(key: String, value: String)
    func recall(key: String) -> String?
    func allEntries() -> [(key: String, value: String)]
}
```

No-op implementation for v1. Future: persistent key-value store for agent context across sessions.

## 7. Telegram Polling Strategy

| Parameter          | Value              | Rationale                                          |
|:-------------------|:-------------------|:---------------------------------------------------|
| Long poll timeout  | 30 seconds         | Telegram's recommended max. Blocks server-side.    |
| Poll interval      | 0 (back-to-back)   | Immediate re-poll for sub-second message latency.  |
| Retry on error     | Exponential backoff | 1s → 2s → 4s → 8s, capped at 30s. Resets on success. |
| Concurrency        | Single Swift `Task` | Cancellable via `isRunning` flag.                  |
| Allowed users      | Chat ID whitelist   | Only respond to authorized Telegram users.         |

## 8. Bot Token Management

- **Input:** Text field in `AgentDebugView`. User pastes token from `@BotFather`.
- **Storage:** iOS Keychain via `KeychainHelper`. Never in UserDefaults, files, or source code.
- **Access:** `TelegramGateway` reads token from Keychain at startup. If missing, gateway stays idle.
- **Security:** Chat ID whitelist prevents unauthorized users from controlling the car. The whitelist is configured in `AgentDebugView` — user sends `/start` to the bot, the debug view shows the chat ID, and the user taps to approve it. Approved IDs are stored in Keychain alongside the token.

## 9. Debug / Diagnostic UI

Standalone `AgentDebugView` — developed and tested in isolation before integration into the main app, following the same pattern as `RaspberryPiControlView` and `STM32ControlView`.

```
┌──────────────────────────────────────┐
│         Agent Diagnostics            │
├──────────────────────────────────────┤
│  Bot Token:  [••••••••••]  [Set]     │
│  Status:     ● Connected (polling)   │
│  Poll Count: 142                     │
│  Last Poll:  12:03:45                │
├──────────────────────────────────────┤
│  Last Message                        │
│  From: @fangxu                       │
│  Text: /forward                      │
│  Time: 12:03:42                      │
├──────────────────────────────────────┤
│  Interpreted Action                  │
│  AgentAction.move(.forward, 0.4)     │
│  Response: "Moving forward at 40%"   │
│  TTS: ✓ Spoken                       │
├──────────────────────────────────────┤
│  Command Log (recent 20)             │
│  12:03:42  /forward  → move(.fwd)   │
│  12:03:30  /status   → queryStatus   │
│  12:03:15  /stop     → stop          │
├──────────────────────────────────────┤
│  Manual Test                         │
│  [Type command here     ] [Send]     │
│  (bypasses Telegram, tests parser)   │
│                                      │
│  [TTS: ON]  [Clear Log]             │
└──────────────────────────────────────┘
```

Features:
- **Token input** — paste and save to Keychain
- **Connection status** — polling state, error count, last poll time
- **Live message log** — raw Telegram messages and interpreted actions
- **Manual test input** — type commands directly to test `CommandInterpreter` without Telegram
- **TTS toggle** — enable/disable speech during testing

## 10. Directory Structure

```
openotter-ios/Sources/Agent/
├── TelegramGateway.swift
├── AgentRuntime.swift
├── CommandInterpreter.swift
├── KeywordInterpreter.swift
├── AgentAction.swift
├── ActionDispatcher.swift
├── ResponseBuilder.swift
├── SpeechOutput.swift
├── SkillRegistry.swift
├── MemoryStore.swift
└── KeychainHelper.swift

openotter-ios/Sources/Views/
└── AgentDebugView.swift
```

## 11. Future Evolution

This design is the foundation for a physical AI agent:

| Phase   | What Changes                                  | What Stays the Same               |
|:--------|:----------------------------------------------|:----------------------------------|
| v1 (now)| KeywordInterpreter, stub skills/memory        | Everything else                   |
| v2      | Swap in LLMInterpreter (cloud API call)       | Gateway, Dispatcher, Safety stack |
| v3      | Implement SkillRegistry with real skills       | Gateway, Interpreter interface    |
| v4      | Implement MemoryStore with persistent storage  | All interfaces                    |
| v5      | LLM generates spoken responses via TTS         | Architecture                      |

Each phase adds new files. No existing files need modification (OCP).

## 12. Integration Plan

1. **Phase A — Isolated development:** Build and test `Agent/` subsystem with `AgentDebugView`. Manual test input validates the full interpret → dispatch → respond → speak pipeline without Telegram or BLE.
2. **Phase B — Telegram integration:** Connect `TelegramGateway` to real bot token. Test command round-trip from another phone.
3. **Phase C — App Core wiring:** Connect `ActionDispatcher` to real `PlannerOrchestrator` and `SafetySupervisor`. Test with car hardware.
4. **Phase D — Add navigation entry:** Add Agent Diagnostics to `HomeView` alongside existing subsystem views.
