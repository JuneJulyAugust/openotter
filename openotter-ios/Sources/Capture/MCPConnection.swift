import Foundation
import Network

/// UDP connection transport layer for MCP communication.
/// Handles NWConnection lifecycle, receive loop, heartbeat timer, and timeout detection.
/// Delegates message interpretation to the caller via `onMessageReceived`.
final class MCPConnection {

    /// Called on the main queue when a message is received from the MCP Pi.
    var onMessageReceived: ((String) -> Void)?

    /// Called on the main queue when connection status changes.
    var onConnectionStatusChanged: ((Bool) -> Void)?

    private var connection: NWConnection?
    private var heartbeatTimer: Timer?
    private var timeoutTimer: Timer?

    private let host: String
    private let port: UInt16

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    deinit {
        disconnect()
    }

    // MARK: - Lifecycle

    func connect() {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        connection = NWConnection(to: endpoint, using: .udp)
        receiveLoop()
        connection?.start(queue: .global())
    }

    func disconnect() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        connection?.cancel()
        connection = nil
    }

    // MARK: - Sending

    /// Send raw message data over the UDP connection.
    func send(message: String) {
        guard let data = message.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("MCPConnection send error: \(error)")
            }
        }))
    }

    // MARK: - Heartbeat

    /// Start sending heartbeats at the specified interval.
    /// `formatMessage` is called each time to produce the heartbeat string.
    func startHeartbeat(interval: TimeInterval, formatMessage: @escaping () -> String) {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let msg = formatMessage()
            self.send(message: msg)
        }
    }

    // MARK: - Timeout

    /// Reset the connection timeout. If no message arrives within `interval` seconds,
    /// `onConnectionStatusChanged?(false)` is called.
    func resetTimeout(interval: TimeInterval = 1.5) {
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onConnectionStatusChanged?(false)
            }
        }
    }

    // MARK: - Private

    private func receiveLoop() {
        connection?.receiveMessage { [weak self] (data, _, _, error) in
            if let data = data, !data.isEmpty {
                let msg = String(decoding: data, as: UTF8.self)
                DispatchQueue.main.async {
                    self?.onMessageReceived?(msg)
                }
            }
            if error == nil {
                self?.receiveLoop()
            }
        }
    }
}
