import SwiftUI

struct HandoffRow: View {
    let handoff: Handoff

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
            HStack {
                Text(handoff.taskTitle)
                    .bold()
                    .lineLimit(1)
                Spacer()
                Pill(handoff.status.title, tint: handoff.status.tint)
            }
            Text("\(handoff.fromAgentName) → \(handoff.toAgentName ?? "any agent")")
                .foregroundStyle(.secondary)
            if !handoff.summary.isEmpty {
                Text(handoff.summary)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
            Text(handoff.createdAt, format: .relative(presentation: .named))
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }
}
