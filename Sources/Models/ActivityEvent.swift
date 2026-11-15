import Foundation

/// One entry of the backend's audit log.
struct ActivityEvent: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case fileModified, taskUpdated, agentConnected, agentDisconnected, checkpoint, handoff, message
        case other
    }

    /// The backend's monotonically increasing activity ID, retained for stream resumption.
    let id: String
    var kind: Kind
    var agentName: String?
    var summary: String
    var timestamp: Date

    // Detail fields used by the Activity page. Defaulted so earlier call sites keep compiling.
    /// The backend's action, for example `task.claim` or `file.write`.
    var action: String = ""
    var targetType: String? = nil
    var targetID: String? = nil
    var actorID: String? = nil
    /// agent, human or system.
    var actorKind: String? = nil
    /// The backend's `details` object, pretty-printed.
    var detailsJSON: String? = nil

    var cursor: Int { Int(id) ?? 0 }
}
