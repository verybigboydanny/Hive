import SwiftUI

struct RulesContent: View {
    let context: ProjectContext

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacingLoose) {
            VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
                Text("Built-in working rules")
                    .font(.headline)
                Text("Every agent receives these, in every project.")
                    .foregroundStyle(.secondary)
                Text(verbatim: context.protocolRules)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(HiveMetrics.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: .rect(cornerRadius: HiveMetrics.cardRadius))
            }

            MemoryListSection(
                title: "Project rules",
                emptyMessage: "No project rules yet. Agents (or you, through Claude) add them with `memory_update`.",
                entries: context.projectRules
            )

            DecisionListSection(decisions: context.decisions)

            MemoryListSection(
                title: "Shared memory",
                emptyMessage: "Nothing in shared memory yet.",
                entries: context.memory.filter { $0.category != "rules" }
            )
        }
    }
}
