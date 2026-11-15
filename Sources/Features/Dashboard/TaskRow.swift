import SwiftUI

struct TaskRow: View {
    let task: HiveTask
    let assignee: Agent?

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(task.title)
                if task.priority >= .high {
                    Pill(task.priority.title, tint: task.priority.tint)
                }
                Spacer()
                Label(task.status.title, systemImage: task.status.symbol)
                    .foregroundStyle(task.status.tint)
            }
            HStack {
                if let assignee {
                    Text(assignee.name)
                } else {
                    Text("Unassigned")
                }
                if task.status == .inProgress, let progress = task.progress {
                    ProgressView(value: progress)
                        .frame(maxWidth: HiveMetrics.taskProgressWidth)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
