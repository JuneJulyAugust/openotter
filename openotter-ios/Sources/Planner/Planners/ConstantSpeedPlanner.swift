import Foundation

// MARK: - Config

struct ConstantSpeedPlannerConfig {
    /// Maximum throttle change per second. Limits jerk on brake release.
    /// At 0.5/s, it takes 2 seconds to ramp from 0 to full throttle (1.0).
    var maxRampRatePerSecond: Float = 0.5
}

// MARK: - ConstantSpeedPlanner

/// Drives forward at a constant throttle with neutral steering.
///
/// Sends a raw open-loop motor command without feedback control.
/// Throttle changes are rate-limited to prevent instantaneous jumps that
/// would re-trigger the safety supervisor after a brake release.
final class ConstantSpeedPlanner: PlannerProtocol {

    let name = "ConstantThrottlePlanner"
    let config: ConstantSpeedPlannerConfig

    init(config: ConstantSpeedPlannerConfig = .init()) {
        self.config = config
    }

    // MARK: - State

    private var targetThrottle: Float = 0
    private var currentOutput: Float = 0
    private var lastTimestamp: TimeInterval?
    private var isActive: Bool = false

    // MARK: - PlannerProtocol

    func setGoal(_ goal: PlannerGoal) {
        reset()
        switch goal {
        case .constantThrottle(let throttle):
            targetThrottle = max(-1.0, min(1.0, throttle))
            isActive = true
        case .idle, .followWaypoints:
            break
        }
    }

    func plan(context: PlannerContext) -> ControlCommand {
        guard isActive else { return .neutral }

        let now = context.timestamp
        let output = rampedThrottle(target: targetThrottle, timestamp: now)

        return ControlCommand(
            steering: 0,   // neutral steering — drive straight
            throttle: output,
            source: .planner(name)
        )
    }

    func reset() {
        targetThrottle = 0
        currentOutput = 0
        lastTimestamp = nil
        isActive = false
    }

    // MARK: - Throttle Ramp

    /// Rate-limits throttle changes to `maxRampRatePerSecond × dt`.
    ///
    /// This ensures smooth acceleration after a safety brake release,
    /// giving the safety supervisor time to re-evaluate without the
    /// sudden throttle jump that would re-trigger braking.
    private func rampedThrottle(target: Float, timestamp: TimeInterval) -> Float {
        guard let lastTs = lastTimestamp else {
            // First tick — start from zero, don't jump.
            lastTimestamp = timestamp
            return currentOutput
        }

        let dt = Float(timestamp - lastTs)
        lastTimestamp = timestamp

        guard dt > 0, dt < 1.0 else {
            // Guard against stale or absurd dt (e.g. after pause/resume).
            // Don't change output on bad timing.
            return currentOutput
        }

        let maxDelta = config.maxRampRatePerSecond * dt
        let delta = target - currentOutput
        let clampedDelta = max(-maxDelta, min(maxDelta, delta))
        currentOutput += clampedDelta

        return currentOutput
    }
}
