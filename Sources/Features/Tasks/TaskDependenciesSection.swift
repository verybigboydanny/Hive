import SwiftUI

struct TaskDependenciesSection: View {
    let task: HiveTask
    let snapshot: ProjectSnapshot
    @Environment(ProjectSession.self) private var session

    var body: some View {
        if !task.dependencyIDs.isEmpty {
            Section("Depends On") {
                ForEach(task.dependencyIDs, id: \.self) { id in
                    let isWaiting = task.blockedBy.contains { $0.id == id }
                    Button {
                        session.showTask(id)
                    } label: {
                        HStack {
                            Text(snapshot.task(withID: id)?.title ?? id)
                            Spacer()
                            Text(isWaiting ? "Waiting" : "Done")
                                .foregroundStyle(isWaiting ? Color.orange : Color.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .hivePanelRows()
        }
    }
}
