import Foundation

protocol CommandInterpreter {
    func interpret(_ text: String) -> AgentAction
}
