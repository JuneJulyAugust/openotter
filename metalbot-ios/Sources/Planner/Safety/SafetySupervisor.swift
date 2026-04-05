import Foundation
import AudioToolbox

// MARK: - Config

struct SafetySupervisorConfig {
    /// Conservative speed estimate when no sensor data available.
    var fallbackSpeedMPS: Float = 0.3

    // MARK: Zone Thresholds

    /// TTC threshold for BRAKE zone (seconds). Obstacle within this TTC → full stop.
    var ttcBrakeS: Float = 0.3

    /// TTC threshold for CAUTION zone (seconds). Obstacle within this TTC → throttle ramp.
    var ttcCautionS: Float = 0.8

    /// Absolute minimum BRAKE distance (meters). Overrides TTC at low speeds.
    var minBrakeDistanceM: Float = 0.30

    /// Absolute minimum CAUTION distance (meters). Overrides TTC at low speeds.
    var minCautionDistanceM: Float = 0.50

    /// Maximum deceleration (m/s²). Used to compute kinematic braking distance.
    var maxDecelerationMPS2: Float = 2.5

    // MARK: Temporal Guards

    /// Minimum time (seconds) the supervisor stays in BRAKE before allowing CLEAR transition.
    var minBrakeDurationS: TimeInterval = 0.5

    /// Minimum time (seconds) the supervisor stays in CAUTION before allowing CLEAR transition.
    var minCautionDurationS: TimeInterval = 0.3

    // MARK: Depth Filtering

    /// EMA smoothing factor for depth readings when obstacle is approaching (lower = smoother).
    /// Approaching uses a higher alpha to react faster.
    var depthEmaAlphaApproaching: Float = 0.5

    /// EMA smoothing factor when obstacle is receding (lower = smoother).
    /// Slower release prevents premature brake release from noise.
    var depthEmaAlphaReceding: Float = 0.3

    // MARK: Misc

    /// Avoid division by zero at standstill.
    var minSpeedEpsilonMPS: Float = 0.01
}

// MARK: - Internal State

/// The three-zone safety state machine.
///
/// Invariant: Once in CAUTION or BRAKE, the supervisor does not return to CLEAR
/// until the obstacle depth exceeds the `clearDistance` computed from the **latched speed**
/// AND the minimum hold duration has elapsed.
enum SafetySupervisorState: Equatable {
    case clear
    case caution(since: TimeInterval)
    case brake(since: TimeInterval)
}

// MARK: - SafetySupervisor

/// Monitors forward depth and overrides planner commands when collision is imminent.
///
/// ## Safety Policy — Tri-Zone State Machine
///
/// Instead of a binary brake/pass decision, the supervisor operates in three zones:
///
/// | Zone      | Condition                              | Action                       |
/// |-----------|----------------------------------------|------------------------------|
/// | **CLEAR** | `filteredDepth > clearDistance`         | Pass command unchanged       |
/// | **CAUTION** | `brakeDistance ≤ filteredDepth ≤ clearDistance` | Scale throttle linearly  |
/// | **BRAKE** | `filteredDepth < brakeDistance`         | Full stop                    |
///
/// ## Key Design Decisions
///
/// 1. **Latched Speed:** When entering CAUTION/BRAKE, the current speed is latched and used
///    for all threshold calculations until CLEAR is re-entered. This prevents the "brake shrinks
///    the threshold" feedback loop.
///
/// 2. **EMA-Filtered Depth:** Raw depth readings are smoothed with an asymmetric EMA filter
///    (faster when approaching, slower when receding) to reject frame-to-frame noise.
///
/// 3. **Cooldown Timers:** State transitions back to CLEAR require both sufficient depth AND
///    a minimum hold duration, preventing rapid oscillation.
final class SafetySupervisor {

    let config: SafetySupervisorConfig
    private(set) var lastEvent: SafetySupervisorEvent?

    // MARK: - State Machine

    private(set) var state: SafetySupervisorState = .clear

    /// Speed latched at the moment the supervisor first detected a threat (entered CAUTION/BRAKE from CLEAR).
    /// Used for all threshold calculations while the threat persists.
    private var latchedSpeed: Float = 0

    /// EMA-filtered depth. Nil until the first valid reading.
    private var filteredDepth: Float?

    init(config: SafetySupervisorConfig = .init()) {
        self.config = config
    }

    // MARK: - Public

