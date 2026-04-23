import Foundation
import AudioToolbox

// MARK: - Config

/// Tunable parameters for the time-to-brake safety policy.
///
/// See `DESIGN.md` for the full derivation. The three policy parameters
/// (`tSysS`, `aMaxMPS2`, `dMarginM`) are physical and independent — change one
/// and the effect on `criticalDistance` is predictable from the formula below:
///
///     criticalDistance(v) = v * tSysS + v² / (2 * aMaxMPS2) + dMarginM
struct SafetySupervisorConfig {
    // MARK: Policy parameters (tune these from field testing)

    /// System reaction latency (seconds): sense → decide → actuator effect.
    var tSysS: Float = 0.1

    /// Maximum achievable deceleration under emergency brake (m/s²).
    /// Empirical: measured 1.19 m/s² at 0.76 m/s with neutral throttle
    /// (no friction brakes — back-EMF and rolling resistance only).
    /// Set to 1.0 with ~20% safety factor; re-measure at multiple speeds.
    var aMaxMPS2: Float = 1.0

    /// Fixed post-stop safety standoff (meters).
    /// Includes ~0.13 m sensor-to-bumper offset (phone is mounted behind
    /// the front bumper, not at the leading edge) plus 0.07 m desired
    /// clearance. When depth reads 0.13 m, the bumper is already at the wall.
    var dMarginM: Float = 0.2

    // MARK: Filtering / debouncing

    /// Exponential moving average weight for forward depth (0..1).
    /// Higher = reacts faster to new readings, less smoothing.
    var alphaSmoothing: Float = 0.5

    /// Continuous clearance duration required before releasing BRAKE (seconds).
    /// Debounces single-frame depth spikes; does NOT enforce a minimum brake duration.
    var releaseHoldS: TimeInterval = 0.3

    // MARK: Misc

    /// Conservative speed used when neither motor nor ARKit speed is available (m/s).
    var fallbackSpeedMPS: Float = 0.3

    /// Speed below which the robot is considered "stopped" — used to capture the stop snapshot (m/s).
    var stopSpeedEpsilonMPS: Float = 0.05

    /// Avoid divide-by-zero when reporting diagnostics.
    var minSpeedEpsilonMPS: Float = 0.01
}

// MARK: - State

/// Two-state safety machine. See `DESIGN.md §5`.
enum SafetySupervisorState: Equatable {
    case safe
    case brake(since: TimeInterval)
}

// MARK: - SafetySupervisor

/// Enforces the time-to-brake collision-avoidance policy on planner output.
///
/// ## Policy (one equation)
///
///     criticalDistance(v) = v * tSysS + v² / (2 * aMaxMPS2) + dMarginM
///
/// ## Rule
///
/// - `smoothedDepth > criticalDistance` → pass planner command through.
/// - `smoothedDepth <= criticalDistance` → emit `ControlCommand.brake`, latch the trigger speed.
///
/// ## Anti-oscillation invariant
///
/// While in BRAKE, `criticalDistance` is computed with the **latched** speed (the
/// speed at trigger), never the current speed. This prevents the feedback loop
/// "brake → speed drops → criticalDistance shrinks → release → accelerate → trigger".
///
/// Release requires either:
/// 1. `smoothedDepth > criticalDistance(latchedSpeed)` continuously for `releaseHoldS`, or
/// 2. operator commands `throttle <= 0` (stop, neutral, or reverse).
final class SafetySupervisor {

    let config: SafetySupervisorConfig
    private(set) var state: SafetySupervisorState = .safe
    private(set) var lastEvent: SafetySupervisorEvent?
    private(set) var currentBrake: SafetyBrakeRecord?

    // MARK: - Internal state

    /// Smoothed depth (exponential moving average). Nil until first valid raw reading.
    private var smoothedDepth: Float?

    /// Speed captured at BRAKE trigger. Frozen until release.
    private var latchedSpeed: Float = 0

    /// Monotonic timestamp of the first frame with continuous clearance.
    /// Used to enforce `releaseHoldS`. Nil means "no clearance streak in progress".
    private var clearanceStartedAt: TimeInterval?

    init(config: SafetySupervisorConfig = .init()) {
        self.config = config
    }

