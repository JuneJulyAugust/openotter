import Foundation

// MARK: - Config

struct WaypointPlannerConfig {
    /// Steering fraction applied at a 90° heading error (0–1).
    /// Full deflection would be 1.0; 0.7 gives visible steering authority
    /// while the output cap below still protects the mechanical end stop.
    var steeringFractionAt90Deg: Float = 0.7

    /// Hard cap for steering output. Keep below the mechanical stop range so
    /// the servo does not sit against its end stop and chatter.
    var maxSteeringFraction: Float = 0.45

    /// Keep enough throttle through normal turns that the car does not stall
    /// while the heading loop is still converging.
    var minimumThrottleFraction: Float = 0.35

    /// If the target is almost behind the car, hold throttle at zero instead
    /// of pushing forward into a U-turn.
    var maxPoweredHeadingError: Float = 5 * .pi / 6

    /// Closed-loop paths use a forward progress search so a missed waypoint
    /// does not trap the car into orbiting around one lobe.
    var closedLoopProgressSearchCount: Int = 32

    /// Curvature feedforward is measured across several waypoints so tiny
    /// spacing noise does not become steering chatter.
    var curvatureSampleSpan: Int = 3

    /// Cross-track correction gain for closed-loop paths. Positive lateral
    /// error means the car is right of the path and should bias heading left.
    var crossTrackHeadingGain: Float = 2.2

    /// Softening distance for cross-track heading correction. Larger values
    /// reduce correction aggressiveness near the path centerline.
    var crossTrackSofteningDistance: Float = 0.18

    /// Steering feedforward from path curvature. Positive path curvature turns
    /// left, so steering uses the negative of this value.
    var curvatureFeedforwardGain: Float = 0.1

    /// Integral term is disabled by default until field logs show a steady
    /// steering bias. Keeping the state in place makes the controller PID-ready.
    var headingIntegralGain: Float = 0

    /// Small derivative term damps fast heading-error growth without relying on
    /// a front wheel angle sensor.
    var headingDerivativeGain: Float = 0.02

    /// Clamp the integral accumulator so future nonzero I gain cannot wind up.
    var headingIntegralLimit: Float = 0.5

    /// When the car is far from the centerline and steering is loaded, reduce
    /// speed enough for the yaw loop to catch up.
    var steeringThrottleScaleAtLimit: Float = 0.45

    /// Lateral error where steering-load throttle shaping reaches full effect.
    var lateralThrottleSlowdownDistance: Float = 0.2

    /// If speed feedback says the car is stuck or almost stuck, keep at least
    /// this fraction of requested throttle so steering load cannot stall it.
    var antiStallThrottleFraction: Float = 0.75

    /// Speed below which the planner blends in anti-stall throttle.
    var antiStallSpeedThresholdMps: Double = 0.12

    /// Derived gain: maps heading error (rad) → steering fraction.
    var steeringGain: Float { steeringFractionAt90Deg / (.pi / 2) }
}

protocol WaypointDebugProviding: AnyObject {
    var activeWaypoints: [Waypoint] { get }
    var currentWaypointIndex: Int { get }
}

// MARK: - WaypointPlanner

/// Waypoint follower with path-tangent tracking for closed-loop courses.
///
/// Finite waypoint missions still steer toward the current waypoint. Closed
/// loops derive reference heading and curvature from the active path segment.
final class WaypointPlanner: PlannerProtocol, WaypointDebugProviding {

    let name = "WaypointPlanner"
    let config: WaypointPlannerConfig

    init(config: WaypointPlannerConfig = .init()) {
        self.config = config
    }

    // MARK: - State

    private var waypoints: [Waypoint] = []
    private var maxThrottle: Float = 0
    private var currentIndex: Int = 0
    private var isClosedLoop: Bool = false
    private var pendingFigureEightConfig: FigureEightTrajectory.Config?
    private var headingErrorIntegral: Float = 0
    private var previousHeadingError: Float?
    private var previousControlTimestamp: TimeInterval?

    var activeWaypoints: [Waypoint] { waypoints }
    var currentWaypointIndex: Int { currentIndex }

    // MARK: - PlannerProtocol

