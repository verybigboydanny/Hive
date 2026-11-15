import SwiftUI

struct FilePreviewHeader: View {
    @Environment(ProjectSession.self) private var session

    var body: some View {
        if let path = session.files.selectedPath, let info = session.files.fileInfo {
            VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
                Text(path)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: HiveMetrics.spacingLoose) {
                    Text(Int64(info.size), format: .byteCount(style: .file))
                    Text("^[\(info.totalLines) line](inflect: true)")
                    Label("Read-only", systemImage: "lock")
                    Spacer()
                    CopyButton(text: info.sha256, title: "Copy SHA-256")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(HiveMetrics.spacing)
        }
    }
}
