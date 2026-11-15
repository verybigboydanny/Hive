import Foundation

struct MemoryEntry: Identifiable, Hashable, Sendable {
    let id: String
    var key: String
    var category: String
    var value: String
    var tags: [String]
    var version: Int
    var updatedByName: String?
    var updatedAt: Date
}

struct DecisionRecord: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var decision: String
    var rationale: String?
    var tags: [String]
    var status: String
    var decidedByName: String?
    var createdAt: Date
}

/// Rules, decisions and shared memory (`GET /v1/project/context`).
struct ProjectContext: Hashable, Sendable {
    /// The built-in working rules every agent receives.
    var protocolRules: String
    /// Entries in the memory category `rules`.
    var projectRules: [MemoryEntry]
    var decisions: [DecisionRecord]
    var memory: [MemoryEntry]
}