    func setGoal(_ goal: PlannerGoal) {
        reset()
        switch goal {
        case .idle: break
        case .followWaypoints(let wps, let throttle):
            waypoints = wps
            maxThrottle = throttle
            isClosedLoop = false
        case .followFigureEight(let config, let throttle):
            pendingFigureEightConfig = config
            maxThrottle = throttle
            isClosedLoop = true
        case .constantThrottle:
            break // Not handled by WaypointPlanner
        }
    }

    func plan(context: PlannerContext) -> ControlCommand {
        materializePendingFigureEightIfNeeded(anchor: context.pose)
        guard !waypoints.isEmpty, currentIndex < waypoints.count else { return .neutral }

        advanceReachedWaypoints(from: context.pose)
        guard currentIndex < waypoints.count else { return .neutral }

        let guidance = guidanceCommand(from: context.pose)
        let steering: Float
        if guidance.usesPathController {
            steering = pathSteeringOutput(
                for: guidance.steeringYawError,
                feedforward: guidance.steeringFeedforward,
                timestamp: context.timestamp
            )
        } else {
            steering = proportionalSteeringOutput(for: guidance.steeringYawError)
        }
        return ControlCommand(
            steering: steering,
            throttle: throttleOutput(
                for: guidance.throttleYawError,
                steering: steering,
                lateralError: guidance.lateralError,
                measuredSpeedMps: measuredSpeedMps(from: context)
            ),
            source: .planner(name)
        )
    }

    func reset() {
        waypoints = []
        maxThrottle = 0
        currentIndex = 0
        isClosedLoop = false
        pendingFigureEightConfig = nil
        resetControllerState()
    }

    // MARK: - Private

    private struct GuidanceCommand {
        let steeringYawError: Float
        let throttleYawError: Float
        let steeringFeedforward: Float
        let lateralError: Float?
        let usesPathController: Bool
    }

    private func materializePendingFigureEightIfNeeded(anchor: PoseEntry) {
        guard let pendingFigureEightConfig else { return }
        waypoints = FigureEightTrajectory.waypoints(config: pendingFigureEightConfig, anchor: anchor)
        currentIndex = 0
        self.pendingFigureEightConfig = nil
    }

    private func advanceReachedWaypoints(from pose: PoseEntry) {
        var checkedCount = 0
        while !waypoints.isEmpty,
              currentIndex < waypoints.count,
              checkedCount < waypoints.count,
              hasReached(target: waypoints[currentIndex], pose: pose) {
            currentIndex += 1
            if isClosedLoop, currentIndex >= waypoints.count {
                currentIndex = 0
            }
            checkedCount += 1
        }

        if !isClosedLoop,
           checkedCount >= waypoints.count,
           currentIndex < waypoints.count,
           hasReached(target: waypoints[currentIndex], pose: pose) {
            currentIndex = waypoints.count
        }

        advanceToClosestForwardWaypoint(from: pose)
    }

    private func advanceToClosestForwardWaypoint(from pose: PoseEntry) {
        guard isClosedLoop, !waypoints.isEmpty else { return }

        let maxOffset = min(config.closedLoopProgressSearchCount, waypoints.count - 1)
        guard maxOffset > 0 else { return }

        var bestIndex = currentIndex
        var bestDistance = distance(to: waypoints[currentIndex], from: pose)

        for offset in 1...maxOffset {
            let index = (currentIndex + offset) % waypoints.count
            let candidateDistance = distance(to: waypoints[index], from: pose)
            if candidateDistance < bestDistance {
                bestDistance = candidateDistance
                bestIndex = index
            }
        }

        currentIndex = bestIndex
    }

    private func guidanceCommand(from pose: PoseEntry) -> GuidanceCommand {
        guard isClosedLoop else {
            let target = waypoints[currentIndex]
            let yawError = headingError(to: target, from: pose)
            return GuidanceCommand(
                steeringYawError: yawError,
                throttleYawError: yawError,
                steeringFeedforward: 0,
                lateralError: nil,
                usesPathController: false
            )
        }

        let reference = closedLoopPathReference(from: pose)
        return GuidanceCommand(
            steeringYawError: reference.steeringYawError,
            throttleYawError: reference.throttleYawError,
            steeringFeedforward: reference.steeringFeedforward,
            lateralError: abs(reference.crossTrackError),
            usesPathController: true
        )
    }

