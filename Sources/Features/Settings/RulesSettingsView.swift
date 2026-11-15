import SwiftUI

/// The rules, decisions and shared memory agents work from. Read-only: the API has no write endpoints for them.
struct RulesSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage(
            title: "Rules",
            subtitle: "What every connected agent is told before it starts working on this project."
        ) {
            ReadOnlyNotice(message: "Hive's API has no endpoint for changing rules, so they can't be edited here. Agents add and change project rules with the `memory_update` tool, using the category `rules`. You can ask Claude to do it with the prompt at the bottom of this page.")

            if let message = model.contextError {
                InlineErrorView(message: message)
            }

            if let context = model.context {
                RulesContent(context: context)
            } else if model.contextError == nil {
                NoProjectNotice(model: model)
            }

            VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
                Text("Ask Claude to add a rule")
                    .font(.headline)
                CodeBlock(text: MCPSetup.addRulePrompt, wrapsLines: true)
            }
        }
    }
}
