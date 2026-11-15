import SwiftUI

struct AgentNameCell: View {
    let agent: Agent

    var body: some View {
        VStack(alignment: .leading) {
            Text(agent.name)
                .bold()
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        [agent.clientName, agent.role].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
