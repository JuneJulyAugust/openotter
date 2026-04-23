import Foundation

enum MoveDirection: String, Equatable {
    case forward, backward, left, right
}

enum AgentAction: Equatable {
    case move(direction: MoveDirection, throttle: Float)
    case stop
    case queryStatus
    case setSpeed(throttle: Float)
    case help
    case unknown(raw: String)
}

struct ActionResult: Equatable {
    let success: Bool
    let message: String
    /// When false, AgentRuntime suppresses TTS for this result.
    /// Use for long-form responses (e.g. help text) that are unsuitable for speech.
    let speakable: Bool

    init(success: Bool, message: String, speakable: Bool = true) {
        self.success = success
        self.message = message
        self.speakable = speakable
    }
}
