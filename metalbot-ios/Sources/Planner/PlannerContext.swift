import Foundation

/// Immutable sensor snapshot passed to the planner and safety supervisor each tick.
struct PlannerContext {
    /// Robot 6D pose in ARKit world frame.
    let pose: PoseEntry

    /// Last commanded throttle [-1, +1] (speed proxy until wheel calibration).
    let currentThrottle: Float

    /// ESC telemetry (nil if BLE not connected).
    let escTelemetry: ESCTelemetry?

    /// Center-pixel depth from LiDAR in meters (nil if depth unavailable).
    let forwardDepth: Float?

    /// Monotonic timestamp (seconds).
    let timestamp: TimeInterval
}
