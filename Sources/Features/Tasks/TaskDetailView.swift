import SwiftUI

struct TaskDetailView: View {
    let task: HiveTask
    let snapshot: ProjectSnapshot
    @Environment(ProjectSession.self) private var session

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
                    Text(task.title)
                        .font(.title2.bold())
                    HStack {
                        Label(task.status.title, systemImage: task.status.symbol)
                            .foregroundStyle(task.status.tint)
                        Pill(task.priority.title, tint: task.priority.tint)
                    }
                }
                if !task.details.isEmpty {
                    Text(task.details)
                        .textSelection(.enabled)
                }
            }
            .hivePanelRows()

            if hasProgress {
                Section("Progress") {
                    if let note = task.progressNote, !note.isEmpty {
                        LabeledContent("Latest Note", value: note)
                    }
                    if let result = task.resultSummary, !result.isEmpty {
                        LabeledContent("Result", value: result)
                    }
                    if let reason = task.cancelReason, !reason.isEmpty {
                        LabeledContent("Cancelled Because", value: reason)
                    }
                }
                .hivePanelRows()
            }

            Section("Assignment") {
                TaskAssignmentRows(task: task)
            }
            .hivePanelRows()

            TaskDependenciesSection(task: task, snapshot: snapshot)

            Section("Details") {
                if !task.labels.isEmpty {
                    LabeledContent("Labels", value: task.labels.joined(separator: ", "))
                }
                if let creator = task.createdBy {
                    LabeledContent("Created By", value: creator == "user" ? "You" : creator)
                }
                if let created = task.createdAt {
                    LabeledContent("Created") {
                        Text(created, format: .dateTime.month().day().year().hour().minute())
                    }
                }
                LabeledContent("Updated") {
                    Text(task.updatedAt, format: .relative(presentation: .named))
                }
                LabeledContent("Version", value: String(task.version))
                LabeledContent("Task ID") {
                    HStack {
                        Text(task.id)
                            .textSelection(.enabled)
                        CopyButton(text: task.id)
                    }
                }
            }
            .hivePanelRows()

            TaskActionsSection(task: task)
        }
        .formStyle(.grouped)
        .hiveGroupedBackground()
    }

    private var hasProgress: Bool {
        [task.progressNote, task.resultSummary, task.cancelReason].contains { !($0 ?? "").isEmpty }
    }
}
