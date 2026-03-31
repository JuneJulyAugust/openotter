import Foundation

// MARK: - Config

struct SafetySupervisorConfig {
    /// Fallback speed if no sensor data available (conservative estimate).
    var fallbackSpeedMPS: Float = 0.5
    /// Brake unconditionally when TTC falls below this threshold.
    var ttcCriticalS: Float = 1.0
    /// Avoid division by zero at standstill.
    var minSpeedEpsilonMPS: Float = 0.01
}

// MARK: - SafetySupervisor

/// Monitors forward depth and overrides planner commands when collision is imminent.
///
/// TTC uses real speed from motor RPM (primary) or ARKit (fallback).
/// If neither is available, falls back to a conservative fixed estimate.
final class SafetySupervisor {

    let config: SafetySupervisorConfig
    private(set) var lastEvent: SafetySupervisorEvent?

    init(config: SafetySupervisorConfig = .init()) {
        self.config = config
    }

    // MARK: - Public

    func supervise(command: ControlCommand, context: PlannerContext) -> ControlCommand {
        guard command.source != .safetySupervisor else { return command }
        guard command.throttle > 0 else { return passThrough(command, context: context) }
        guard let depth = validDepth(from: context) else { return command }

        let speed = resolveSpeed(context: context)
        let ttc = depth / speed
        let event = makeEvent(ttc: ttc, depth: depth, context: context)
        lastEvent = event

        if ttc < config.ttcCriticalS {
            let reason = String(format: "TTC %.2fs (d=%.2fm, v=%.2fm/s)", ttc, depth, speed)
            return .brake(reason: reason)
        }
        return command
    }

    func reset() {
        lastEvent = nil
    }

    // MARK: - Private Helpers

    private func passThrough(_ command: ControlCommand, context: PlannerContext) -> ControlCommand {
        if let depth = validDepth(from: context) {
            let speed = resolveSpeed(context: context)
            lastEvent = makeEvent(ttc: depth / speed, depth: depth, context: context)
        } else {
            lastEvent = nil
        }
        return command
    }

    private func validDepth(from context: PlannerContext) -> Float? {
        guard let d = context.forwardDepth, d > 0, d.isFinite else { return nil }
        return d
    }

    /// Motor RPM speed preferred, then ARKit, then conservative fallback.
    private func resolveSpeed(context: PlannerContext) -> Float {
        if let best = context.bestSpeedMps, best > Double(config.minSpeedEpsilonMPS) {
            return Float(best)
        }
        return max(config.fallbackSpeedMPS, config.minSpeedEpsilonMPS)
    }

    private func makeEvent(ttc: Float, depth: Float, context: PlannerContext) -> SafetySupervisorEvent {
        let action: SafetySupervisorEvent.Action = ttc < config.ttcCriticalS
            ? .brakeApplied(String(format: "TTC %.2fs (d=%.2fm)", ttc, depth))
            : .clear
        return SafetySupervisorEvent(timestamp: context.timestamp, ttc: ttc, forwardDepth: depth, action: action)
    }
}
