import Foundation

/// What the user types into the New Task sheet. Sent with `POST /v1/tasks` (attributed to the user).
struct NewTaskDraft: Sendable {
    var title: String
    var details: String = ""
    var priority: HiveTask.Priority = .normal
    var labels: [String] = []
    var dependsOn: [String] = []
}

extension NewTaskDraft {
    /// Splits "a, b ,, a" into ["a", "b"]: trimmed, non-empty, no repeats, original order.
    static func parseLabels(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
