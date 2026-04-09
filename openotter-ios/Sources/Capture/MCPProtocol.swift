import Foundation

/// Pure protocol formatting and parsing for MCP communication.
/// No I/O or Network framework dependencies — fully testable.
enum MCPProtocol {

    // MARK: - Message Formatting

    /// Format a heartbeat message with the given sequence number.
    /// Example: "hb_iphone:42"
    static func formatHeartbeat(seq: Int) -> String {
        "hb_iphone:\(seq)"
    }

    /// Format a control command message.
    /// Example: "cmd:s=0.50,m=-0.75"
    static func formatCommand(steering: Float, motor: Float) -> String {
        String(format: "cmd:s=%.2f,m=%.2f", steering, motor)
    }

    // MARK: - Message Parsing

    /// Returns true if the message is a Pi heartbeat response (starts with "hb_pi").
    static func isHeartbeatResponse(_ msg: String) -> Bool {
        msg.hasPrefix("hb_pi")
    }
}
