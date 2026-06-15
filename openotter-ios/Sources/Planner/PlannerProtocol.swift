import Foundation

/// A point on the ground plane (XZ) in ARKit world frame.
struct Waypoint {
    let x: Float                // forward axis (ARKit world)
    let z: Float                // right axis (ARKit world)
    let acceptanceRadius: Float // meters

    init(x: Float, z: Float, acceptanceRadius: Float = 0.2) {
        self.x = x
        self.z = z
        self.acceptanceRadius = acceptanceRadius
    }
}

enum FigureEightControllerKind: String, Equatable {
    case tangentTrack
    case lqrTrack

    var displayName: String {
        switch self {
        case .tangentTrack: return "TangentTrack"
        case .lqrTrack: return "LQRTrack"
        }
    }
}

/// What the planner is pursuing.
enum PlannerGoal {
    case idle
    case followWaypoints([Waypoint], maxThrottle: Float)
    case followFigureEight(config: FigureEightTrajectory.Config,
                           maxThrottle: Float,
                           controller: FigureEightControllerKind = .tangentTrack)
    case constantThrottle(targetThrottle: Float)
}

/// Extensibility contract for all planners.
/// Adding a new planner = one new file implementing this protocol.
protocol PlannerProtocol: AnyObject {
    var name: String { get }
    func setGoal(_ goal: PlannerGoal)
    func plan(context: PlannerContext) -> ControlCommand
    func reset()
}
