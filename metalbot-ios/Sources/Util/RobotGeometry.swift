import Foundation

/// Pure geometric utilities for robot navigation in ARKit world frame.
///
/// Coordinate conventions (established in ARKitPoseViewModel):
///   robotX = -cameraWorldZ   (forward)
///   robotZ =  cameraWorldX   (right)
///   yaw    =  atan2(col2.x, col2.z)  — gimbal-safe rotation about gravity/Y-axis
///
/// Forward unit vector in robot (x, z) at heading θ:
///   forwardX = cos(θ),  forwardZ = -sin(θ)
///
/// Derivation: yaw = atan2(col2.x, col2.z). For pure Y-rotation by θ,
/// col2 = (sinθ, 0, cosθ). Camera forward = -col2_world = (-sinθ, 0, -cosθ).
/// After remapping: robotX = -(-cosθ) = cosθ, robotZ = -sinθ. ∎

/// Return a waypoint `distance` metres directly ahead of `pose`.
func forwardWaypoint(from pose: PoseEntry,
                     distance: Float,
                     acceptanceRadius: Float = 0.2) -> Waypoint {
    Waypoint(
        x: pose.x + distance * cosf(pose.yaw),
        z: pose.z - distance * sinf(pose.yaw),
        acceptanceRadius: acceptanceRadius
    )
}
