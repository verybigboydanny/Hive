import SwiftUI

struct CancelTaskSheet: View {
    let task: HiveTask
    @Environment(ProjectSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("Cancel “\(task.title)”?")
                        .font(.headline)
                    Text("The task is kept for the record but no agent can work on it any more.")
                        .foregroundStyle(.secondary)
                }
                .hivePanelRows()
                TextField("Reason", text: $reason, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(2...5)
            }
            .formStyle(.grouped)
            .hiveGroupedBackground()
            if let errorMessage {
                InlineErrorView(message: errorMessage)
                    .padding(.horizontal, HiveMetrics.spacingLoose)
            }
            HStack {
                Spacer()
                Button("Keep Task") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Cancel Task", role: .destructive) {
                    cancel()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)
            }
            .padding(HiveMetrics.spacingLoose)
        }
        .frame(width: HiveMetrics.sheetWidth)
        .interactiveDismissDisabled(isWorking)
    }

    private func cancel() {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await session.cancelTask(task, reason: trimmed.isEmpty ? "Cancelled from the Hive app" : trimmed)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
