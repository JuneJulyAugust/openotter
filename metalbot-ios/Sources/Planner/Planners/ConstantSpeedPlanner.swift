import Foundation

/// Drives forward at a constant target speed with neutral steering.
///
/// Uses a discrete PI controller to convert the speed error (target - measured)
/// into a throttle command. The integrator is clamped to prevent windup.
///
/// Speed source priority: motor RPM > ARKit > open-loop ramp.
final class ConstantSpeedPlanner: PlannerProtocol {

    let name = "ConstantSpeedPlanner"

    // MARK: - PI Gains

    /// Proportional gain: throttle fraction per (m/s) error.
    private let kP: Float = 1.0
    /// Integral gain: throttle fraction per (m/s * s) accumulated error.
    private let kI: Float = 0.3
    /// Anti-windup clamp for the integrator (throttle-seconds).
    private let integralLimit: Float = 0.5

    // MARK: - State

    private var targetMps: Float = 0
    private var integralError: Float = 0
    private var lastTimestamp: TimeInterval?
    private var isActive: Bool = false

    // MARK: - PlannerProtocol

    func setGoal(_ goal: PlannerGoal) {
        reset()
        switch goal {
        case .constantSpeed(let target):
            targetMps = target
            isActive = true
        case .idle, .followWaypoints:
            break
        }
    }

    func plan(context: PlannerContext) -> ControlCommand {
        guard isActive else { return .neutral }

        let dt = computeDt(timestamp: context.timestamp)
        let measuredSpeed = Float(context.bestSpeedMps ?? 0)
        let error = targetMps - measuredSpeed

        // Integrate with anti-windup clamp
        integralError += error * dt
        integralError = max(-integralLimit, min(integralLimit, integralError))

        let output = kP * error + kI * integralError
        // Clamp throttle to [-1, 1] range
        let throttle = max(-1.0, min(1.0, output))

        return ControlCommand(
            steering: 0, // neutral steering — drive straight
            throttle: throttle,
            source: .planner(name)
        )
    }

    func reset() {
        targetMps = 0
        integralError = 0
        lastTimestamp = nil
        isActive = false
    }

    // MARK: - Private

    private func computeDt(timestamp: TimeInterval) -> Float {
        defer { lastTimestamp = timestamp }
        guard let prev = lastTimestamp else { return 0 }
        let dt = timestamp - prev
        // Cap dt to avoid integral spikes after pauses
        return Float(min(dt, 0.1))
    }
}
