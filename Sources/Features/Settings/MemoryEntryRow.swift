import SwiftUI

struct MemoryEntryRow: View {
    let entry: MemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
            Text(entry.key)
                .bold()
            Text(entry.value)
                .textSelection(.enabled)
            Text(footer)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(HiveMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: HiveMetrics.cardRadius))
        .accessibilityElement(children: .combine)
    }

    private var footer: String {
        var parts = ["Version \(entry.version)"]
        if let name = entry.updatedByName { parts.append("updated by \(name)") }
        parts.append(entry.updatedAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }
}
