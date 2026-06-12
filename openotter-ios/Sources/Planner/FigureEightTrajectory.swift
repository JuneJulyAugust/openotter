import Foundation

enum FigureEightTrajectory {

    struct Config {
        let segmentCount: Int
        let length: Float
        let width: Float
        let acceptanceRadius: Float

        init(segmentCount: Int = 240,
             length: Float = 4.0,
             width: Float = 2.0,
             acceptanceRadius: Float = 0.12) {
            self.segmentCount = max(12, segmentCount)
            self.length = max(0.05, length)
            self.width = max(0.05, width)
            self.acceptanceRadius = max(0.05, acceptanceRadius)
        }
    }

    static func waypoints(config: Config = .init()) -> [Waypoint] {
        waypoints(config: config, anchor: PoseEntry(timestamp: 0, x: 0, y: 0, z: 0, yaw: 0, confidence: 1))
    }

    static func waypoints(config: Config = .init(), anchor: PoseEntry) -> [Waypoint] {
        let localPoints = localWaypoints(config: config)

        return localPoints.map { point in
            let world = worldPoint(localX: point.x, localZ: point.z, anchor: anchor)
            return Waypoint(
                x: world.x,
                z: world.z,
                acceptanceRadius: config.acceptanceRadius
            )
        }
    }

    private static func localWaypoints(config: Config) -> [(x: Float, z: Float)] {
        let denseCount = max(config.segmentCount * 8, 720)
        let dense = scaledDensePoints(count: denseCount, config: config)
        let cumulative = cumulativeLengths(dense)
        guard let totalLength = cumulative.last, totalLength > 0 else {
            return Array(repeating: (x: 0, z: 0), count: config.segmentCount)
        }

        var segmentIndex = 1
        return (0..<config.segmentCount).map { waypointIndex in
            let targetDistance = totalLength * Float(waypointIndex) / Float(config.segmentCount)
            while segmentIndex < cumulative.count - 1,
                  cumulative[segmentIndex] < targetDistance {
                segmentIndex += 1
            }

            let previousIndex = max(0, segmentIndex - 1)
            let segmentLength = cumulative[segmentIndex] - cumulative[previousIndex]
            let fraction: Float
            if segmentLength > 0 {
                fraction = (targetDistance - cumulative[previousIndex]) / segmentLength
            } else {
                fraction = 0
            }

            let previous = dense[previousIndex]
            let next = dense[segmentIndex]
            return (
                x: previous.x + (next.x - previous.x) * fraction,
                z: previous.z + (next.z - previous.z) * fraction
            )
        }
    }

    private static func scaledDensePoints(count: Int, config: Config) -> [(x: Float, z: Float)] {
        let raw = (0...count).map { index in
            rawBernoulliPoint(t: 2 * .pi * Float(index) / Float(count))
        }
        let maxAbsX = raw.map { abs($0.x) }.max() ?? 1
        let maxAbsZ = raw.map { abs($0.z) }.max() ?? 1
        let xScale = config.length / 2
        let zScale = config.width / 2

        return raw.map { point in
            (
                x: point.x / maxAbsX * xScale,
                z: point.z / maxAbsZ * zScale
            )
        }
    }

    private static func rawBernoulliPoint(t: Float) -> (x: Float, z: Float) {
        let theta = t + .pi / 2
        let sinTheta = sinf(theta)
        let cosTheta = cosf(theta)
        let denominator = 1 + sinTheta * sinTheta

        return (
            x: -cosTheta / denominator,
            z: -(sinTheta * cosTheta) / denominator
        )
    }

    private static func cumulativeLengths(_ points: [(x: Float, z: Float)]) -> [Float] {
        guard !points.isEmpty else { return [] }

        var cumulative = Array(repeating: Float(0), count: points.count)
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let dx = current.x - previous.x
            let dz = current.z - previous.z
            cumulative[index] = cumulative[index - 1] + sqrtf(dx * dx + dz * dz)
        }
        return cumulative
    }
}
