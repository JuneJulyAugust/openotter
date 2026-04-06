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
    let result: [TelegramUpdate]?          // nil on error responses
    let description: String?               // Telegram error description (e.g. "Unauthorized")
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

    /// Most recent chat ID seen, even if not yet whitelisted. Shown in UI for easy approval.
    @Published var lastSeenChatId: Int64?
    @Published var lastSeenUsername: String?

    var allowedChatIds: Set<Int64> = []

    private var token: String
    private let session: URLSession
    private let pollTimeout: Int = 30
    private var offset: Int = 0
    private var pollTask: Task<Void, Never>?

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

    /// Replace the token and reset poll state. Call before startPolling() after a token change.
    func updateToken(_ newToken: String) {
        stopPolling()
        token = newToken
        offset = 0
        backoffSeconds = 0
        lastError = nil
        pollCount = 0
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

                    // Always record the last seen chat ID — useful for first-time whitelist setup.
                    await MainActor.run {
                        self.lastSeenChatId = message.chatId
                        self.lastSeenUsername = message.fromUsername
                    }

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
        guard response.ok, let updates = response.result else {
            let desc = response.description ?? "Unknown Telegram error"
            throw NSError(domain: "TelegramGateway", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: desc])
        }
        return updates
    }

    // MARK: - Reply Keyboard

    /// Persistent buttons shown at the bottom of the Telegram chat.
    /// Users tap instead of typing. Labels are matched by KeywordInterpreter aliases.
    private static func replyMarkup() -> [String: Any] {
        let buttons: [[[String: String]]] = [
            [["text": "🚗 Drive"], ["text": "🅿️ Park"]],
            [["text": "🔙 Reverse"], ["text": "📊 Status"]],
        ]
        return [
            "keyboard": buttons,
            "resize_keyboard": true,
            "one_time_keyboard": false,
            "is_persistent": true,
        ]
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

        let body: [String: Any] = [
            "chat_id": chatId,
            "text": text,
            "reply_markup": Self.replyMarkup(),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, _) = try await session.data(for: request)
    }

    // MARK: - Authorization

    func isChatAllowed(_ chatId: Int64) -> Bool {
        allowedChatIds.contains(chatId)
    }
}
