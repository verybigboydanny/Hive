import SwiftUI

struct TaskInspector: View {
    let taskID: HiveTask.ID?
    @Environment(ProjectSession.self) private var session

    var body: some View {
        if let snapshot = session.snapshot, let task = snapshot.task(withID: taskID) {
            TaskDetailView(task: task, snapshot: snapshot)
        } else {
            ContentUnavailableView("No Task Selected", systemImage: "checklist")
        }
    }
}
