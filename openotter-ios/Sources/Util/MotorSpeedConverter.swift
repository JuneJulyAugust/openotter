import Foundation

/// A simple window-based moving average filter to reduce noise while maintaining low latency.
public struct MovingAverageFilter {
    private var window: [Double] = []
    private let size: Int

    public init(size: Int) {
        self.size = size
    }

    public mutating func update(_ value: Double) -> Double {
        if value == 0 {
            window.removeAll()
            return 0
        }
        window.append(value)
        if window.count > size {
            window.removeFirst()
        }
        return window.reduce(0, +) / Double(window.count)
    }
}

/// Linear conversion from motor RPM to vehicle speed in m/s based on wheel calibration data.
public struct MotorSpeedConverter {
    // From motor_wheel_calibration.csv:
    // motor_rpm vs wheel_rpm: (765, 23.3), (1000, 30.5), (1118, 34.0), (2100, 64.0), (2930, 89.0), (4570, 140.0)
    // Average gear ratio (wheel_rpm / motor_rpm) ≈ 0.030475
    // Wheel diameter = 88mm = 0.088m

    private static let gearRatio: Double = 0.029
    private static let wheelDiameterM: Double = 0.088
    private static let pi: Double = 3.14159265358979

    /// Converts motor RPM to vehicle speed in metres per second.
    public static func rpmToMps(_ rpm: Double) -> Double {
        let wheelRpm = rpm * gearRatio
        let wheelRps = wheelRpm / 60.0
        let circumference = pi * wheelDiameterM
        return wheelRps * circumference
    }

    /// Pre-calculated linear coefficient: speed_mps = rpm * rpmToMpsFactor
    public static let rpmToMpsFactor: Double = (gearRatio / 60.0) * pi * wheelDiameterM
}
