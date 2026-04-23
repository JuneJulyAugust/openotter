import Foundation

/// Parses raw Telegram text into an `AgentAction`.
///
/// Stateful: holds the current throttle magnitude so that subsequent
/// move commands (`drive`, `reverse`, etc.) use the most recently set
/// speed. The default is 0.4 (40% throttle).
///
/// Speed can be changed via:
/// - Text:    `speed 0.6`, `/speed 0.3`
/// - Buttons: `🐢 Slow` (0.3), `🐇 Fast` (0.6)
final class KeywordInterpreter: CommandInterpreter {

    /// Current throttle magnitude [0.1, 1.0]. Drives all subsequent move commands.
    private(set) var currentThrottle: Float = 0.4

    /// Clamp and store a new throttle value.
    func setThrottle(_ value: Float) {
        currentThrottle = min(max(value, 0.1), 1.0)
    }

    private static let speedRange: ClosedRange<Float> = 0.1...1.0

    // MARK: - Static alias table (throttle placeholder = 0, patched at interpret time)

    /// Canonical action for each alias.
    /// Multiple keys map to the same action — single source of truth.
    ///
    /// Note: `r` maps to reverse (matches Telegram button).
    /// "right" requires the full word since single-letter conflicts.
    private static let aliases: [String: AgentAction] = {
        // Throttle is a placeholder — interpret() patches it with currentThrottle.
        let forward  = AgentAction.move(direction: .forward,  throttle: 0)
        let backward = AgentAction.move(direction: .backward, throttle: 0)
        let left     = AgentAction.move(direction: .left,     throttle: 0)
        let right    = AgentAction.move(direction: .right,    throttle: 0)
        let stop     = AgentAction.stop
        let status   = AgentAction.queryStatus
        let help     = AgentAction.help

        return [
            // Slash commands
            "/forward": forward,  "/backward": backward,
            "/left": left,        "/right": right,
            "/stop": stop,        "/status": status,
            "/drive": forward,    "/reverse": backward,
            "/park": stop,        "/help": help,
            "/d": forward,        "/r": backward,
            "/l": left,           "/p": stop,
            "/s": status,         "/h": help,

            // Bare words
            "forward": forward,   "backward": backward,
            "left": left,         "right": right,
            "stop": stop,         "status": status,
            "help": help,

            // Friendly names
            "drive": forward,     "reverse": backward,
            "park": stop,         "go": forward,

            // Single-letter shortcuts
            "d": forward,         "r": backward,
            "l": left,            "p": stop,
            "s": status,          "h": help,

            // Speed preset buttons (emoji stripped by interpret())
            "slow": .setSpeed(throttle: 0.2),
            "normal": .setSpeed(throttle: 0.4),
            "fast": .setSpeed(throttle: 0.8),
        ]
    }()

    // MARK: - Interpret

    func interpret(_ text: String) -> AgentAction {
        // Strip non-ASCII (emoji / variation selectors).
        // "🚗 Drive" → " Drive" → trimmed → "drive"
        let ascii = String(text.unicodeScalars.filter { $0.isASCII })
        let command = ascii.trimmingCharacters(in: .whitespaces).lowercased()

        // Parse "speed <value>" or "/speed <value>"
        if let speedAction = parseSpeedCommand(command) {
            return speedAction
        }

        guard let action = Self.aliases[command] else {
            return .unknown(raw: text)
        }

        // Patch placeholder throttle with current live value.
        if case .move(let direction, _) = action {
            return .move(direction: direction, throttle: currentThrottle)
        }
        return action
    }

    // MARK: - Speed Parsing

    /// Matches `speed 0.6`, `/speed 0.3`, `speed0.5` (no space).
    /// Returns nil if the text doesn't match the speed pattern.
    private func parseSpeedCommand(_ command: String) -> AgentAction? {
        let prefix = command.hasPrefix("/speed") ? "/speed" : (command.hasPrefix("speed") ? "speed" : nil)
        guard let prefix else { return nil }
        let remainder = command.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard let value = Float(remainder) else { return nil }
        let clamped = min(max(value, Self.speedRange.lowerBound), Self.speedRange.upperBound)
        return .setSpeed(throttle: clamped)
    }
}
