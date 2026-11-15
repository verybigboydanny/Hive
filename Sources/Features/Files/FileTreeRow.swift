import SwiftUI
import AppKit

struct FileTreeRow: View {
    let row: FileRow
    let rootURL: URL?

    var body: some View {
        HStack(spacing: HiveMetrics.spacingTight) {
            Image(systemName: "chevron.right")
                .rotationEffect(row.isExpanded ? .degrees(90) : .zero)
                .foregroundStyle(.secondary)
                .opacity(row.entry.kind == .directory ? 1 : 0)
                .frame(width: HiveMetrics.treeChevronWidth)
                .accessibilityHidden(true)
            Label(row.entry.name, systemImage: row.entry.kind.symbol)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if row.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.leading, Double(row.depth) * HiveMetrics.treeIndent)
        .contentShape(.rect)
        .contextMenu {
            Button("Copy Path") {
                copyPath()
            }
            if rootURL != nil {
                Button("Reveal in Finder") {
                    revealInFinder()
                }
            }
        }
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.entry.path, forType: .string)
    }

    private func revealInFinder() {
        guard let rootURL else { return }
        let url = rootURL.appending(path: row.entry.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