    // MARK: - Public

    func supervise(command: ControlCommand, context: PlannerContext) -> ControlCommand {
        // Never re-process our own brake commands.
        guard command.source != .safetySupervisor else { return command }

        // Non-forward command (stop, neutral, reverse) — operator override.
        // Drop latch, pass through.
        guard command.throttle > 0 else {
            return handleNonForwardCommand(command, context: context)
        }

        guard let rawDepth = validDepth(from: context) else {
            // No depth data → cannot evaluate safety. Pass through, clear any stale event.
            lastEvent = nil
            return command
        }

        let smoothed = updateSmoothedDepth(raw: rawDepth)
        let vNow = resolveSpeed(context: context)
        let now = context.timestamp

        // Speed used for critical-distance calculation: latched while braking, current otherwise.
        let vForThreshold: Float
        switch state {
        case .safe:         vForThreshold = vNow
        case .brake:        vForThreshold = latchedSpeed
        }
        let dCrit = criticalDistance(speed: vForThreshold)

        let output: ControlCommand
        switch state {
        case .safe:
            output = evaluateSafeState(
                command: command,
                context: context,
                rawDepth: rawDepth,
                smoothed: smoothed,
                speed: vNow,
                criticalDistance: dCrit,
                now: now
            )

        case .brake:
            output = evaluateBrakeState(
                command: command,
                context: context,
                rawDepth: rawDepth,
                smoothed: smoothed,
                speedNow: vNow,
                criticalDistance: dCrit,
                now: now
            )
        }

        return output
    }

    func reset() {
        state = .safe
        lastEvent = nil
        currentBrake = nil
        smoothedDepth = nil
        latchedSpeed = 0
        clearanceStartedAt = nil
    }

    // MARK: - State handlers

    private func evaluateSafeState(
        command: ControlCommand,
        context: PlannerContext,
        rawDepth: Float,
        smoothed: Float,
        speed: Float,
        criticalDistance: Float,
        now: TimeInterval
    ) -> ControlCommand {

        if smoothed <= criticalDistance {
            // TRIGGER: SAFE → BRAKE.
            latchedSpeed = speed
            let trigger = SafetyBrakeTrigger(
                timestamp: now,
                pose: context.pose,
                speed: speed,
                depth: smoothed,
                criticalDistance: criticalDistance,
                motorSpeed: Float(context.motorSpeedMps ?? Double.nan),
                arkitSpeed: Float(context.arkitSpeedMps ?? Double.nan)
            )
            currentBrake = SafetyBrakeRecord(trigger: trigger, stop: nil)
            clearanceStartedAt = nil
            state = .brake(since: now)
            playAlertBeepAsync()

            let reason = String(
                format: "Obstacle %.2fm <= criticalDistance %.2fm (v=%.2fm/s)",
                smoothed, criticalDistance, speed
            )
            lastEvent = SafetySupervisorEvent(
                timestamp: now,
                rawDepth: rawDepth,
                smoothedDepth: smoothed,
                speed: speed,
                criticalDistance: criticalDistance,
                isBraking: true,
                reason: reason
            )
            return .brake(reason: reason)
        }

        // Stay SAFE.
        lastEvent = SafetySupervisorEvent(
            timestamp: now,
            rawDepth: rawDepth,
            smoothedDepth: smoothed,
            speed: speed,
            criticalDistance: criticalDistance,
            isBraking: false,
            reason: nil
        )
        return command
    }

