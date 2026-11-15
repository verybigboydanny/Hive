import SwiftUI

/// Every agent registered with the project, with search, sorting and a detail inspector.
struct AgentsView: View {
    @Environment(ProjectSession.self) private var session
    @State private var filter = AgentFilter()
    @State private var selection: Agent.ID?
    @State private var showsInspector = false
    @State private var composeRecipient: Agent?

    var body: some View {
        let agents = session.snapshot?.agents ?? []
        Group {
            if agents.isEmpty {
                ContentUnavailableView {
                    Label("No Agents Yet", systemImage: "person.2.slash")
                } description: {
                    Text("Agents appear here once they register with this project through the Hive MCP server.")
                } actions: {
                    Button {
                        session.selection = .setUpAgent
                    } label: {
                        Label("Set Up Agent", systemImage: "person.badge.plus")
                    }
                    SettingsLink {
                        Label("Connect Claude…", systemImage: "link")
                    }
                }
            } else {
                AgentTable(agents: filter.apply(to: agents), selection: $selection, composeRecipient: $composeRecipient)
                    .overlay {
                        if filter.isFiltering && filter.apply(to: agents).isEmpty {
                            ContentUnavailableView.search
                        }
                    }
            }
        }
        .searchable(text: $filter.searchText, prompt: "Search agents")
        .toolbar {
            ToolbarItem {
                Toggle("Hide Offline Agents", systemImage: "eye.slash", isOn: $filter.hidesOffline)
                    .help("Hide agents that are offline")
            }
        }
        .inspector(isPresented: $showsInspector) {
            AgentInspector(agentID: selection, composeRecipient: $composeRecipient)
                .inspectorColumnWidth(min: HiveMetrics.inspectorMinWidth, ideal: HiveMetrics.inspectorIdealWidth, max: HiveMetrics.inspectorMaxWidth)
        }
        .sheet(item: $composeRecipient) { agent in
            ComposeMessageSheet(recipientID: agent.id)
        }
        .onChange(of: selection) {
            showsInspector = selection != nil
        }
        .onChange(of: session.focusedAgentID, initial: true) {
            applyFocus()
        }
    }

    private func applyFocus() {
        guard let id = session.focusedAgentID else { return }
        filter = AgentFilter()
        selection = id
        session.focusedAgentID = nil
    }
}