    func supervise(command: ControlCommand, context: PlannerContext) -> ControlCommand {
        // Never re-process our own commands.
        guard command.source != .safetySupervisor else { return command }

        // Only intervene on forward motion (positive throttle).
        guard command.throttle > 0 else {
            return handleNonForwardCommand(command, context: context)
        }

        guard let rawDepth = validDepth(from: context) else {
            // No depth data — cannot evaluate safety. Pass through (conservative: could also brake).
            return command
        }

        // Update EMA-filtered depth.
        let smoothedDepth = updateFilteredDepth(rawDepth: rawDepth)
        let speed = resolveSpeed(context: context)

        // Compute zone boundaries using the appropriate speed.
        let effectiveSpeed = effectiveSpeedForThresholds(currentSpeed: speed)
        let brakeDistance = computeBrakeDistance(speed: effectiveSpeed)
        let clearDistance = computeClearDistance(speed: effectiveSpeed)

        // Evaluate state transition.
        let now = context.timestamp
        let newState = evaluateTransition(
            filteredDepth: smoothedDepth,
            brakeDistance: brakeDistance,
            clearDistance: clearDistance,
            timestamp: now
        )

        // Latch speed on threat onset (CLEAR → non-CLEAR).
        if case .clear = state, newState != .clear {
            latchedSpeed = speed
            playAlertBeepAsync()
        }

        state = newState

        // Compute TTC for diagnostics.
        let ttc = speed > config.minSpeedEpsilonMPS ? smoothedDepth / speed : Float.infinity

        // Build output command.
        let outputCommand: ControlCommand
        let action: SafetySupervisorEvent.Action

        switch state {
        case .clear:
            outputCommand = command
            action = .clear

        case .caution:
            let scale = cautionThrottleScale(
                depth: smoothedDepth,
                brakeDistance: brakeDistance,
                clearDistance: clearDistance
            )
            let reason = String(format: "Depth %.2fm in caution zone [%.2f, %.2f] (v=%.2fm/s)",
                                smoothedDepth, brakeDistance, clearDistance, effectiveSpeed)
            outputCommand = ControlCommand(
                steering: command.steering,
                throttle: command.throttle * scale,
                source: .safetySupervisor,
                reason: reason
            )
            action = .caution(throttleScale: scale, reason: reason)

        case .brake:
            let reason = String(format: "Obstacle %.2fm < brake %.2fm (v=%.2fm/s)",
                                smoothedDepth, brakeDistance, effectiveSpeed)
            outputCommand = .brake(reason: reason)
            action = .brakeApplied(reason)
        }

        lastEvent = SafetySupervisorEvent(
            timestamp: now,
            ttc: ttc,
            forwardDepth: rawDepth,
            filteredDepth: smoothedDepth,
            action: action
        )

        return outputCommand
    }

    func reset() {
        lastEvent = nil
        state = .clear
        latchedSpeed = 0
        filteredDepth = nil
    }

    // MARK: - Zone Boundaries

    /// Compute the BRAKE zone boundary: depth below this → full stop.
    ///
    /// Three components (take the max):
    /// 1. `minBrakeDistanceM` — hard minimum for sensor blind spots.
    /// 2. `speed × ttcBrakeS` — TTC-based threshold.
    /// 3. `speed² / (2 × maxDeceleration)` — kinematic braking distance.
    private func computeBrakeDistance(speed: Float) -> Float {
        let ttcDist = speed * config.ttcBrakeS
        let kinematicDist = (speed * speed) / (2.0 * config.maxDecelerationMPS2)
        return max(config.minBrakeDistanceM, max(ttcDist, kinematicDist))
    }

    /// Compute the CLEAR zone boundary: depth above this → safe to pass through.
    ///
    /// Uses `ttcCautionS` (the larger TTC) as the basis for the clear threshold.
    private func computeClearDistance(speed: Float) -> Float {
        let ttcDist = speed * config.ttcCautionS
        let kinematicDist = (speed * speed) / (2.0 * config.maxDecelerationMPS2)
        return max(config.minCautionDistanceM, max(ttcDist, kinematicDist))
    }

    // MARK: - State Transitions

