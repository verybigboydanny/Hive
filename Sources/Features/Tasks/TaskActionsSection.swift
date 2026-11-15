import SwiftUI

/// What the HTTP API lets the user do to a task: release a claim, or cancel it.
/// Claiming, progress and completion belong to agents.
struct TaskActionsSection: View {
    let task: HiveTask
    @Environment(ProjectSession.self) private var session
    @State private var confirmsRelease = false
    @State private var showsCancel = false

    private var canRelease: Bool {
        task.ownerName != nil && [.inProgress, .blocked, .review].contains(task.status)
    }

    private var canCancel: Bool {
        task.status != .done && task.status != .cancelled
    }

    var body: some View {
        Section("Actions") {
            Button("Release Claim…", systemImage: "arrow.uturn.backward") {
                confirmsRelease = true
            }
            .disabled(!canRelease)
            .confirmationDialog("Release this task?", isPresented: $confirmsRelease, titleVisibility: .visible) {
                Button("Release", role: .destructive) {
                    release()
                }
            } message: {
                Text("The agent loses its claim and the task becomes open for any agent to take.")
            }

            Button("Cancel Task…", systemImage: "xmark.circle", role: .destructive) {
                showsCancel = true
            }
            .disabled(!canCancel)
            .sheet(isPresented: $showsCancel) {
                CancelTaskSheet(task: task)
            }

            Text("Agents claim, update and complete tasks. From here you can create, release or cancel them.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .hivePanelRows()
    }

    private func release() {
        Task {
            do {
                try await session.releaseTask(task)
            } catch {
                session.errorMessage = error.localizedDescription
            }
        }
    }
}
