import SwiftUI

struct TaskColumnView: View {
    let status: HiveTask.Status
    let tasks: [HiveTask]
    @Binding var selection: HiveTask.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
            HStack {
                Label(status.title, systemImage: status.symbol)
                    .bold()
                    .foregroundStyle(status.tint)
                Spacer()
                Text(tasks.count, format: .number)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: HiveMetrics.spacing) {
                    ForEach(tasks) { task in
                        Button {
                            selection = task.id
                        } label: {
                            TaskCardView(task: task, isSelected: selection == task.id)
                        }
                        .buttonStyle(.plain)
                        .transition(.asymmetric(
                            insertion: reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)),
                            removal: .opacity
                        ))
                    }
                    if tasks.isEmpty {
                        Text("No tasks")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(HiveMetrics.spacingLoose)
                    }
                }
            }
        }
        .frame(width: HiveMetrics.boardColumnWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .snappy(duration: 0.24), value: tasks.map(\.id))
    }
}
