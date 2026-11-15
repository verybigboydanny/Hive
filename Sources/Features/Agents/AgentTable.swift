import SwiftUI
import AppKit

struct AgentTable: View {
    let agents: [Agent]
    @Binding var selection: Agent.ID?
    @Binding var composeRecipient: Agent?

    @Environment(ProjectSession.self) private var session
    @State private var sortOrder = [KeyPathComparator(\Agent.name)]

    var body: some View {
        Table(agents.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Agent", value: \.name) { agent in
                AgentNameCell(agent: agent)
            }
            TableColumn("Status") { agent in
                StatusIndicator(title: agent.status.title, color: agent.status.color)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Working On") { agent in
                Text(currentTaskTitle(for: agent) ?? "—")
                    .foregroundStyle(.secondary)
            }
            TableColumn("Last Active", value: \.lastActivity) { agent in
                Text(agent.lastActivity, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)
        }
        .hiveTableStyle()
        .contextMenu(forSelectionType: Agent.ID.self) { ids in
            if let id = ids.first, let agent = agents.first(where: { $0.id == id }) {
                Button("Send Message…") {
                    composeRecipient = agent
                }
                Button("Copy Agent ID") {
                    copy(agent.id)
                }
            }
        }
    }

    private func currentTaskTitle(for agent: Agent) -> String? {
        session.snapshot?.task(withID: agent.currentTaskID)?.title
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
