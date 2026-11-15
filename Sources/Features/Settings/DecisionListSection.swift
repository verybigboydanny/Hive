import SwiftUI

struct DecisionListSection: View {
    let decisions: [DecisionRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
            Text("Decisions")
                .font(.headline)
            if decisions.isEmpty {
                Text("No decisions recorded yet. Agents record them with `decision_record`.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(decisions) { decision in
                    DecisionRow(decision: decision)
                }
            }
        }
    }
}
