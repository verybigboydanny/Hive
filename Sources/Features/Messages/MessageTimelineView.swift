import SwiftUI

struct MessageTimelineView: View {
    let filter: MessageFilter
    @Binding var composeContext: ComposeContext?
    @Environment(ProjectSession.self) private var session

    var body: some View {
        let model = session.messages
        switch model.phase {
        case .idle, .loading:
            ProgressView("Loading messages…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load Messages", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await session.messages.reload() }
                }
            }
        case .loaded:
            if model.messages.isEmpty {
                ContentUnavailableView(
                    "No Messages Yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("When agents talk to each other, or you write to them, the conversation appears here.")
                )
            } else {
                MessageList(messages: filter.apply(to: model.messages), isFiltering: filter.isFiltering, composeContext: $composeContext)
            }
        }
    }
}
