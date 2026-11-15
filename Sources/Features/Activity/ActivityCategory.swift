import Foundation

/// Groups the backend's activity actions (`task.claim`, `file.write`, ...) for filtering.
enum ActivityCategory: String, CaseIterable, Identifiable, Sendable {
    case all, tasks, files, messages, handoffs, agents, checkpoints, knowledge, security

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Activity"
        case .tasks: "Tasks"
        case .files: "Files"
        case .messages: "Messages"
        case .handoffs: "Handoffs"
        case .agents: "Agents"
        case .checkpoints: "Checkpoints"
        case .knowledge: "Memory & Decisions"
        case .security: "Security"
        }
    }

    /// The action prefixes (before the dot) this category covers.
    private var prefixes: [String] {
        switch self {
        case .all: []
        case .tasks: ["task."]
        case .files: ["file.", "folder."]
        case .messages: ["message."]
        case .handoffs: ["handoff."]
        case .agents: ["agent."]
        case .checkpoints: ["checkpoint."]
        case .knowledge: ["memory.", "decision."]
        case .security: ["security."]
        }
    }

    func matches(action: String) -> Bool {
        self == .all || prefixes.contains { action.hasPrefix($0) }
    }
}
