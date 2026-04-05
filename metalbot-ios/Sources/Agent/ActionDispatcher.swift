import Foundation

/// Narrow interface for setting planner goals — satisfied by PlannerOrchestrator.
protocol GoalReceiving: AnyObject {
    func setGoal(_ goal: PlannerGoal)
    func reset()
}

extension PlannerOrchestrator: GoalReceiving {}

/// Narrow interface for querying car status.
protocol StatusProviding {
    func currentStatus() -> String
}

protocol ActionDispatching {
    func dispatch(_ action: AgentAction) -> ActionResult
}

final class ActionDispatcher: ActionDispatching {

    private weak var goalReceiver: (any GoalReceiving)?
    private let statusProvider: any StatusProviding

    init(goalReceiver: any GoalReceiving, statusProvider: any StatusProviding) {
        self.goalReceiver = goalReceiver
        self.statusProvider = statusProvider
    }

    func dispatch(_ action: AgentAction) -> ActionResult {
        switch action {
        case .move(let direction, let throttle):
            let signedThrottle: Float
            switch direction {
            case .forward:  signedThrottle = throttle
            case .backward: signedThrottle = -throttle
            case .left:     signedThrottle = throttle
            case .right:    signedThrottle = throttle
            }
            goalReceiver?.setGoal(.constantThrottle(targetThrottle: signedThrottle))
            return ActionResult(success: true, message: "Throttle set to \(signedThrottle)")

        case .stop:
            goalReceiver?.reset()
            return ActionResult(success: true, message: "Stopped")

        case .queryStatus:
            let status = statusProvider.currentStatus()
            return ActionResult(success: true, message: status)

        case .unknown(let raw):
            return ActionResult(success: false, message: "Unrecognized command: \(raw)")
        }
    }
}
