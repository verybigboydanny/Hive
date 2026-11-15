import SwiftUI

struct FileTreeView: View {
    @Environment(ProjectSession.self) private var session

    var body: some View {
        @Bindable var files = session.files
        List(files.rows, selection: $files.selectionID) { row in
            FileTreeRow(row: row, rootURL: session.project?.rootURL)
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom) {
            if files.rootTruncated {
                Text("Only the first entries of large folders are shown.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(HiveMetrics.spacing)
            }
        }
    }
}
