import SwiftUI

/// Set Up Agent: describe an agent once and Hive writes the complete onboarding instruction for it.
///
/// The target project is always the project open in this window. It is shown, never typed, and it travels to the
/// backend as the explicit `project_id` that the AI client then passes to `agent_register`, so the agent cannot end
/// up in a previously used project.
struct SetUpAgentView: View {
    @Environment(ProjectSession.self) private var session

    @State private var name = ""
    @State private var role = ""
    @State private var capabilitiesText = ""
    @State private var client: AgentClient = .claude
    @State private var result: AgentOnboarding?
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var capabilities: [String] {
        capabilitiesText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { session.project != nil && !trimmedName.isEmpty && !isWorking }

    /// Changes whenever anything the instruction depends on changes, so a stale instruction is never left on screen.
    private var inputSignature: String {
        [session.project?.projectID ?? "", trimmedName, role, capabilitiesText, client.rawValue].joined(separator: "\u{1F}")
    }

    var body: some View {
        SettingsPage(
            title: "Set Up Agent",
            subtitle: "Describe the agent. Hive writes an instruction that registers it in this project and nowhere else."
        ) {
            if let project = session.project {
                Form {
                    LabeledContent("Project") { Text(project.name) }
                    LabeledContent("Project ID") {
                        Text(project.projectID ?? "Not available")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .formStyle(.grouped)
                .hiveGroupedBackground()
            }

            Form {
                TextField("Agent name", text: $name, prompt: Text("Backend Claude"))
                TextField("Role", text: $role, prompt: Text("What this agent is responsible for"))
                TextField("Capabilities", text: $capabilitiesText, prompt: Text("Optional, comma separated: python, sql"))
                Picker("AI client", selection: $client) {
                    ForEach(AgentClient.allCases) { Text($0.title).tag($0) }
                }
            }
            .formStyle(.grouped)
            .hiveGroupedBackground()

            VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
                Button {
                    Task { await generate() }
                } label: {
                    Label(isWorking ? "Setting Up…" : "Set Up Agent", systemImage: "person.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)

                Text("Before you start: connect the Hive MCP server in your AI client (Settings → Apps & MCP), then restart that client once.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                InlineErrorView(message: errorMessage)
            }

            if let result {
                VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
                    ForEach(result.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Label("Instruction for \(result.projectName)", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("Paste this into a new chat in \(client.title). The agent registers under this project, shows you its agent ID and secret resume token, then reports its context and waits for your go-ahead.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    CodeBlock(text: result.prompt, wrapsLines: true)
                    CopyButton(text: result.prompt, title: "Copy Instruction")
                }
            }
        }
        .onChange(of: inputSignature) {
            result = nil
            errorMessage = nil
        }
    }

    private func generate() async {
        guard let project = session.project else { return }
        isWorking = true
        errorMessage = nil
        result = nil
        defer { isWorking = false }
        do {
            let request = AgentSetupRequest(name: trimmedName, role: role.trimmingCharacters(in: .whitespacesAndNewlines),
                                            capabilities: capabilities, client: client)
            result = try await session.dataSource.onboarding(for: project, setup: request)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
