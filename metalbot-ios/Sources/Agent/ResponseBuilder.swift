import Foundation

protocol ResponseBuilding {
    func build(action: AgentAction, result: ActionResult) -> String
}

struct ResponseBuilder: ResponseBuilding {

    func build(action: AgentAction, result: ActionResult) -> String {
        switch action {
        case .move(let direction, let throttle):
            if result.success {
                let pct = Int(throttle * 100)
                return "Moving \(direction.rawValue) at \(pct)% throttle."
            } else {
                return "Cannot move \(direction.rawValue): \(result.message)."
            }

        case .stop:
            if result.success {
                return "Stopped. All actuators neutral."
            } else {
                return "Stop failed: \(result.message)."
            }

        case .queryStatus:
            return result.message

        case .unknown(let raw):
            return "Unknown command: \"\(raw)\". Use /forward, /backward, /stop, or /status."
        }
    }
}
