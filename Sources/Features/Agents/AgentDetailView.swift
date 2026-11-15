import SwiftUI

struct AgentDetailView: View {
    let agent: Agent
    let snapshot: ProjectSnapshot
    @Binding var composeRecipient: Agent?
    @Environment(ProjectSession.self) private var session
    @State private var showsRemoveConfirmation = false
    @State private var isRemoving = false
    @State private var removeError: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
                    Text(agent.name)
                        .font(.title2.bold())
                    Text([agent.clientName, agent.model].compactMap { $0 }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    StatusIndicator(title: agent.status.title, color: agent.status.color)
                }
                Button("Send Message…", systemImage: "bubble.left") {
                    composeRecipient = agent
                }
            }
            .hivePanelRows()

            Section("Profile") {
                if let role = agent.role, !role.isEmpty {
                    LabeledContent("Role", value: role)
                }
                if let message = agent.statusMessage, !message.isEmpty {
                    LabeledContent("Status Message", value: message)
                }
                if !agent.capabilities.isEmpty {
                    LabeledContent("Capabilities", value: agent.capabilities.joined(separator: ", "))
                }
                if let presence = agent.presence {
                    LabeledContent("Presence", value: presence.capitalized)
                }
                LabeledContent("Open Sessions", value: String(agent.openSessions))
                LabeledContent("Last Active") {
                    Text(agent.lastActivity, format: .relative(presentation: .named))
                }
                if let registered = agent.registeredAt {
                    LabeledContent("Registered") {
                        Text(registered, format: .dateTime.month().day().year().hour().minute())
                    }
                }
            }
            .hivePanelRows()

            Section("Tasks") {
                let tasks = agent.activeTaskIDs.compactMap { snapshot.task(withID: $0) }
                if tasks.isEmpty {
                    Text("No active tasks")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tasks) { task in
                        Button {
                            session.showTask(task.id)
                        } label: {
                            Label(task.title, systemImage: task.status.symbol)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .hivePanelRows()

            Section("Identifier") {
                LabeledContent("Agent ID") {
                    HStack {
                        Text(agent.id)
                            .textSelection(.enabled)
                        CopyButton(text: agent.id)
                    }
                }
            }
            .hivePanelRows()

            Section {
                if let errorMessage = removeError {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                Button(role: .destructive) {
                    showsRemoveConfirmation = true
                } label: {
                    if isRemoving {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Removing…")
                        }
                    } else {
                        Label("Remove Agent", systemImage: "person.badge.minus")
                    }
                }
                .disabled(isRemoving)
                .confirmationDialog(
                    "Remove \(agent.name)?",
                    isPresented: $showsRemoveConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Remove Agent", role: .destructive) {
                        Task { await remove() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("\(agent.name) will be signed out and can no longer reconnect. Any tasks it holds will return to the backlog. This cannot be undone.")
                }
            }
            .hivePanelRows()
        }
        .formStyle(.grouped)
        .hiveGroupedBackground()
    }

    private func remove() async {
        isRemoving = true
        removeError = nil
        do {
            try await session.removeAgent(agent)
        } catch {
            removeError = error.localizedDescription
        }
        isRemoving = false
    }
}
