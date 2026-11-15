import SwiftUI

struct MemoryListSection: View {
    let title: LocalizedStringKey
    let emptyMessage: LocalizedStringKey
    let entries: [MemoryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
            Text(title)
                .font(.headline)
            if entries.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    MemoryEntryRow(entry: entry)
                }
            }
        }
    }
}
