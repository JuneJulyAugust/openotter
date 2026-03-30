import Foundation

// MARK: - Config

struct WaypointPlannerConfig {
    /// Steering fraction applied at a 90° heading error (0–1).
    /// Full deflection would be 1.0; 0.6 gives smoother response.
    var steeringFractionAt90Deg: Float = 0.6

    /// Derived gain: maps heading error (rad) → steering fraction.
    var steeringGain: Float { steeringFractionAt90Deg / (.pi / 2) }
}

// MARK: - WaypointPlanner

/// Straight-line waypoint follower with proportional heading control.
///
/// Steering is proportional to heading error.
/// Throttle fades toward zero as the turn sharpens, preventing high-speed cornering.
final class WaypointPlanner: PlannerProtocol {

    let name = "WaypointPlanner"
    let config: WaypointPlannerConfig

    init(config: WaypointPlannerConfig = .init()) {
        self.config = config
    }

    // MARK: - State

    private var waypoints: [Waypoint] = []
    private var maxThrottle: Float = 0
    private var currentIndex: Int = 0

    // MARK: - PlannerProtocol

    func setGoal(_ goal: PlannerGoal) {
        reset()
        switch goal {
        case .idle: break
        case .followWaypoints(let wps, let throttle):
            waypoints = wps
            maxThrottle = throttle
        }
    }

    func plan(context: PlannerContext) -> ControlCommand {
        guard !waypoints.isEmpty, currentIndex < waypoints.count else { return .neutral }

        let target = waypoints[currentIndex]

        if hasReached(target: target, pose: context.pose) {
            currentIndex += 1
            return plan(context: context) // recurse for next waypoint
        }

        let yawError = headingError(to: target, from: context.pose)
        return ControlCommand(
            steering: steeringOutput(for: yawError),
            throttle: throttleOutput(for: yawError),
            source: .planner(name)
        )
    }

    func reset() {
        waypoints = []
        maxThrottle = 0
        currentIndex = 0
    }

    // MARK: - Private

    private func hasReached(target: Waypoint, pose: PoseEntry) -> Bool {
        groundDistance(ax: pose.x, az: pose.z, bx: target.x, bz: target.z) < target.acceptanceRadius
    }

    private func headingError(to target: Waypoint, from pose: PoseEntry) -> Float {
        let dx = target.x - pose.x
        let dz = target.z - pose.z
        let desired = atan2f(dx, -dz)
        return (desired - pose.yaw).wrapToPi()
    }

    private func steeringOutput(for yawError: Float) -> Float {
        max(-1, min(1, config.steeringGain * yawError))
    }

    /// Throttle fades to zero at 180° error; full throttle when heading is aligned.
    private func throttleOutput(for yawError: Float) -> Float {
        maxThrottle * (1.0 - abs(yawError) / .pi)
    }
}

// MARK: - Geometry (ground plane only)

private func groundDistance(ax: Float, az: Float, bx: Float, bz: Float) -> Float {
    let dx = bx - ax
    let dz = bz - az
    return sqrtf(dx * dx + dz * dz)
}
