import SwiftUI
import AppKit

struct MessageRowView: View {
    let message: HiveMessage
    let onReply: @MainActor () -> Void
    @Environment(ProjectSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
            HStack(alignment: .firstTextBaseline, spacing: HiveMetrics.spacing) {
                Text(message.fromName)
                    .bold()
                Text("to \(message.toName ?? "everyone")")
                    .foregroundStyle(.secondary)
                if message.kind != .message {
                    Pill(message.kind.title, tint: message.kind.tint)
                }
                Spacer()
                Text(message.createdAt, format: .dateTime.hour().minute())
                    .foregroundStyle(.secondary)
            }
            if let subject = message.subject, !subject.isEmpty {
                Text(subject)
                    .bold()
            }
            Text(message.body)
                .textSelection(.enabled)
            if let taskID = message.taskID, let task = session.snapshot?.task(withID: taskID) {
                Button {
                    session.showTask(taskID)
                } label: {
                    Label(task.title, systemImage: "checklist")
                }
                .buttonStyle(.link)
            }
        }
        .padding(.horizontal, HiveMetrics.spacingLoose)
        .padding(.vertical, HiveMetrics.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.isFromUser ? Color.accentColor.opacity(0.08) : Color.clear)
        .contextMenu {
            Button("Reply…") {
                onReply()
            }
            Button("Copy Message") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.body, forType: .string)
            }
        }
    }
}
