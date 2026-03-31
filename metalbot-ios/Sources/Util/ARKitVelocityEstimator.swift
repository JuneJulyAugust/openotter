// Sources/Util/ARKitVelocityEstimator.swift
import Foundation

/// Velocity filter strategy for ARKit-derived speed.
enum VelocityFilterMode {
    case movingAverage
    case exponentialMovingAverage
}

/// Estimates ground-plane speed by differentiating consecutive ARKit poses.
///
/// Speed = sqrt(dx^2 + dz^2) / dt, where dx/dz are position deltas in robot frame
/// and dt is the timestamp delta between consecutive frames.
struct ARKitVelocityEstimator {

    var filterMode: VelocityFilterMode

    /// Moving average window size.
    private let maWindowSize: Int
    /// EMA smoothing factor (0..1). Higher = more responsive, noisier.
    private let emaSmoothingFactor: Double

    private var maWindow: [Double] = []
    private var emaValue: Double?
    private var lastX: Float?
    private var lastZ: Float?
    private var lastTimestamp: TimeInterval?

    init(filterMode: VelocityFilterMode = .movingAverage,
         maWindowSize: Int = 5,
         emaSmoothingFactor: Double = 0.3) {
        self.filterMode = filterMode
        self.maWindowSize = maWindowSize
        self.emaSmoothingFactor = emaSmoothingFactor
    }

    /// Feed a new pose and get filtered speed in m/s. Returns nil until two poses received.
    mutating func update(x: Float, z: Float, timestamp: TimeInterval) -> Double? {
        defer {
            lastX = x
            lastZ = z
            lastTimestamp = timestamp
        }

        guard let prevX = lastX, let prevZ = lastZ, let prevT = lastTimestamp else {
            return nil
        }

        let dt = timestamp - prevT
        guard dt > 1e-6 else { return nil }

        let dx = Double(x - prevX)
        let dz = Double(z - prevZ)
        let rawSpeed = sqrt(dx * dx + dz * dz) / dt

        switch filterMode {
        case .movingAverage:
            return applyMA(rawSpeed)
        case .exponentialMovingAverage:
            return applyEMA(rawSpeed)
        }
    }

    mutating func reset() {
        lastX = nil
        lastZ = nil
        lastTimestamp = nil
        maWindow.removeAll()
        emaValue = nil
    }

    // MARK: - Filters

    private mutating func applyMA(_ value: Double) -> Double {
        maWindow.append(value)
        if maWindow.count > maWindowSize { maWindow.removeFirst() }
        return maWindow.reduce(0, +) / Double(maWindow.count)
    }

    private mutating func applyEMA(_ value: Double) -> Double {
        guard let prev = emaValue else {
            emaValue = value
            return value
        }
        let filtered = emaSmoothingFactor * value + (1.0 - emaSmoothingFactor) * prev
        emaValue = filtered
        return filtered
    }
}
