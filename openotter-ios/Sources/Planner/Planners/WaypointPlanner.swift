import Foundation

// MARK: - Config

struct WaypointPlannerConfig {
    /// Steering fraction applied at a 90° heading error (0–1).
    /// Full deflection would be 1.0; 0.6 gives smoother response.
    var steeringFractionAt90Deg: Float = 0.6

    /// Keep enough throttle through normal turns that the car does not stall
    /// while the heading loop is still converging.
    var minimumThrottleFraction: Float = 0.35

    /// If the target is almost behind the car, hold throttle at zero instead
    /// of pushing forward into a U-turn.
    var maxPoweredHeadingError: Float = 5 * .pi / 6

    /// Derived gain: maps heading error (rad) → steering fraction.
    var steeringGain: Float { steeringFractionAt90Deg / (.pi / 2) }
}

protocol WaypointDebugProviding: AnyObject {
    var activeWaypoints: [Waypoint] { get }
    var currentWaypointIndex: Int { get }
}

// MARK: - WaypointPlanner

/// Straight-line waypoint follower with proportional heading control.
///
/// Steering is proportional to heading error.
/// Throttle fades toward zero as the turn sharpens, preventing high-speed cornering.
final class WaypointPlanner: PlannerProtocol, WaypointDebugProviding {

    let name = "WaypointPlanner"
    let config: WaypointPlannerConfig

    init(config: WaypointPlannerConfig = .init()) {
        self.config = config
    }

    // MARK: - State

    private var waypoints: [Waypoint] = []
    private var maxThrottle: Float = 0
    private var currentIndex: Int = 0
    private var isClosedLoop: Bool = false
    private var pendingFigureEightConfig: FigureEightTrajectory.Config?

    var activeWaypoints: [Waypoint] { waypoints }
    var currentWaypointIndex: Int { currentIndex }

    // MARK: - PlannerProtocol

    func setGoal(_ goal: PlannerGoal) {
        reset()
        switch goal {
        case .idle: break
        case .followWaypoints(let wps, let throttle):
            waypoints = wps
            maxThrottle = throttle
            isClosedLoop = false
        case .followFigureEight(let config, let throttle):
            pendingFigureEightConfig = config
            maxThrottle = throttle
            isClosedLoop = true
        case .constantThrottle:
            break // Not handled by WaypointPlanner
        }
    }

    func plan(context: PlannerContext) -> ControlCommand {
        materializePendingFigureEightIfNeeded(anchor: context.pose)
        guard !waypoints.isEmpty, currentIndex < waypoints.count else { return .neutral }

        advanceReachedWaypoints(from: context.pose)
        guard currentIndex < waypoints.count else { return .neutral }

        let target = waypoints[currentIndex]

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
        isClosedLoop = false
        pendingFigureEightConfig = nil
    }

    // MARK: - Private

    private func materializePendingFigureEightIfNeeded(anchor: PoseEntry) {
        guard let pendingFigureEightConfig else { return }
        waypoints = FigureEightTrajectory.waypoints(config: pendingFigureEightConfig, anchor: anchor)
        currentIndex = 0
        self.pendingFigureEightConfig = nil
    }

    private func advanceReachedWaypoints(from pose: PoseEntry) {
        var checkedCount = 0
        while !waypoints.isEmpty,
              currentIndex < waypoints.count,
              checkedCount < waypoints.count,
              hasReached(target: waypoints[currentIndex], pose: pose) {
            currentIndex += 1
            if isClosedLoop, currentIndex >= waypoints.count {
                currentIndex = 0
            }
            checkedCount += 1
        }

        if !isClosedLoop,
           checkedCount >= waypoints.count,
           currentIndex < waypoints.count,
           hasReached(target: waypoints[currentIndex], pose: pose) {
            currentIndex = waypoints.count
        }
    }

    private func hasReached(target: Waypoint, pose: PoseEntry) -> Bool {
        groundDistance(ax: pose.x, az: pose.z, bx: target.x, bz: target.z) < target.acceptanceRadius
    }

    private func headingError(to target: Waypoint, from pose: PoseEntry) -> Float {
        let dx = target.x - pose.x
        let dz = target.z - pose.z
        let desired = atan2f(-dz, dx)
        return (desired - pose.yaw).wrapToPi()
    }

    private func steeringOutput(for yawError: Float) -> Float {
        max(-1, min(1, -config.steeringGain * yawError))
    }

    /// Throttle fades as heading error grows, but keeps a small floor through
    /// normal turns so high-friction starts do not stall the mission.
    private func throttleOutput(for yawError: Float) -> Float {
        let absError = abs(yawError)
        guard absError <= config.maxPoweredHeadingError else { return 0 }
        let fade = 1.0 - absError / .pi
        return maxThrottle * max(config.minimumThrottleFraction, fade)
    }
}

// MARK: - Geometry (ground plane only)

private func groundDistance(ax: Float, az: Float, bx: Float, bz: Float) -> Float {
    let dx = bx - ax
    let dz = bz - az
    return sqrtf(dx * dx + dz * dz)
}