    private func evaluateBrakeState(
        command: ControlCommand,
        context: PlannerContext,
        rawDepth: Float,
        smoothed: Float,
        speedNow: Float,
        criticalDistance: Float,
        now: TimeInterval
    ) -> ControlCommand {

        // Capture stop snapshot on first frame where motion has ceased.
        //
        // `speedNow` passed in is the thresholding speed (may include a conservative
        // fallback when sensors report no motion). Stop detection needs the *raw*
        // sensor reading: if motor or ARKit explicitly report speeds below the stop
        // epsilon, the robot is stopped. Lack of sensor data is treated as "unknown",
        // not "stopped".
        if var record = currentBrake, record.stop == nil, isStopped(context: context) {
            record.stop = SafetyBrakeStop(
                timestamp: now,
                pose: context.pose,
                depth: smoothed
            )
            currentBrake = record
        }

        // Track clearance streak.
        if smoothed > criticalDistance {
            if clearanceStartedAt == nil {
                clearanceStartedAt = now
            }
        } else {
            clearanceStartedAt = nil
        }

        // Release if clearance held long enough.
        if let start = clearanceStartedAt, now - start >= config.releaseHoldS {
            state = .safe
            currentBrake = nil
            latchedSpeed = 0
            clearanceStartedAt = nil

            lastEvent = SafetySupervisorEvent(
                timestamp: now,
                rawDepth: rawDepth,
                smoothedDepth: smoothed,
                speed: speedNow,
                criticalDistance: self.criticalDistance(speed: speedNow),
                isBraking: false,
                reason: "Released: cleared criticalDistance for \(config.releaseHoldS)s"
            )
            return command
        }

        // Hold BRAKE.
        let reason = String(
            format: "BRAKE held: depth %.2fm vs criticalDistance %.2fm (latched v=%.2fm/s)",
            smoothed, criticalDistance, latchedSpeed
        )
        lastEvent = SafetySupervisorEvent(
            timestamp: now,
            rawDepth: rawDepth,
            smoothedDepth: smoothed,
            speed: latchedSpeed,
            criticalDistance: criticalDistance,
            isBraking: true,
            reason: reason
        )
        return .brake(reason: reason)
    }

    private func handleNonForwardCommand(
        _ command: ControlCommand,
        context: PlannerContext
    ) -> ControlCommand {
        // Operator override: drop latch, return to SAFE.
        if case .brake = state {
            state = .safe
            currentBrake = nil
            latchedSpeed = 0
            clearanceStartedAt = nil
        }

        // Keep the smoothing filter alive so re-entry to forward motion is continuous.
        if let raw = validDepth(from: context) {
            let smoothed = updateSmoothedDepth(raw: raw)
            let speed = resolveSpeed(context: context)
            lastEvent = SafetySupervisorEvent(
                timestamp: context.timestamp,
                rawDepth: raw,
                smoothedDepth: smoothed,
                speed: speed,
                criticalDistance: criticalDistance(speed: speed),
                isBraking: false,
                reason: nil
            )
        } else {
            lastEvent = nil
        }
        return command
    }

    // MARK: - Math

    /// See `DESIGN.md §4`.
    ///
    /// `criticalDistance(v) = v * tSysS + v² / (2 * aMaxMPS2) + dMarginM`
    func criticalDistance(speed v: Float) -> Float {
        let reaction = v * config.tSysS
        let stopping = (v * v) / (2.0 * max(config.aMaxMPS2, 1e-3))
        return reaction + stopping + config.dMarginM
    }

    // MARK: - Helpers

    private func updateSmoothedDepth(raw: Float) -> Float {
        guard let prev = smoothedDepth else {
            smoothedDepth = raw
            return raw
        }
        let alpha = config.alphaSmoothing
        let next = alpha * raw + (1 - alpha) * prev
        smoothedDepth = next
        return next
    }

    private func resolveSpeed(context: PlannerContext) -> Float {
        if let best = context.bestSpeedMps, best > Double(config.minSpeedEpsilonMPS) {
            return Float(best)
        }
        return max(config.fallbackSpeedMPS, config.minSpeedEpsilonMPS)
    }

    /// True when *any* raw speed source confirms the robot is moving slower than
    /// `stopSpeedEpsilonMPS`. Absent sensor data alone does not count — we refuse
    /// to infer "stopped" from silence.
    private func isStopped(context: PlannerContext) -> Bool {
        let epsilon = Double(config.stopSpeedEpsilonMPS)
        if let motor = context.motorSpeedMps, abs(motor) < epsilon { return true }
        if let arkit = context.arkitSpeedMps, abs(arkit) < epsilon { return true }
        return false
    }

    private func validDepth(from context: PlannerContext) -> Float? {
        guard let d = context.forwardDepth, d > 0, d.isFinite else { return nil }
        return d
    }

    private func playAlertBeepAsync() {
        DispatchQueue.global(qos: .utility).async {
            AudioServicesPlaySystemSound(1052)
        }
    }
}
