import SwiftUI

/// The thing an event acted on. Tasks and agents link to their pages; anything else is plain text.
struct ActivityTargetLink: View {
    let targetType: String
    let targetID: String
    @Environment(ProjectSession.self) private var session

    var body: some View {
        switch destination {
        case .task:
            Button(label) {
                session.showTask(targetID)
            }
            .buttonStyle(.link)
        case .agent:
            Button(label) {
                session.showAgent(targetID)
            }
            .buttonStyle(.link)
        case .none:
            Text(targetID)
                .textSelection(.enabled)
        }
    }

    private enum Destination {
        case task, agent, none
    }

    private var destination: Destination {
        guard let snapshot = session.snapshot else { return .none }
        if targetType == "task", snapshot.task(withID: targetID) != nil { return .task }
        if targetType == "agent", snapshot.agents.contains(where: { $0.id == targetID }) { return .agent }
        return .none
    }

    private var label: String {
        guard let snapshot = session.snapshot else { return targetID }
        switch destination {
        case .task: return snapshot.task(withID: targetID)?.title ?? targetID
        case .agent: return snapshot.agents.first(where: { $0.id == targetID })?.name ?? targetID
        case .none: return targetID
        }
    }
}
