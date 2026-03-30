import Foundation

/// Source of a control command — tracks provenance for UI and logging.
enum CommandSource: Equatable {
    case planner(String)
    case safetySupervisor
    case idle
}

/// Actuator command with provenance tracking.
struct ControlCommand: Equatable {
    let steering: Float     // [-1, +1]
    let throttle: Float     // [-1, +1]
    let source: CommandSource
    let reason: String?

    init(steering: Float, throttle: Float, source: CommandSource, reason: String? = nil) {
        self.steering = steering
        self.throttle = throttle
        self.source = source
        self.reason = reason
    }

    static let neutral = ControlCommand(steering: 0, throttle: 0, source: .idle)

    static func brake(reason: String) -> ControlCommand {
        ControlCommand(steering: 0, throttle: 0, source: .safetySupervisor, reason: reason)
    }
}
