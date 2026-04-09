import Foundation

enum MoveDirection: String, Equatable {
    case forward, backward, left, right
}

enum AgentAction: Equatable {
    case move(direction: MoveDirection, throttle: Float)
    case stop
    case queryStatus
    case unknown(raw: String)
}

struct ActionResult: Equatable {
    let success: Bool
    let message: String
}