    private struct ClosedLoopPathSegment {
        let projectedPoint: GroundVector
        let tangentYaw: Float
    }

    private struct ClosedLoopPathReference {
        let steeringYawError: Float
        let throttleYawError: Float
        let crossTrackError: Float
        let steeringFeedforward: Float
    }

    private func closedLoopPathReference(from pose: PoseEntry) -> ClosedLoopPathReference {
        let referenceIndex = currentIndex
        let segment = projectedSegmentReference(at: referenceIndex, from: pose)
        let crossTrackError = signedCrossTrackError(
            from: pose,
            reference: segment.projectedPoint,
            tangentYaw: segment.tangentYaw
        )
        let crossTrackCorrection = atan2f(
            config.crossTrackHeadingGain * crossTrackError,
            max(0.001, config.crossTrackSofteningDistance)
        )
        let desiredYaw = (segment.tangentYaw + crossTrackCorrection).wrapToPi()
        let curvature = signedCurvature(at: referenceIndex)

        return ClosedLoopPathReference(
            steeringYawError: (desiredYaw - pose.yaw).wrapToPi(),
            throttleYawError: (segment.tangentYaw - pose.yaw).wrapToPi(),
            crossTrackError: crossTrackError,
            steeringFeedforward: curvatureFeedforward(for: curvature)
        )
    }

    private func hasReached(target: Waypoint, pose: PoseEntry) -> Bool {
        distance(to: target, from: pose) < target.acceptanceRadius
    }

    private func distance(to target: Waypoint, from pose: PoseEntry) -> Float {
        groundDistance(ax: pose.x, az: pose.z, bx: target.x, bz: target.z)
    }

    private func headingError(to target: Waypoint, from pose: PoseEntry) -> Float {
        let dx = target.x - pose.x
        let dz = target.z - pose.z
        let desired = atan2f(-dz, dx)
        return (desired - pose.yaw).wrapToPi()
    }

    private func proportionalSteeringOutput(for yawError: Float) -> Float {
        let limit = max(0, min(1, config.maxSteeringFraction))
        return clamp(-config.steeringGain * yawError, min: -limit, max: limit)
    }

    private func pathSteeringOutput(for yawError: Float,
                                    feedforward: Float,
                                    timestamp: TimeInterval) -> Float {
        let limit = max(0, min(1, config.maxSteeringFraction))
        let derivative = updateControllerState(yawError: yawError, timestamp: timestamp)
        let pidCorrection = config.steeringGain * yawError
            + config.headingIntegralGain * headingErrorIntegral
            + config.headingDerivativeGain * derivative
        return clamp(feedforward - pidCorrection, min: -limit, max: limit)
    }

    /// Throttle fades as path-heading error grows, slows loaded steering once
    /// moving, and blends in breakaway throttle when speed feedback is near zero.
    private func throttleOutput(for throttleYawError: Float,
                                steering: Float,
                                lateralError: Float?,
                                measuredSpeedMps: Double?) -> Float {
        let absError = abs(throttleYawError)
        guard absError <= config.maxPoweredHeadingError else { return 0 }
        let fade = 1.0 - absError / .pi
        let baseThrottle = maxThrottle * max(config.minimumThrottleFraction, fade)
        guard let lateralError else {
            return antiStallAdjustedThrottle(
                baseThrottle,
                throttleYawError: throttleYawError,
                measuredSpeedMps: measuredSpeedMps
            )
        }

        let steeringLimit = max(0.001, min(1, config.maxSteeringFraction))
        let steeringLoad = min(1, abs(steering) / steeringLimit)
        let lateralLoad = min(1, lateralError / max(0.001, config.lateralThrottleSlowdownDistance))
        let scaleAtLimit = max(0, min(1, config.steeringThrottleScaleAtLimit))
        let scale = 1 - (1 - scaleAtLimit) * steeringLoad * lateralLoad
        return antiStallAdjustedThrottle(
            baseThrottle * scale,
            throttleYawError: throttleYawError,
            measuredSpeedMps: measuredSpeedMps
        )
    }

