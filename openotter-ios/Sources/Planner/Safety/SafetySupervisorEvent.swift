import Foundation

/// Notification from the safety supervisor about its latest decision.
struct SafetySupervisorEvent: Equatable {
    let timestamp: TimeInterval
    let ttc: Float              // seconds (based on filtered values)
    let forwardDepth: Float     // raw depth in meters
    let filteredDepth: Float    // EMA-smoothed depth in meters

    enum Action: Equatable {
        case clear
        case caution(throttleScale: Float, reason: String)
        case brakeApplied(String)
    }

    let action: Action

    /// True when the supervisor is actively overriding the planner (BRAKE or CAUTION).
    var isOverriding: Bool {
        switch action {
        case .clear: return false
        case .caution, .brakeApplied: return true
        }
    }

    /// True only when in full-stop BRAKE state.
    var isBraking: Bool {
        if case .brakeApplied = action { return true }
        return false
    }
}
