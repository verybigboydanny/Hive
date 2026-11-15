import SwiftUI

struct TrashRow: View {
    let item: TrashItem
    let isRestoring: Bool
    let onRestore: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
                Text(item.originalPath)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let reason = item.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isRestoring {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Restore") {
                onRestore()
            }
            .disabled(isRestoring)
        }
    }

    private var detail: String {
        var parts: [String] = []
        parts.append(item.kind == "dir" || item.kind == "directory" ? "Folder (\(item.entries) items)" : "File")
        if let by = item.deletedBy { parts.append("deleted by \(by)") }
        parts.append(item.deletedAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }
}
