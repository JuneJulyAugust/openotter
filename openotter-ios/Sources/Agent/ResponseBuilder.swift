import Foundation

protocol ResponseBuilding {
    func build(action: AgentAction, result: ActionResult) -> String
}

struct ResponseBuilder: ResponseBuilding {

    func build(action: AgentAction, result: ActionResult) -> String {
        guard result.success else { return result.message }

        switch action {
        case .move(let direction, _):
            switch direction {
            case .forward:  return "Drive"
            case .backward: return "Reverse"
            case .left:     return "Left"
            case .right:    return "Right"
            }
        case .stop:
            return "Park"
        case .queryStatus:
            return result.message
        case .unknown(let raw):
            return "Unknown: \(raw)"
        }
    }
}
