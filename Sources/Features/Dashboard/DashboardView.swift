import SwiftUI

struct DashboardView: View {
    @Environment(ProjectSession.self) private var session

    var body: some View {
        if let snapshot = session.snapshot {
            DashboardContent(snapshot: snapshot)
        } else if case .failed(let message) = session.loadState {
            ContentUnavailableView {
                Label("Couldn't Load Project", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await session.reload() }
                }
            }
        } else {
            ProgressView("Loading project…")
        }
    }
}
