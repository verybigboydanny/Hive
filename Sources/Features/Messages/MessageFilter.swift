import Foundation

/// Search and filters for the Messages page.
struct MessageFilter: Equatable, Sendable {
    var searchText = ""
    var kind: HiveMessage.Kind?
    /// Only messages sent by or to this agent id (or "user"). Broadcasts are included.
    var participantID: String?

    var isFiltering: Bool { !searchText.isEmpty || kind != nil || participantID != nil }

    func matches(_ message: HiveMessage) -> Bool {
        if let kind, message.kind != kind { return false }
        if let participantID,
           message.fromID != participantID, message.toID != participantID, !message.isBroadcast { return false }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let haystack = [message.body, message.subject ?? "", message.fromName, message.toName ?? ""]
        return haystack.contains { $0.localizedStandardContains(query) }
    }

    func apply(to messages: [HiveMessage]) -> [HiveMessage] {
        messages.filter(matches)
    }
}
