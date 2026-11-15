import SwiftUI

struct AgentInspector: View {
    let agentID: Agent.ID?
    @Binding var composeRecipient: Agent?
    @Environment(ProjectSession.self) private var session

    var body: some View {
        if let snapshot = session.snapshot, let agentID, let agent = snapshot.agents.first(where: { $0.id == agentID }) {
            AgentDetailView(agent: agent, snapshot: snapshot, composeRecipient: $composeRecipient)
        } else {
            ContentUnavailableView("No Agent Selected", systemImage: "person")
        }
    }
}
