import Foundation

struct KeywordInterpreter: CommandInterpreter {

    private static let defaultThrottle: Float = 0.4

    /// Canonical action for each alias.
    /// Multiple keys map to the same action — single source of truth.
    ///
    /// Note: `r` maps to reverse (matches Telegram button).
    /// "right" requires the full word since single-letter conflicts.
    private static let aliases: [String: AgentAction] = {
        let t = defaultThrottle
        let forward  = AgentAction.move(direction: .forward,  throttle: t)
        let backward = AgentAction.move(direction: .backward, throttle: t)
        let left     = AgentAction.move(direction: .left,     throttle: t)
        let right    = AgentAction.move(direction: .right,    throttle: t)
        let stop     = AgentAction.stop
        let status   = AgentAction.queryStatus

        return [
            // Slash commands
            "/forward": forward,  "/backward": backward,
            "/left": left,        "/right": right,
            "/stop": stop,        "/status": status,
            "/drive": forward,    "/reverse": backward,
            "/park": stop,
            "/d": forward,        "/r": backward,
            "/l": left,           "/p": stop,
            "/s": status,

            // Bare words
            "forward": forward,   "backward": backward,
            "left": left,         "right": right,
            "stop": stop,         "status": status,

            // Friendly names
            "drive": forward,     "reverse": backward,
            "park": stop,         "go": forward,

            // Single-letter shortcuts
            "d": forward,         "r": backward,
            "l": left,            "p": stop,
            "s": status,
        ]
    }()

    func interpret(_ text: String) -> AgentAction {
        // Keep only ASCII characters — strips all emoji and variation selectors.
        // "🚗 Drive" → " Drive" → trimmed → "drive"
        // "🅿️ Park"  → " Park"  → trimmed → "park"
        let ascii = String(text.unicodeScalars.filter { $0.isASCII })
        let command = ascii.trimmingCharacters(in: .whitespaces).lowercased()
        return Self.aliases[command] ?? .unknown(raw: text)
    }
}
