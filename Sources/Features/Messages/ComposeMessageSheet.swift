import SwiftUI

/// Sends a message as the user. Agents receive it in their inbox (`message_inbox`).
struct ComposeMessageSheet: View {
    @Environment(ProjectSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var recipientID: String
    @State private var subject: String
    @State private var taskID: String
    @State private var kind: HiveMessage.Kind = .message
    @State private var messageBody = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    /// `recipientID` is an agent id, or "all". `taskID` is "" for no related task.
    init(recipientID: String = "all", taskID: String = "", subject: String = "") {
        _recipientID = State(initialValue: recipientID)
        _taskID = State(initialValue: taskID)
        _subject = State(initialValue: subject)
    }

    var body: some View {
        let agents = session.snapshot?.agents ?? []
        let tasks = (session.snapshot?.tasks ?? []).filter { $0.status != .done && $0.status != .cancelled }
        VStack(spacing: 0) {
            Form {
                Picker("To", selection: $recipientID) {
                    Text("Everyone").tag("all")
                    ForEach(agents) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }
                Picker("Type", selection: $kind) {
                    ForEach(HiveMessage.Kind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                Picker("About Task", selection: $taskID) {
                    Text("None").tag("")
                    ForEach(tasks) { task in
                        Text(task.title).tag(task.id)
                    }
                }
                TextField("Subject", text: $subject, prompt: Text("Optional"))
                TextField("Message", text: $messageBody, axis: .vertical)
                    .lineLimit(HiveMetrics.composerMinHeightLines...10)
            }
            .formStyle(.grouped)
            .hiveGroupedBackground()

            if let errorMessage {
                InlineErrorView(message: errorMessage)
                    .padding(.horizontal, HiveMetrics.spacingLoose)
            }
            HStack {
                Text("Sent as you. Agents read it in their inbox.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Send") {
                    send()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(trimmedBody.isEmpty || isSending)
            }
            .padding(HiveMetrics.spacingLoose)
        }
        .frame(width: HiveMetrics.formSheetWidth)
        .interactiveDismissDisabled(isSending)
    }

    private var trimmedBody: String {
        messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = NewMessageDraft(
            to: recipientID,
            body: trimmedBody,
            subject: trimmedSubject.isEmpty ? nil : trimmedSubject,
            kind: kind,
            taskID: taskID.isEmpty ? nil : taskID
        )
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await session.messages.send(draft)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}
