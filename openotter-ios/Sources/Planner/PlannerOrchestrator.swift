import Foundation
import Combine

/// Wires the active planner and safety supervisor together.
/// This is the only component SelfDrivingViewModel calls.
final class PlannerOrchestrator: ObservableObject {

    // MARK: - Components

    private(set) var activePlanner: any PlannerProtocol
    private let supervisor = SafetySupervisor()

    // MARK: - Published State

    @Published private(set) var lastCommand: ControlCommand = .neutral
    @Published private(set) var lastSupervisorEvent: SafetySupervisorEvent?

    /// True while the supervisor is actively braking (drives alarm + overlay in UI).
    @Published private(set) var isOverridden: Bool = false

    /// Current safety supervisor state for UI feedback.
    @Published private(set) var supervisorState: SafetySupervisorState = .safe

    /// Trigger + (optional) stop snapshot for the current BRAKE episode.
    /// Nil while SAFE.
    @Published private(set) var brakeRecord: SafetyBrakeRecord?

    // MARK: - Init

    init(planner: any PlannerProtocol) {
        self.activePlanner = planner
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

    // MARK: - Goal Passthrough

    func setGoal(_ goal: PlannerGoal) {
        activePlanner.setGoal(goal)
    }

    func reset() {
        activePlanner.reset()
        supervisor.reset()
        lastCommand = .neutral
        lastSupervisorEvent = nil
        isOverridden = false
        supervisorState = .safe
        brakeRecord = nil
    }
}
