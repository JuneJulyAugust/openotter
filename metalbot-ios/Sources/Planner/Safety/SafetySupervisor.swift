import Foundation

// MARK: - Config

struct SafetySupervisorConfig {
    /// Assumed robot speed in m/s (placeholder until wheel calibration — see TODO P-02).
    var assumedSpeedMPS: Float = 2.0
    /// Brake unconditionally when TTC falls below this threshold.
    var ttcCriticalS: Float = 1.0
    /// Avoid division by zero at standstill.
    var minSpeedEpsilonMPS: Float = 0.01
}

// MARK: - SafetySupervisor

/// Monitors forward depth and overrides planner commands when collision is imminent.
///
/// Interface: `supervise(command:context:) → ControlCommand`
/// — returns the command unchanged if safe, or `.brake` if TTC is critical.
/// Extending the supervisor (e.g. adding a warning level) only requires
/// modifying this class; the interface is unchanged.
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

        let ttc = computeTTC(depth: depth)
        let event = makeEvent(ttc: ttc, depth: depth, context: context)
        lastEvent = event

        if ttc < config.ttcCriticalS {
            let reason = String(format: "TTC %.2fs (d=%.2fm)", ttc, depth)
            return .brake(reason: reason)
        }
        return command
    }

    func reset() {
        lastEvent = nil
    }

    // MARK: - Private Helpers

    /// Pass command through with a .clear event so the UI always has a fresh TTC reading.
    private func passThrough(_ command: ControlCommand, context: PlannerContext) -> ControlCommand {
        if let depth = validDepth(from: context) {
            lastEvent = makeEvent(ttc: computeTTC(depth: depth), depth: depth, context: context)
        } else {
            lastEvent = nil
        }
        return command
    }

    /// Returns a positive, finite depth or nil.
    private func validDepth(from context: PlannerContext) -> Float? {
        guard let d = context.forwardDepth, d > 0, d.isFinite else { return nil }
        return d
    }

    /// TTC = depth / speed, guarded against zero speed.
    private func computeTTC(depth: Float) -> Float {
        depth / max(config.assumedSpeedMPS, config.minSpeedEpsilonMPS)
    }

    private func makeEvent(ttc: Float, depth: Float, context: PlannerContext) -> SafetySupervisorEvent {
        let action: SafetySupervisorEvent.Action = ttc < config.ttcCriticalS
            ? .brakeApplied(String(format: "TTC %.2fs (d=%.2fm)", ttc, depth))
            : .clear
        return SafetySupervisorEvent(timestamp: context.timestamp, ttc: ttc, forwardDepth: depth, action: action)
    }
}
