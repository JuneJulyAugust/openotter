import Foundation

/// Notification from the safety supervisor about its latest decision.
struct SafetySupervisorEvent: Equatable {
    let timestamp: TimeInterval
    let ttc: Float              // seconds
    let forwardDepth: Float     // meters

    enum Action: Equatable {
        case clear
        case brakeApplied(String)
    }

    let action: Action
}
