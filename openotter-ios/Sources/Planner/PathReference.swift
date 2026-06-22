import Foundation

struct PathReferenceResult {
    let index: Int
    let projectedPoint: GroundVector
    let tangentYaw: Float
    let crossTrackError: Float
    let curvature: Float
}

enum PathReference {

    static func project(pose: PoseEntry,
                        waypoints: [Waypoint],
                        currentIndex: Int,
                        progressSearchCount: Int,
                        curvatureSampleSpan: Int) -> PathReferenceResult {
        guard waypoints.count > 1 else {
            return PathReferenceResult(
                index: 0,
                projectedPoint: GroundVector(x: pose.x, z: pose.z),
                tangentYaw: pose.yaw,
                crossTrackError: 0,
                curvature: 0
            )
        }

        let clampedIndex = ((currentIndex % waypoints.count) + waypoints.count) % waypoints.count
        let referenceIndex = closestForwardIndex(
            pose: pose,
            waypoints: waypoints,
            currentIndex: clampedIndex,
            progressSearchCount: progressSearchCount
        )
        let segment = projectedSegment(at: referenceIndex, pose: pose, waypoints: waypoints)
        let right = rightVector(yaw: segment.tangentYaw)
        let dx = pose.x - segment.projectedPoint.x
        let dz = pose.z - segment.projectedPoint.z
        let crossTrackError = dx * right.x + dz * right.z
        return PathReferenceResult(
            index: referenceIndex,
            projectedPoint: segment.projectedPoint,
            tangentYaw: segment.tangentYaw,
            crossTrackError: crossTrackError,
            curvature: signedCurvature(at: referenceIndex, waypoints: waypoints, sampleSpan: curvatureSampleSpan)
        )
    }

    private struct SegmentProjection {
        let projectedPoint: GroundVector
        let tangentYaw: Float
        let distanceSquared: Float
    }

    private static func closestForwardIndex(pose: PoseEntry,
                                            waypoints: [Waypoint],
                                            currentIndex: Int,
                                            progressSearchCount: Int) -> Int {
        let maxOffset = min(max(0, progressSearchCount), waypoints.count - 1)
        var bestIndex = currentIndex
        var bestDistance = projectedSegment(at: currentIndex, pose: pose, waypoints: waypoints).distanceSquared

        guard maxOffset > 0 else { return bestIndex }
        for offset in 1...maxOffset {
            let index = (currentIndex + offset) % waypoints.count
            let distance = projectedSegment(at: index, pose: pose, waypoints: waypoints).distanceSquared
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func projectedSegment(at index: Int,
                                         pose: PoseEntry,
                                         waypoints: [Waypoint]) -> SegmentProjection {
        let start = waypoints[index]
        let end = waypoints[(index + 1) % waypoints.count]
        let dx = end.x - start.x
        let dz = end.z - start.z
        let lengthSquared = dx * dx + dz * dz
        let projection: Float
        if lengthSquared > 0 {
            projection = clamp(
                ((pose.x - start.x) * dx + (pose.z - start.z) * dz) / lengthSquared,
                min: 0,
                max: 1
            )
        } else {
            projection = 0
        }

        let point = GroundVector(
            x: start.x + dx * projection,
            z: start.z + dz * projection
        )
        let distanceX = pose.x - point.x
        let distanceZ = pose.z - point.z
        return SegmentProjection(
            projectedPoint: point,
            tangentYaw: atan2f(-dz, dx),
            distanceSquared: distanceX * distanceX + distanceZ * distanceZ
        )
    }

    private static func signedCurvature(at index: Int,
                                        waypoints: [Waypoint],
                                        sampleSpan: Int) -> Float {
        guard waypoints.count > 2 else { return 0 }

        let span = max(1, min(sampleSpan, max(1, (waypoints.count - 1) / 2)))
        let previous = waypoints[(index - span + waypoints.count) % waypoints.count]
        let current = waypoints[index]
        let next = waypoints[(index + span) % waypoints.count]
        let inboundYaw = heading(from: previous, to: current)
        let outboundYaw = heading(from: current, to: next)
        let headingDelta = (outboundYaw - inboundYaw).wrapToPi()
        let arcLength = max(0.001, arcLength(centeredAt: index, span: span, waypoints: waypoints))
        return headingDelta / arcLength
    }

    private static func heading(from start: Waypoint, to end: Waypoint) -> Float {
        atan2f(-(end.z - start.z), end.x - start.x)
    }

    private static func arcLength(centeredAt index: Int, span: Int, waypoints: [Waypoint]) -> Float {
        var length: Float = 0
        for offset in -span..<span {
            let firstIndex = (index + offset + waypoints.count) % waypoints.count
            let secondIndex = (firstIndex + 1) % waypoints.count
            length += groundDistance(
                ax: waypoints[firstIndex].x,
                az: waypoints[firstIndex].z,
                bx: waypoints[secondIndex].x,
                bz: waypoints[secondIndex].z
            )
        }
        return length
    }
}

private func groundDistance(ax: Float, az: Float, bx: Float, bz: Float) -> Float {
    let dx = bx - ax
    let dz = bz - az
    return sqrtf(dx * dx + dz * dz)
}

private func clamp(_ value: Float, min: Float, max: Float) -> Float {
    Swift.max(min, Swift.min(max, value))
}
