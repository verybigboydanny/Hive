import Foundation

/// The starting values for a message the user is about to write (empty for a new message, filled for a reply).
struct ComposeContext: Identifiable {
    let id = UUID()
    var recipientID = "all"
    var taskID = ""
    var subject = ""

    /// A reply addressed to whoever sent `message`, about the same task.
    static func reply(to message: HiveMessage) -> ComposeContext {
        var context = ComposeContext()
        if let sender = message.fromID, !message.isFromUser { context.recipientID = sender }
        context.taskID = message.taskID ?? ""
        if let subject = message.subject, !subject.isEmpty {
            context.subject = subject.hasPrefix("Re: ") ? subject : "Re: " + subject
        }
        return context
    }
}
