import Foundation

protocol SkillProviding {
    var name: String { get }
    var description: String { get }
    func execute(parameters: [String: Any]) -> ActionResult
}

protocol SkillRegistering {
    func register(_ skill: any SkillProviding)
    func skill(named name: String) -> (any SkillProviding)?
    var allSkills: [any SkillProviding] { get }
}

/// No-op stub for v1. Skills plug in here in future versions.
final class NoOpSkillRegistry: SkillRegistering {
    func register(_ skill: any SkillProviding) {}
    func skill(named name: String) -> (any SkillProviding)? { nil }
    var allSkills: [any SkillProviding] { [] }
}
