import Foundation

/// Search and filter for the Agents page.
struct AgentFilter: Equatable, Sendable {
    var searchText = ""
    var hidesOffline = false

    var isFiltering: Bool { !searchText.isEmpty || hidesOffline }

    func matches(_ agent: Agent) -> Bool {
        if hidesOffline && agent.status == .offline { return false }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let haystack = [agent.name, agent.clientName, agent.role ?? "", agent.model ?? "", agent.statusMessage ?? "",
                        agent.capabilities.joined(separator: " ")]
        return haystack.contains { $0.localizedStandardContains(query) }
    }

    func apply(to agents: [Agent]) -> [Agent] {
        agents.filter(matches)
    }
}
