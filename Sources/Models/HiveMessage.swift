import Foundation

/// A persistent message between agents and/or the user. Mapped from the backend's message object.
struct HiveMessage: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case message, question, answer, notice
    }

    let id: String
    var seq: Int
    var threadID: String?
    var kind: Kind
    var fromID: String?
    var fromName: String
    /// agent or human (as reported by the backend).
    var fromKind: String
    /// nil means the message was sent to everyone.
    var toID: String?
    var toName: String?
    var subject: String?
    var body: String
    var taskID: String?
    var createdAt: Date

    var isFromUser: Bool { fromKind == "human" }
    var isBroadcast: Bool { toID == nil }
}

/// What the user types into the composer. Sent with `POST /v1/messages` (the backend attributes it to the user).
struct NewMessageDraft: Sendable {
    /// An agent id, or "all".
    var to: String
    var body: String
    var subject: String? = nil
    var kind: HiveMessage.Kind = .message
    var taskID: String? = nil
}
