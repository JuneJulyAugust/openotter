import SwiftUI

struct AgentDebugView: View {

    @StateObject private var gateway: TelegramGateway
    @StateObject private var runtime: AgentRuntime
    private let speech: SpeechOutput

    // Strongly held so the weak delegate on TelegramGateway is not immediately released.
    @State private var bridge: GatewayBridge?

    @State private var tokenInput: String = ""
    @State private var manualInput: String = ""
    @State private var chatIdInput: String = ""
    @State private var isTokenSaved: Bool = false

    init() {
        let token = KeychainHelper.read(key: "telegram-bot-token") ?? ""
        let speechOutput = SpeechOutput()
        let gw = TelegramGateway(token: token)

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
            let b = GatewayBridge(runtime: runtime, gateway: gateway)
            bridge = b
            gateway.delegate = b
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
                    let trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    KeychainHelper.save(key: "telegram-bot-token", value: trimmed)
                    gateway.updateToken(trimmed)
                    isTokenSaved = true
                    tokenInput = ""
                }
                .disabled(tokenInput.isEmpty)
            }
            if isTokenSaved {
                HStack {
                    Label("Token saved in Keychain", systemImage: "checkmark.shield.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Spacer()
                    Button("Reset") {
                        KeychainHelper.delete(key: "telegram-bot-token")
                        gateway.updateToken("")
                        isTokenSaved = false
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
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
            if let seenId = gateway.lastSeenChatId,
               !gateway.allowedChatIds.contains(seenId) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Seen chat ID: \(seenId)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.orange)
                        if let username = gateway.lastSeenUsername {
                            Text("@\(username)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button("Allow") {
                        gateway.allowedChatIds.insert(seenId)
                        saveChatIds()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
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

