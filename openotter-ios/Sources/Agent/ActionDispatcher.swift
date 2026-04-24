import Foundation

/// Narrow interface for setting planner goals — satisfied by PlannerOrchestrator.
/// `setGoal` implies "enter Drive and pursue this goal"; `reset` implies
/// "enter Park". The orchestrator coordinates the corresponding firmware
/// mode transition through its own injected `OperatingModeReceiving`, so
/// the dispatcher does not need to know the BLE layer exists.
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
    private let interpreter: KeywordInterpreter

    init(goalReceiver: any GoalReceiving,
         statusProvider: any StatusProviding,
         interpreter: KeywordInterpreter) {
        self.goalReceiver = goalReceiver
        self.statusProvider = statusProvider
        self.interpreter = interpreter
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

        case .setSpeed(let throttle):
            interpreter.setThrottle(throttle)
            let pct = Int(interpreter.currentThrottle * 100)
            return ActionResult(success: true,
                                message: "Speed set to \(String(format: "%.1f", interpreter.currentThrottle)) (\(pct)%)")

        case .help:
            return ActionResult(success: true,
                                message: Self.helpText(currentThrottle: interpreter.currentThrottle),
                                speakable: false)

        case .unknown(let raw):
            return ActionResult(success: false, message: "Unrecognized command: \(raw)")
        }
    }

    // MARK: - Help Text

    private static func helpText(currentThrottle: Float) -> String {
        let pct = Int(currentThrottle * 100)
        return """
        🤖 OpenOtter Commands

        Movement:
          🚗 drive / d / go — Drive forward
          🔙 reverse / r    — Drive backward
          🅿️ park / p / stop — Stop & park

        Speed presets:
          🐢 slow            — 20%
          🚗 normal           — 40% (default)
          🐇 fast             — 80%
          speed <0.1–1.0>    — Set exact speed

        Info:
          📊 status / s      — Vehicle status
          ❓ help / h        — This message

        Current speed: \(String(format: "%.1f", currentThrottle)) (\(pct)%)
        """
    }
}
