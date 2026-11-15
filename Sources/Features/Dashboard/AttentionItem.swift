import Foundation

/// Something on the Dashboard that needs a person's eyes: a blocked task, an expired claim, a waiting handoff.
struct AttentionItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case blockedTask, expiredLease, pendingHandoff
    }

    enum Destination: Hashable, Sendable {
        case task(HiveTask.ID)
        case messages
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let destination: Destination

    static let limit = 6

    /// Blocked tasks first, then expired claims, then handoffs waiting for someone to accept them.
    static func items(from snapshot: ProjectSnapshot) -> [AttentionItem] {
        var items: [AttentionItem] = []

        for task in snapshot.tasks where task.status == .blocked {
            var parts: [String] = []
            if let owner = task.ownerName { parts.append("Held by \(owner)") }
            if let note = task.progressNote, !note.isEmpty { parts.append(note) }
            items.append(AttentionItem(
                id: "blocked-\(task.id)", kind: .blockedTask, title: task.title,
                detail: parts.isEmpty ? "Blocked" : "Blocked. " + parts.joined(separator: ". "), destination: .task(task.id)
            ))
        }

        let heldStatuses: [HiveTask.Status] = [.inProgress, .blocked, .review]
        for task in snapshot.tasks where task.isLeaseExpired && heldStatuses.contains(task.status) {
            let owner = task.ownerName.map { "\($0)'s claim has expired" } ?? "The claim has expired"
            items.append(AttentionItem(
                id: "lease-\(task.id)", kind: .expiredLease, title: task.title,
                detail: owner + ". Another agent can take this task over.", destination: .task(task.id)
            ))
        }

        for handoff in snapshot.handoffs {
            let recipient = handoff.toAgentName ?? "any agent"
            items.append(AttentionItem(
                id: "handoff-\(handoff.id)", kind: .pendingHandoff, title: handoff.taskTitle,
                detail: "Handoff from \(handoff.fromAgentName) to \(recipient) is waiting to be accepted.", destination: .messages
            ))
        }
        return Array(items.prefix(limit))
    }
}
