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
