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

struct GroundVector: Equatable {
    let x: Float
    let z: Float
}

func forwardVector(yaw: Float) -> GroundVector {
    GroundVector(x: cosf(yaw), z: -sinf(yaw))
}

func rightVector(yaw: Float) -> GroundVector {
    GroundVector(x: sinf(yaw), z: cosf(yaw))
}

func worldPoint(localX: Float, localZ: Float, anchor: PoseEntry) -> GroundVector {
    let forward = forwardVector(yaw: anchor.yaw)
    let right = rightVector(yaw: anchor.yaw)
    return GroundVector(
        x: anchor.x + localX * forward.x + localZ * right.x,
        z: anchor.z + localX * forward.z + localZ * right.z
    )
}

/// Return a waypoint `distance` metres directly ahead of `pose`.
func forwardWaypoint(from pose: PoseEntry,
                     distance: Float,
                     acceptanceRadius: Float = 0.2) -> Waypoint {
    let point = worldPoint(localX: distance, localZ: 0, anchor: pose)
    return Waypoint(x: point.x, z: point.z, acceptanceRadius: acceptanceRadius)
}
