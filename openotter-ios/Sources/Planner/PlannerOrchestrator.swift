import Foundation
import Combine

/// Wires the active planner and safety supervisor together.
/// This is the only component SelfDrivingViewModel calls.
///
/// Owns the operating mode (Park vs Drive) — the single iOS-side source of
/// truth that mirrors the firmware mode characteristic (FE44). Every
/// `setGoal` implies "I want to drive" and every `reset` implies "park";
/// subsystems that care about mode transitions are notified through the
/// optional `OperatingModeReceiving` push channel.
final class PlannerOrchestrator: ObservableObject {

    // MARK: - Components

    private(set) var activePlanner: any PlannerProtocol
    private let supervisor = SafetySupervisor()
    private weak var modeReceiver: (any OperatingModeReceiving)?

    // MARK: - Published State

    @Published private(set) var lastCommand: ControlCommand = .neutral
    @Published private(set) var lastSupervisorEvent: SafetySupervisorEvent?

    /// Current operating mode. Initial value is `.park` so the system boots
    /// into a stable, non-actuating state regardless of the firmware's own
    /// post-connect default; the BLE bridge will push this through on the
    /// first transition.
    @Published private(set) var operatingMode: OperatingMode = .park

    /// True while the supervisor is actively braking (drives alarm + overlay in UI).
    @Published private(set) var isOverridden: Bool = false

    /// Current safety supervisor state for UI feedback.
    @Published private(set) var supervisorState: SafetySupervisorState = .safe

    /// Trigger + (optional) stop snapshot for the current BRAKE episode.
    /// Nil while SAFE.
    @Published private(set) var brakeRecord: SafetyBrakeRecord?

    // MARK: - Init

    init(planner: any PlannerProtocol,
         modeReceiver: (any OperatingModeReceiving)? = nil) {
        self.activePlanner = planner
        self.modeReceiver = modeReceiver
    }

    // MARK: - Runtime Planner Swap

    func swapPlanner(_ newPlanner: any PlannerProtocol) {
        activePlanner.reset()
        activePlanner = newPlanner
    }

    // MARK: - Control Tick

    /// Called every control loop iteration. Returns the safe command to execute.
    func tick(context: PlannerContext) -> ControlCommand {
        let plannerCommand = activePlanner.plan(context: context)
        let safeCommand = supervisor.supervise(command: plannerCommand, context: context)

        lastCommand = safeCommand
        lastSupervisorEvent = supervisor.lastEvent
        supervisorState = supervisor.state
        brakeRecord = supervisor.currentBrake

        if case .brake = supervisor.state {
            isOverridden = true
        } else {
            isOverridden = false
        }

        return safeCommand
    }

    // MARK: - Mode Transitions

    /// Transition to Drive and pursue `goal`. Always pushes Drive through
    /// the receiver (idempotent), since the caller's intent is "I want
    /// motion" — even if we believed we were already driving, the firmware
    /// may have been forced into Park by another client.
    func setGoal(_ goal: PlannerGoal) {
        transition(to: .drive)
        activePlanner.setGoal(goal)
    }

    /// Transition to Park: clear planner intent, drop any supervisor latch,
    /// and push Park through the receiver so the firmware suppresses its
    /// reverse supervisor and forces neutral throttle. This is the one
    /// terminal state from which neither supervisor can re-arm.
    func reset() {
        activePlanner.reset()
        supervisor.reset()
        lastCommand = .neutral
        lastSupervisorEvent = nil
        isOverridden = false
        supervisorState = .safe
        brakeRecord = nil
        transition(to: .park)
    }

    private func transition(to mode: OperatingMode) {
        if operatingMode != mode {
            operatingMode = mode
        }
        modeReceiver?.setOperatingMode(mode)
    }
}
