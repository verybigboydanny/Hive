import SwiftUI

struct TaskFilterMenu: View {
    @Binding var filter: TaskFilter

    var body: some View {
        Menu("Filter", systemImage: "line.3.horizontal.decrease.circle") {
            Picker("Priority", selection: $filter.minimumPriority) {
                Text("Any Priority").tag(HiveTask.Priority?.none)
                ForEach(HiveTask.Priority.allCases, id: \.self) { priority in
                    Text(priority.title).tag(Optional(priority))
                }
            }
            Toggle("Show Cancelled", isOn: $filter.showsCancelled)
        }
        .help("Filter tasks")
    }
}
