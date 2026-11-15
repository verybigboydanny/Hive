import SwiftUI

struct TaskListView: View {
    let tasks: [HiveTask]
    @Binding var selection: HiveTask.ID?

    @State private var sortOrder = [KeyPathComparator(\HiveTask.priority, order: .reverse)]

    var body: some View {
        Table(tasks.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Task", value: \.title) { task in
                Text(task.title)
            }
            TableColumn("Status") { task in
                Label(task.status.title, systemImage: task.status.symbol)
                    .foregroundStyle(task.status.tint)
            }
            .width(min: 100, ideal: 120)
            TableColumn("Priority", value: \.priority) { task in
                Text(task.priority.title)
                    .foregroundStyle(task.priority.tint)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Owner") { task in
                Text(task.ownerName ?? "—")
                    .foregroundStyle(.secondary)
            }
            TableColumn("Updated", value: \.updatedAt) { task in
                Text(task.updatedAt, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)
        }
        .hiveTableStyle()
        .overlay {
            if tasks.isEmpty {
                ContentUnavailableView.search
            }
        }
    }
}
