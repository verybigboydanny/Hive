import Foundation

/// An agent registered with Hive. Mapped from the backend's agent object (see backend-contract.md, `agent_list`).
struct Agent: Identifiable, Hashable, Sendable {
    enum Status: String, CaseIterable, Sendable {
        case working, online, idle, offline
    }

    let id: String
    var name: String
    var clientName: String
    var status: Status
    var currentTaskID: HiveTask.ID?
    var lastActivity: Date

    // Detail fields used by the Agents page. Defaulted so earlier call sites keep compiling.
    var role: String? = nil
    var model: String? = nil
    var capabilities: [String] = []
    /// The agent's own short message, set with `agent_update_status`.
    var statusMessage: String? = nil
    /// The backend's `status`: active, idle, blocked or offline.
    var reportedStatus: String? = nil
    /// The backend's `presence`: online, away or offline (derived from last_seen_at).
    var presence: String? = nil
    var registeredAt: Date? = nil
    var openSessions: Int = 0
    var activeTaskIDs: [HiveTask.ID] = []
}
