import SwiftUI

struct FileLoadMoreBar: View {
    @Environment(ProjectSession.self) private var session
    let shown: Int
    let total: Int
    let isLoading: Bool

    var body: some View {
        HStack {
            Text("Showing \(shown) of \(total) lines")
                .foregroundStyle(.secondary)
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Load More") {
                Task { await session.files.loadMoreLines() }
            }
            .disabled(isLoading)
        }
        .padding(HiveMetrics.spacing)
    }
}
