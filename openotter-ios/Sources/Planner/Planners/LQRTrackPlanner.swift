import Foundation

struct LQRTrackConfig {
    var targetSpeedMps: Double = 0.20
    var effectiveWheelbaseM: Double = 0.35
    var steeringScale: Double = 1.0
    var throttleAccelScale: Float = 0.15
    var curvatureFeedforwardGain: Float = 0.10
    var minimumThrottleFraction: Float = 0.35
    var closedLoopProgressSearchCount: Int = 32
    var curvatureSampleSpan: Int = 3
    var derivativeResetIndexJump: Int = 8
    var dtRange: ClosedRange<Double> = 0.02...0.25
    var qDiagonal: [Double] = [3.0, 0.2, 2.5, 0.2, 0.8]
    var rDiagonal: [Double] = [1.0, 2.0]
}

/// LQRTrack figure-eight planner using LQR speed and steering feedback.
///
/// This remains an experimental controller behind `/figure8_lqr`; `/figure8`
/// keeps using the simpler TangentTrack baseline.
final class LQRTrackPlanner: PlannerProtocol, PathDebugProviding {

    let name = "LQRTrack"
    let config: LQRTrackConfig

    init(config: LQRTrackConfig = .init()) {
        self.config = config
    }

    private var waypoints: [Waypoint] = []
    private var maxThrottle: Float = 0
    private var currentIndex: Int = 0
    private var pendingFigureEightConfig: FigureEightTrajectory.Config?
    private var previousError: Float?
    private var previousHeadingError: Float?
    private var previousTimestamp: TimeInterval?
    private var previousReferenceIndex: Int?

    var activeWaypoints: [Waypoint] { waypoints }
    var currentWaypointIndex: Int { currentIndex }

    func setGoal(_ goal: PlannerGoal) {
        reset()
        switch goal {
        case .followFigureEight(let config, let throttle, let controller):
            guard controller == .lqrTrack else { break }
            pendingFigureEightConfig = config
            maxThrottle = throttle
        case .idle, .followWaypoints, .constantThrottle:
            break
        }
    }

    func plan(context: PlannerContext) -> ControlCommand {
        materializePendingFigureEightIfNeeded(anchor: context.pose)
        guard waypoints.count > 1 else { return .neutral }

        let reference = PathReference.project(
            pose: context.pose,
            waypoints: waypoints,
            currentIndex: currentIndex,
            progressSearchCount: config.closedLoopProgressSearchCount,
            curvatureSampleSpan: config.curvatureSampleSpan
        )
        currentIndex = reference.index

        let measuredSpeed = measuredSpeedMps(from: context)
        let dt = controlDt(timestamp: context.timestamp)
        let lateralError = -reference.crossTrackError
        let headingError = (context.pose.yaw - reference.tangentYaw).wrapToPi()
        let resetDerivative = shouldResetDerivativeMemory(referenceIndex: reference.index)
        let previousLateralError = resetDerivative ? lateralError : (previousError ?? lateralError)
        let previousHeadingError = resetDerivative ? headingError : (self.previousHeadingError ?? headingError)
        let errorRate = Double((lateralError - previousLateralError) / Float(dt))
        let headingRate = Double((headingError - previousHeadingError).wrapToPi() / Float(dt))
        let speedError = measuredSpeed - config.targetSpeedMps
        let state = [
            Double(lateralError),
            errorRate,
            Double(headingError),
            headingRate,
            speedError
        ]

        let model = LQRTrackModel.discrete(
            dt: dt,
            speedMps: max(measuredSpeed, config.targetSpeedMps),
            effectiveWheelbaseM: config.effectiveWheelbaseM
        )
        let result = LQRMath.dlqr(
            a: model.a,
            b: model.b,
            q: Matrix.diagonal(config.qDiagonal),
            r: Matrix.diagonal(config.rDiagonal)
        )

        guard case .success(let gain) = result else {
            storePrevious(lateralError: lateralError, headingError: headingError, timestamp: context.timestamp)
            return ControlCommand(steering: 0, throttle: 0, source: .planner(name), reason: "LQR solve failed")
        }

        let feedback = gain * state
        let steeringFeedback = feedback[0]
        let accelerationFeedback = -feedback[1]
        let steeringFeedforward = clamp(
            -config.curvatureFeedforwardGain * reference.curvature,
            min: -1,
            max: 1
        )
        let steering = clamp(
            steeringFeedforward + Float(config.steeringScale * steeringFeedback),
            min: -1,
            max: 1
        )
        let throttle = clamp(
            baseThrottleForTargetSpeed() + config.throttleAccelScale * Float(accelerationFeedback),
            min: 0,
            max: max(0, min(1, maxThrottle))
        )

        storePrevious(lateralError: lateralError, headingError: headingError, timestamp: context.timestamp)
        return ControlCommand(steering: steering, throttle: throttle, source: .planner(name))
    }

    func reset() {
        waypoints = []
        maxThrottle = 0
        currentIndex = 0
        pendingFigureEightConfig = nil
        previousError = nil
        previousHeadingError = nil
        previousTimestamp = nil
        previousReferenceIndex = nil
    }

    private func materializePendingFigureEightIfNeeded(anchor: PoseEntry) {
        guard let pendingFigureEightConfig else { return }
        waypoints = FigureEightTrajectory.waypoints(config: pendingFigureEightConfig, anchor: anchor)
        currentIndex = 0
        self.pendingFigureEightConfig = nil
    }

    private func measuredSpeedMps(from context: PlannerContext) -> Double {
        [context.motorSpeedMps, context.arkitSpeedMps]
            .compactMap { $0 }
            .filter { $0.isFinite && $0 >= 0 }
            .max() ?? 0
    }

    private func controlDt(timestamp: TimeInterval) -> Double {
        guard let previousTimestamp else { return 0.1 }
        let raw = timestamp - previousTimestamp
        return min(max(raw, config.dtRange.lowerBound), config.dtRange.upperBound)
    }

    private func baseThrottleForTargetSpeed() -> Float {
        guard config.targetSpeedMps > 0.05 else { return 0 }
        let fraction = Float(min(1, max(0, config.targetSpeedMps / 0.20)))
        return max(maxThrottle * config.minimumThrottleFraction, maxThrottle * fraction)
    }

    private func shouldResetDerivativeMemory(referenceIndex: Int) -> Bool {
        guard let previousReferenceIndex, !waypoints.isEmpty else { return true }
        let forwardDelta = (referenceIndex - previousReferenceIndex + waypoints.count) % waypoints.count
        return forwardDelta > config.derivativeResetIndexJump
    }

    private func storePrevious(lateralError: Float,
                               headingError: Float,
                               timestamp: TimeInterval) {
        previousError = lateralError
        previousHeadingError = headingError
        previousTimestamp = timestamp
        previousReferenceIndex = currentIndex
    }
}

private func clamp(_ value: Float, min: Float, max: Float) -> Float {
    Swift.max(min, Swift.min(max, value))
}
