import SwiftUI

/// Creates a task as the user (`POST /v1/tasks`). Agents then claim it.
struct NewTaskSheet: View {
    @Environment(ProjectSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""
    @State private var priority: HiveTask.Priority = .normal
    @State private var labelsText = ""
    @State private var dependsOn: Set<HiveTask.ID> = []
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        let candidates = (session.snapshot?.tasks ?? []).filter { $0.status != .done && $0.status != .cancelled }
        VStack(spacing: 0) {
            Form {
                TextField("Title", text: $title)
                TextField("Details", text: $details, prompt: Text("What should the agent deliver?"), axis: .vertical)
                    .lineLimit(3...8)
                Picker("Priority", selection: $priority) {
                    ForEach(HiveTask.Priority.allCases, id: \.self) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                TextField("Labels", text: $labelsText, prompt: Text("Comma-separated, optional"))
                if !candidates.isEmpty {
                    Section("Depends On") {
                        ForEach(candidates) { task in
                            DependencyToggleRow(task: task, selection: $dependsOn)
                        }
                    }
                    .hivePanelRows()
                }
            }
            .formStyle(.grouped)
            .hiveGroupedBackground()

            if let errorMessage {
                InlineErrorView(message: errorMessage)
                    .padding(.horizontal, HiveMetrics.spacingLoose)
            }
            HStack {
                Text("A task can't be claimed until the tasks it depends on are done.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Create Task") {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(trimmedTitle.isEmpty || isCreating)
            }
            .padding(HiveMetrics.spacingLoose)
        }
        .frame(width: HiveMetrics.formSheetWidth)
        .interactiveDismissDisabled(isCreating)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
        let draft = NewTaskDraft(
            title: trimmedTitle,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: priority,
            labels: NewTaskDraft.parseLabels(labelsText),
            dependsOn: Array(dependsOn).sorted()
        )
        isCreating = true
        errorMessage = nil
        Task {
            do {
                let task = try await session.createTask(draft)
                dismiss()
                session.showTask(task.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}
