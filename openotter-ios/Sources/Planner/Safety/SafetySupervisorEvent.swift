import Foundation

/// Snapshot captured the instant the supervisor transitions SAFE → BRAKE.
struct SafetyBrakeTrigger {
    let timestamp: TimeInterval
    let pose: PoseEntry
    let speed: Float                // latched speed at trigger (m/s)
    let depth: Float                // smoothed depth at trigger (m)
    let criticalDistance: Float     // D_crit(speed) at trigger (m)
    let motorSpeed: Float           // raw motor-derived speed (m/s), NaN if unavailable
    let arkitSpeed: Float           // raw ARKit-derived speed (m/s), NaN if unavailable
}

/// Snapshot captured the first frame inside a BRAKE episode where the robot is actually stopped.
struct SafetyBrakeStop {
    let timestamp: TimeInterval
    let pose: PoseEntry
    let depth: Float                // smoothed depth when motion ceased (m)
}

/// Joint record for one BRAKE episode: trigger + (optional) stop + derived quantities.
/// Exists only while the supervisor is in BRAKE (cleared on release).
struct SafetyBrakeRecord {
    let trigger: SafetyBrakeTrigger
    var stop: SafetyBrakeStop?

    /// Wall-clock time from trigger to robot standstill. Nil until `stop` is captured.
    var stoppingTimeS: TimeInterval? {
        stop.map { $0.timestamp - trigger.timestamp }
    }

    /// Planar distance from the trigger pose to the stop pose (meters).
    var stoppingDistanceM: Float? {
        guard let stop else { return nil }
        let dx = stop.pose.x - trigger.pose.x
        let dy = stop.pose.y - trigger.pose.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Mean deceleration to stop (m/s²). Nil until `stop` is captured or when stopping time is degenerate.
    var actualDecelMPS2: Float? {
        guard let t = stoppingTimeS, t > 1e-3 else { return nil }
        return trigger.speed / Float(t)
    }

    /// How much closer to the obstacle the robot ended up vs. the moment BRAKE engaged.
    /// Positive = robot moved toward obstacle after trigger (typical). Nil until stop captured.
    var brakingDistanceM: Float? {
        guard let stop else { return nil }
        return trigger.depth - stop.depth
    }
}

/// Per-tick diagnostic. Emitted by the supervisor on every call to `supervise(...)`.
struct SafetySupervisorEvent: Equatable {
    let timestamp: TimeInterval
    let rawDepth: Float
    let smoothedDepth: Float
    /// Speed used to compute `criticalDistance` this tick.
    /// While SAFE: current speed. While BRAKE: latched speed (frozen at trigger).
    let speed: Float
    let criticalDistance: Float
    let isBraking: Bool
    let reason: String?
}