    private func antiStallAdjustedThrottle(_ throttle: Float,
                                           throttleYawError: Float,
                                           measuredSpeedMps: Double?) -> Float {
        guard throttle > 0, abs(throttleYawError) < .pi / 2 else { return throttle }

        let threshold = max(0.001, config.antiStallSpeedThresholdMps)
        let speed = max(0, measuredSpeedMps ?? 0)
        guard speed < threshold else { return throttle }

        let breakawayThrottle = maxThrottle * max(0, min(1, config.antiStallThrottleFraction))
        guard breakawayThrottle > throttle else { return throttle }

        let blend = Float(1.0 - speed / threshold)
        return throttle + (breakawayThrottle - throttle) * blend
    }

    private func measuredSpeedMps(from context: PlannerContext) -> Double? {
        [context.motorSpeedMps, context.arkitSpeedMps]
            .compactMap { $0 }
            .filter { $0.isFinite && $0 >= 0 }
            .max()
    }

    private func updateControllerState(yawError: Float, timestamp: TimeInterval) -> Float {
        defer {
            previousHeadingError = yawError
            previousControlTimestamp = timestamp
        }

        guard let previousControlTimestamp else { return 0 }

        let dt = Float(timestamp - previousControlTimestamp)
        guard dt > 0 else { return 0 }

        let clampedDt = min(0.25, dt)
        headingErrorIntegral = clamp(
            headingErrorIntegral + yawError * clampedDt,
            min: -abs(config.headingIntegralLimit),
            max: abs(config.headingIntegralLimit)
        )

        guard let previousHeadingError else { return 0 }
        return (yawError - previousHeadingError).wrapToPi() / clampedDt
    }

    private func resetControllerState() {
        headingErrorIntegral = 0
        previousHeadingError = nil
        previousControlTimestamp = nil
    }

    private func heading(from start: Waypoint, to end: Waypoint) -> Float {
        atan2f(-(end.z - start.z), end.x - start.x)
    }

    private func projectedSegmentReference(at index: Int, from pose: PoseEntry) -> ClosedLoopPathSegment {
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

        return ClosedLoopPathSegment(
            projectedPoint: GroundVector(
                x: start.x + dx * projection,
                z: start.z + dz * projection
            ),
            tangentYaw: atan2f(-dz, dx)
        )
    }

    private func signedCrossTrackError(from pose: PoseEntry, reference: GroundVector, tangentYaw: Float) -> Float {
        let right = rightVector(yaw: tangentYaw)
        let dx = pose.x - reference.x
        let dz = pose.z - reference.z
        return dx * right.x + dz * right.z
    }

    private func signedCurvature(at index: Int) -> Float {
        guard waypoints.count > 2 else { return 0 }

        let span = max(1, min(config.curvatureSampleSpan, max(1, (waypoints.count - 1) / 2)))
        let previous = waypoints[(index - span + waypoints.count) % waypoints.count]
        let current = waypoints[index]
        let next = waypoints[(index + span) % waypoints.count]
        let inboundYaw = heading(from: previous, to: current)
        let outboundYaw = heading(from: current, to: next)
        let headingDelta = (outboundYaw - inboundYaw).wrapToPi()
        let arcLength = max(0.001, arcLength(centeredAt: index, span: span))
        return headingDelta / arcLength
    }

    private func arcLength(centeredAt index: Int, span: Int) -> Float {
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

    private func curvatureFeedforward(for curvature: Float) -> Float {
        let limit = max(0, min(1, config.maxSteeringFraction))
        return clamp(-config.curvatureFeedforwardGain * curvature, min: -limit, max: limit)
    }
}

// MARK: - Geometry (ground plane only)

private func groundDistance(ax: Float, az: Float, bx: Float, bz: Float) -> Float {
    let dx = bx - ax
    let dz = bz - az
    return sqrtf(dx * dx + dz * dz)
}

private func clamp(_ value: Float, min: Float, max: Float) -> Float {
    Swift.max(min, Swift.min(max, value))
}
