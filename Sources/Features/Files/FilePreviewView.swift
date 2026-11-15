import SwiftUI

struct FilePreviewView: View {
    @Environment(ProjectSession.self) private var session

    var body: some View {
        switch session.files.contentState {
        case .none:
            ContentUnavailableView(
                "Select a File",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Choose a file to preview it. Files are read-only here: agents change them through Hive.")
            )
        case .loading:
            ProgressView()
        case .unavailable(let reason):
            ContentUnavailableView("No Preview Available", systemImage: "doc", description: Text(reason))
        case .failed(let message):
            ContentUnavailableView("Couldn't Open File", systemImage: "exclamationmark.triangle", description: Text(message))
        case .loaded:
            FileContentView()
        }
    }
}
