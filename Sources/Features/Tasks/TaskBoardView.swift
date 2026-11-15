import SwiftUI

struct TaskBoardView: View {
    let tasks: [HiveTask]
    let filter: TaskFilter
    @Binding var selection: HiveTask.ID?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: HiveMetrics.spacingLoose) {
                ForEach(filter.columns, id: \.self) { status in
                    TaskColumnView(status: status, tasks: filter.tasks(in: status, from: tasks), selection: $selection)
                }
            }
            .padding(HiveMetrics.spacingLoose)
        }
        .overlay {
            if filter.isFiltering && filter.apply(to: tasks).isEmpty {
                ContentUnavailableView.search
            }
        }
    }
}
