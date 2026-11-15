import SwiftUI

struct AgentRow: View {
    let agent: Agent
    let currentTask: HiveTask?

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack(alignment: .firstTextBaseline) {
                    Text(agent.name)
                        .bold()
                    Text(agent.clientName)
                        .foregroundStyle(.secondary)
                }
                if let currentTask {
                    Text(currentTask.title)
                } else {
                    Text("No active task")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                StatusIndicator(title: agent.status.title, color: agent.status.color)
                Text(agent.lastActivity, format: .relative(presentation: .named))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
