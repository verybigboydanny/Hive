import Foundation

/// Search and filters for the Activity page.
struct ActivityFilter: Equatable, Sendable {
    var searchText = ""
    var category: ActivityCategory = .all
    /// Only events by this actor (an agent id, or "user").
    var actorID: String?

    var isFiltering: Bool { !searchText.isEmpty || category != .all || actorID != nil }

    func matches(_ event: ActivityEvent) -> Bool {
        guard category.matches(action: event.action) else { return false }
        if let actorID, event.actorID != actorID { return false }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let haystack = [event.summary, event.action, event.agentName ?? "", event.targetID ?? ""]
        return haystack.contains { $0.localizedStandardContains(query) }
    }

    func apply(to events: [ActivityEvent]) -> [ActivityEvent] {
        events.filter(matches)
    }
}

/// Someone who appears in the activity log, for the actor filter menu.
struct ActivityActor: Identifiable, Hashable, Sendable {
    let id: String
    let name: String

    /// The distinct actors in `events`, sorted by name.
    static func actors(in events: [ActivityEvent]) -> [ActivityActor] {
        var names: [String: String] = [:]
        for event in events {
            guard let id = event.actorID else { continue }
            names[id] = names[id] ?? event.agentName ?? id
        }
        return names.map { ActivityActor(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
