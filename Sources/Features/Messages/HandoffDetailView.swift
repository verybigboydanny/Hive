import SwiftUI

struct HandoffDetailView: View {
    let handoff: Handoff
    @Environment(ProjectSession.self) private var session

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
                    Text(handoff.taskTitle)
                        .font(.title2.bold())
                    HStack {
                        Pill(handoff.status.title, tint: handoff.status.tint)
                        Text("\(handoff.fromAgentName) → \(handoff.toAgentName ?? "any agent")")
                            .foregroundStyle(.secondary)
                    }
                    if !handoff.summary.isEmpty {
                        Text(handoff.summary)
                    }
                }
                if let taskID = handoff.taskID {
                    Button("Show Task", systemImage: "checklist") {
                        session.showTask(taskID)
                    }
                }
            }
            .hivePanelRows()

            HandoffTextSection(title: "Completed", text: handoff.completedWork)
            HandoffTextSection(title: "Remaining", text: handoff.remainingWork)
            HandoffTextSection(title: "Next Action", text: handoff.nextAction)
            HandoffTextSection(title: "Context", text: handoff.context)

            if !handoff.filesModified.isEmpty {
                Section("Files Changed") {
                    ForEach(handoff.filesModified, id: \.self) { path in
                        Text(path)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .hivePanelRows()
            }

            Section("History") {
                LabeledContent("Created") {
                    Text(handoff.createdAt, format: .dateTime.month().day().year().hour().minute())
                }
                if let name = handoff.acceptedByName {
                    LabeledContent("Accepted By", value: name)
                }
                if let accepted = handoff.acceptedAt {
                    LabeledContent("Accepted") {
                        Text(accepted, format: .dateTime.month().day().year().hour().minute())
                    }
                }
                LabeledContent("Handoff ID") {
                    HStack {
                        Text(handoff.id)
                            .textSelection(.enabled)
                        CopyButton(text: handoff.id)
                    }
                }
            }
            .hivePanelRows()

            Section {
                ReadOnlyNotice(message: "Agents accept or cancel handoffs themselves. The Hive API has no endpoint for doing it from the app.")
            }
            .hivePanelRows()
        }
        .formStyle(.grouped)
        .hiveGroupedBackground()
    }
}
