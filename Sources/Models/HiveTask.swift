import Foundation

/// A task. Named HiveTask to avoid clashing with Swift's Task.
/// Mapped from the backend's task object (see backend-contract.md, `task_list`).
struct HiveTask: Identifiable, Hashable, Sendable {
    enum Status: String, CaseIterable, Sendable {
        case backlog, inProgress, blocked, review, done, cancelled
    }

    enum Priority: String, CaseIterable, Comparable, Sendable {
        case low, normal, high, urgent

        var rank: Int {
            switch self {
            case .low: 0
            case .normal: 1
            case .high: 2
            case .urgent: 3
            }
        }

        static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rank < rhs.rank }
    }

    /// A dependency that is not finished yet.
    struct Blocker: Hashable, Sendable {
        let id: String
        let status: String
    }

    let id: String
    var title: String
    var summary: String
    var status: Status
    var assigneeID: Agent.ID?
    var progress: Double?
    var dependencyIDs: [HiveTask.ID]
    var updatedAt: Date

    // Detail fields used by the Tasks page. Defaulted so earlier call sites keep compiling.
    var details: String = ""
    var priority: Priority = .normal
    var labels: [String] = []
    var ownerName: String? = nil
    var leaseExpiresAt: Date? = nil
    var isLeaseExpired: Bool = false
    var blockedBy: [Blocker] = []
    var isClaimable: Bool = false
    var version: Int = 1
    var progressNote: String? = nil
    var resultSummary: String? = nil
    var cancelReason: String? = nil
    var createdBy: String? = nil
    var parentID: String? = nil
    var createdAt: Date? = nil
    var completedAt: Date? = nil
}
