import SwiftUI

/// Everything agents and the user have said to each other, plus the handoffs between agents.
struct MessagesView: View {
    @Environment(ProjectSession.self) private var session
    @State private var tab: MessagesTab = .messages
    @State private var filter = MessageFilter()
    @State private var composeContext: ComposeContext?

    var body: some View {
        let pending = session.snapshot?.handoffs.count ?? 0
        Group {
            switch tab {
            case .messages:
                MessageTimelineView(filter: filter, composeContext: $composeContext)
            case .handoffs:
                HandoffsView()
            }
        }
        .searchable(text: $filter.searchText, prompt: "Search messages")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $tab) {
                    Text("Messages").tag(MessagesTab.messages)
                    Text(pending > 0 ? "Handoffs (\(pending))" : "Handoffs").tag(MessagesTab.handoffs)
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                MessageFilterMenu(filter: $filter)
                    .disabled(tab != .messages)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New Message", systemImage: "square.and.pencil") {
                    composeContext = ComposeContext()
                }
                .help("Send a message to an agent or to everyone")
            }
        }
        .sheet(item: $composeContext) { context in
            ComposeMessageSheet(recipientID: context.recipientID, taskID: context.taskID, subject: context.subject)
        }
        .task {
            await session.messages.loadIfNeeded()
            await session.handoffs.loadIfNeeded()
        }
    }
}