    private func evaluateTransition(
        filteredDepth: Float,
        brakeDistance: Float,
        clearDistance: Float,
        timestamp: TimeInterval
    ) -> SafetySupervisorState {

        // Always enter BRAKE if depth is critically low, regardless of current state.
        if filteredDepth < brakeDistance {
            switch state {
            case .brake:
                return state  // Stay in BRAKE, preserve the original timestamp.
            default:
                return .brake(since: timestamp)
            }
        }

        // Depth is above brake distance but may be in caution or clear range.
        if filteredDepth < clearDistance {
            // In the caution band.
            switch state {
            case .caution:
                return state  // Stay in CAUTION, preserve timestamp.
            case .brake(let since):
                // Transition BRAKE → CAUTION only after cooldown.
                if timestamp - since >= config.minBrakeDurationS {
                    return .caution(since: timestamp)
                }
                return state  // Hold BRAKE until cooldown expires.
            default:
                return .caution(since: timestamp)
            }
        }

        // Depth is above clear distance — check cooldown before releasing.
        switch state {
        case .clear:
            return .clear

        case .caution(let since):
            if timestamp - since >= config.minCautionDurationS {
                return .clear
            }
            return state  // Hold CAUTION until cooldown expires.

        case .brake(let since):
            if timestamp - since >= config.minBrakeDurationS {
                // Transition through CAUTION, don't jump to CLEAR.
                return .caution(since: timestamp)
            }
            return state
        }
    }

    // MARK: - Throttle Scaling in CAUTION Zone

    /// Linear interpolation: throttle = 0 at brakeDistance, throttle = 1.0 at clearDistance.
    private func cautionThrottleScale(depth: Float, brakeDistance: Float, clearDistance: Float) -> Float {
        let range = clearDistance - brakeDistance
        guard range > 0.001 else { return 0 }
        let fraction = (depth - brakeDistance) / range
        return max(0, min(1, fraction))
    }

    // MARK: - Speed Resolution

    /// Use the latched speed while in a threat state, current speed otherwise.
    private func effectiveSpeedForThresholds(currentSpeed: Float) -> Float {
        switch state {
        case .clear:
            return currentSpeed
        case .caution, .brake:
            // Use the greater of latched speed and current speed.
            // This ensures thresholds never shrink below what triggered the threat,
            // but can grow if the robot somehow accelerates despite the override.
            return max(latchedSpeed, currentSpeed)
        }
    }

    /// Motor RPM speed preferred, then ARKit, then conservative fallback.
    private func resolveSpeed(context: PlannerContext) -> Float {
        if let best = context.bestSpeedMps, best > Double(config.minSpeedEpsilonMPS) {
            return Float(best)
        }
        return max(config.fallbackSpeedMPS, config.minSpeedEpsilonMPS)
    }

    // MARK: - Depth Filtering

    /// Asymmetric EMA: faster alpha when obstacle is approaching, slower when receding.
    private func updateFilteredDepth(rawDepth: Float) -> Float {
        guard let prev = filteredDepth else {
            filteredDepth = rawDepth
            return rawDepth
        }

        let alpha = rawDepth < prev
            ? config.depthEmaAlphaApproaching
            : config.depthEmaAlphaReceding
        let smoothed = alpha * rawDepth + (1 - alpha) * prev
        filteredDepth = smoothed
        return smoothed
    }

    // MARK: - Helpers

    private func handleNonForwardCommand(_ command: ControlCommand, context: PlannerContext) -> ControlCommand {
        // Not moving forward — safe. Transition to CLEAR immediately (no cooldown needed).
        if state != .clear {
            state = .clear
            latchedSpeed = 0
        }
        // Still update depth filter for continuity.
        if let raw = validDepth(from: context) {
            _ = updateFilteredDepth(rawDepth: raw)
            let speed = resolveSpeed(context: context)
            let ttc = speed > config.minSpeedEpsilonMPS ? (filteredDepth ?? raw) / speed : Float.infinity
            lastEvent = SafetySupervisorEvent(
                timestamp: context.timestamp,
                ttc: ttc,
                forwardDepth: raw,
                filteredDepth: filteredDepth ?? raw,
                action: .clear
            )
        } else {
            lastEvent = nil
        }
        return command
    }

    private func validDepth(from context: PlannerContext) -> Float? {
        guard let d = context.forwardDepth, d > 0, d.isFinite else { return nil }
        return d
    }

    // MARK: - Alert Sound

    /// Plays a short system beep on a background queue so it never blocks the safety loop.
    private func playAlertBeepAsync() {
        DispatchQueue.global(qos: .utility).async {
            AudioServicesPlaySystemSound(1052)  // Short alert beep
        }
    }
}
