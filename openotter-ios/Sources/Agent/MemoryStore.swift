import Foundation

protocol MemoryStoring {
    func store(key: String, value: String)
    func recall(key: String) -> String?
    func allEntries() -> [(key: String, value: String)]
}

/// No-op stub for v1. Persistent memory in future versions.
final class NoOpMemoryStore: MemoryStoring {
    func store(key: String, value: String) {}
    func recall(key: String) -> String? { nil }
    func allEntries() -> [(key: String, value: String)] { [] }
}
