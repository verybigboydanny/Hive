import SwiftUI

/// A short, copyable guide available before or after opening a Hive project.
struct HowToUseHiveView: View {
    @Environment(ProjectSession.self) private var session
    private let prompts = MCPSetup(backendSourcePath: "", workspacePath: "")

    var body: some View {
        SettingsPage(
            title: "How to use Hive",
            subtitle: "Connect Claude, review the shared context, then approve and follow its work."
        ) {
            GuideStep(number: 1, title: "Connect an agent") {
                Text("Open Hive Settings → Apps & MCP and add Hive to your AI app once; the connection works for every project. Quit and reopen the app. Then open Set Up Agent, name the agent and copy the instruction Hive writes for the open project.")
                Button {
                    session.selection = .setUpAgent
                } label: {
                    Label("Open Set Up Agent", systemImage: "person.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }

            GuideStep(number: 2, title: "Review context and tasks") {
                Text("Claude can read the project rules, its assignments, inbox, and pending handoffs. Review its recommendation before assigning work.")
                PromptCard(
                    title: "Fetch the latest context",
                    detail: "A quick status check that leaves task and handoff decisions with you.",
                    prompt: prompts.contextPrompt
                )
            }

            GuideStep(number: 3, title: "Approve and track work") {
                Text("Choose a task in Hive, confirm that Claude may claim it, then follow progress in Tasks and Activity. Hive keeps task ownership, checkpoints, and file changes visible.")
                PromptCard(
                    title: "Start a task after approval",
                    detail: "Claude checks that the task is available and waits for your approval before claiming it.",
                    prompt: prompts.startTaskPrompt
                )
                PromptCard(
                    title: "Hand work to another agent",
                    detail: "Claude saves a checkpoint and records what the next agent needs.",
                    prompt: prompts.handoffPrompt
                )
            }
        }
    }
}

private struct GuideStep<Content: View>: View {
    let number: Int
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
            Label {
                Text(title).font(.headline)
            } icon: {
                Text(number.formatted())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor, in: Circle())
            }
            VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
                content
            }
            .padding(.leading, 32)
        }
    }
}
