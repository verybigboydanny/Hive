import SwiftUI

struct DecisionRow: View {
    let decision: DecisionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
            Text(decision.title)
                .bold()
            Text(decision.decision)
                .textSelection(.enabled)
            if let rationale = decision.rationale, !rationale.isEmpty {
                Text(rationale)
                    .foregroundStyle(.secondary)
            }
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
        var parts: [String] = []
        if let name = decision.decidedByName { parts.append("Decided by \(name)") }
        parts.append(decision.createdAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }
}
