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

    /// Vehicle speed from motor RPM (nil if ESC not connected or RPM zero).
    let motorSpeedMps: Double?

    /// Vehicle speed from ARKit pose differentiation (nil if not yet available).
    let arkitSpeedMps: Double?

    /// Monotonic timestamp (seconds).
    let timestamp: TimeInterval

    /// Best available speed estimate: motor RPM preferred, ARKit fallback.
    /// Returns nil if neither source is available or both report zero.
    var bestSpeedMps: Double? {
        if let motor = motorSpeedMps, motor > 0.01 { return motor }
        if let arkit = arkitSpeedMps, arkit > 0.01 { return arkit }
        return nil
    }
}
