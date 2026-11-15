import SwiftUI

struct FilesContent: View {
    @Environment(ProjectSession.self) private var session

    var body: some View {
        let files = session.files
        switch files.rootPhase {
        case .idle, .loading:
            ProgressView("Loading files…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load Files", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await session.files.loadRoot() }
                }
            }
        case .loaded:
            if files.rows.isEmpty {
                ContentUnavailableView("This Project Is Empty", systemImage: "folder", description: Text("Files agents create will appear here."))
            } else {
                HSplitView {
                    FileTreeView()
                        .frame(minWidth: HiveMetrics.treeMinWidth, idealWidth: HiveMetrics.treeIdealWidth, maxWidth: HiveMetrics.treeMaxWidth)
                    FilePreviewView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
