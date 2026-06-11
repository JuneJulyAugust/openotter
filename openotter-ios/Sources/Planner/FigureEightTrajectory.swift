import Foundation

enum FigureEightTrajectory {

    struct Config {
        let segmentCount: Int
        let length: Float
        let width: Float
        let acceptanceRadius: Float

        init(segmentCount: Int = 120,
             length: Float = 1.5,
             width: Float = 1.0,
             acceptanceRadius: Float = 0.22) {
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
        let xScale = config.length / 2
        let zScale = config.width / 2
        let dt = Float.pi * 2 / Float(config.segmentCount)
        let initialTangentAngle = atan2f(2 * zScale, xScale)
        let cosA = cosf(-initialTangentAngle)
        let sinA = sinf(-initialTangentAngle)

        return (0..<config.segmentCount).map { i in
            let t = Float(i) * dt
            let curveX = xScale * sinf(t)
            let curveZ = zScale * sinf(2 * t)
            let localX = curveX * cosA - curveZ * sinA
            let localZ = curveX * sinA + curveZ * cosA
            let world = worldPoint(localX: localX, localZ: localZ, anchor: anchor)
            return Waypoint(
                x: world.x,
                z: world.z,
                acceptanceRadius: config.acceptanceRadius
            )
        }
    }
}
