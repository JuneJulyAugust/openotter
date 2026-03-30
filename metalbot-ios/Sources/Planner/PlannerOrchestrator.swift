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
    @Published private(set) var isOverridden: Bool = false

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
        isOverridden = safeCommand.source == .safetySupervisor

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
    }
}
