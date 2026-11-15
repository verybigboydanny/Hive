import Foundation

/// A structured work transfer between agents. Mapped from the backend's handoff object.
struct Handoff: Identifiable, Hashable, Sendable {
    enum Status: String, CaseIterable, Sendable {
        case pending, accepted, cancelled
    }

    let id: String
    var taskTitle: String
    var fromAgentName: String
    var toAgentName: String?
    var createdAt: Date

    // Detail fields used by the Messages page. Defaulted so earlier call sites keep compiling.
    var status: Status = .pending
    var taskID: String? = nil
    var fromID: String? = nil
    var toID: String? = nil
    var summary: String = ""
    var completedWork: String? = nil
    var remainingWork: String? = nil
    var filesModified: [String] = []
    var nextAction: String? = nil
    var context: String? = nil
    var acceptedByName: String? = nil
    var acceptedAt: Date? = nil
}
