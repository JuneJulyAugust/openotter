import XCTest
@testable import metalbot

// MARK: - Test Helpers

/// Shared factory for `PlannerContext` used across all planner/safety tests.
/// Centralizes context construction so test values are explicit and nothing is hidden.
enum PlannerTestFactory {

    /// Minimal pose at origin, facing forward, full confidence.
    static let defaultPose = PoseEntry(
        timestamp: 0,
        x: 0, y: 0, z: 0,
        yaw: 0,
        confidence: 1.0
    )

    /// Build a PlannerContext with sensible defaults — override only what your test cares about.
    static func context(
        timestamp: TimeInterval = 0,
        throttle: Float = 0,
        forwardDepth: Float? = nil,
        motorSpeedMps: Double? = nil,
        arkitSpeedMps: Double? = nil,
        pose: PoseEntry? = nil
    ) -> PlannerContext {
        let p = pose ?? PoseEntry(
            timestamp: timestamp,
            x: 0, y: 0, z: 0,
            yaw: 0,
            confidence: 1.0
        )
        return PlannerContext(
            pose: p,
            currentThrottle: throttle,
            escTelemetry: nil,
            forwardDepth: forwardDepth,
            motorSpeedMps: motorSpeedMps,
            arkitSpeedMps: arkitSpeedMps,
            timestamp: timestamp
        )
    }

    /// Build a forward-driving planner command (simulates what a planner would emit).
    static func forwardCommand(throttle: Float = 0.5, steering: Float = 0) -> ControlCommand {
        ControlCommand(steering: steering, throttle: throttle, source: .planner("TestPlanner"))
    }
}
