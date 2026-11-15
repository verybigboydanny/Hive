import SwiftUI

/// A loaded file: header, numbered lines, and a "Load More" footer for long files.
struct FileContentView: View {
    @Environment(ProjectSession.self) private var session

    var body: some View {
        let files = session.files
        VStack(spacing: 0) {
            FilePreviewHeader()
            Divider()
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(files.numberedLines) { line in
                        FileLineView(line: line)
                    }
                }
                .textSelection(.enabled)
                .padding(HiveMetrics.spacing)
            }
            .font(.system(.body, design: .monospaced))
            if let info = files.fileInfo, info.nextStartLine != nil {
                Divider()
                FileLoadMoreBar(shown: files.lines.count, total: info.totalLines, isLoading: files.isLoadingMore)
            }
        }
    }
}
