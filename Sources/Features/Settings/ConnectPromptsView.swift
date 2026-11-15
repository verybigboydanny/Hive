import SwiftUI

/// Steps 4 and 5: prompts to paste into Claude.
struct ConnectPromptsView: View {
    let setup: MCPSetup
    @Binding var agentName: String
    @Binding var agentRole: String
    @Binding var taskID: String
    @Binding var handoffRecipient: String

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacingLoose) {
            ConnectStep(number: 4, title: "Introduce Claude to the project") {
                VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
                    Text("The Set Up Agent page writes a complete instruction for the open project. This shorter prompt is for manual use.")
                    Form {
                        TextField("Agent name", text: $agentName, prompt: Text("Claude"))
                        TextField("Role", text: $agentRole, prompt: Text("Optional, for example Backend"))
                    }
                    .formStyle(.grouped)
                    .hiveGroupedBackground()
                    PromptCard(
                        title: "Register and get oriented",
                        detail: "Claude registers, shows you its agent ID and resume token, and summarises the project. Save both values: the token is shown only once.",
                        prompt: setup.onboardPrompt
                    )
                    PromptCard(
                        title: "Reconnect later",
                        detail: "Use this in a new chat to continue as the same agent, with the values you saved.",
                        prompt: setup.reconnectPrompt
                    )
                }
            }

            ConnectStep(number: 5, title: "Put Claude to work") {
                VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
                    Form {
                        TextField("Task ID", text: $taskID, prompt: Text("Optional, from the Tasks page"))
                        TextField("Hand off to", text: $handoffRecipient, prompt: Text("Optional agent name"))
                    }
                    .formStyle(.grouped)
                    .hiveGroupedBackground()
                    PromptCard(
                        title: "Fetch the latest context",
                        detail: "Claude reads the rules, its tasks, its inbox and pending handoffs, then reports back.",
                        prompt: setup.contextPrompt
                    )
                    PromptCard(
                        title: "Start a claimed task",
                        detail: "Claude claims the task, works on it with safe file edits and progress updates, and completes it.",
                        prompt: setup.startTaskPrompt
                    )
                    PromptCard(
                        title: "Hand off to another agent",
                        detail: "Claude saves a checkpoint and writes a handoff so another agent can continue.",
                        prompt: setup.handoffPrompt
                    )
                    Text("Hive also offers the MCP prompts `hive_onboard`, `hive_resume` and `hive_handoff`, which you can pick from Claude's prompt menu.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
