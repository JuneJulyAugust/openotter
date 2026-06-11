import Foundation

enum FigureEightTrajectory {

    struct Config {
        let segmentCount: Int
        let length: Float
        let width: Float
        let acceptanceRadius: Float

        init(segmentCount: Int = 72,
             length: Float = 0.8,
             width: Float = 0.5,
             acceptanceRadius: Float = 0.18) {
            self.segmentCount = max(12, segmentCount)
            self.length = max(0.05, length)
            self.width = max(0.05, width)
            self.acceptanceRadius = max(0.05, acceptanceRadius)
        }
    }

    static func waypoints(config: Config = .init()) -> [Waypoint] {
        let xScale = config.length / 2
        let zScale = config.width / 2
        let dt = Float.pi * 2 / Float(config.segmentCount)
        let phase = Float.pi / 2

        return (0..<config.segmentCount).map { i in
            let t = Float(i) * dt + phase
            return Waypoint(
                x: xScale * sinf(t),
                z: zScale * sinf(2 * t),
                acceptanceRadius: config.acceptanceRadius
            )
        }
    }
}
