import Foundation

/// Search and filters for the Tasks page.
struct TaskFilter: Equatable, Sendable {
    var searchText = ""
    /// Show only tasks of at least this priority. Nil shows every priority.
    var minimumPriority: HiveTask.Priority?
    var showsCancelled = false

    /// The board's columns, left to right.
    var columns: [HiveTask.Status] {
        var statuses: [HiveTask.Status] = [.backlog, .inProgress, .blocked, .review, .done]
        if showsCancelled { statuses.append(.cancelled) }
        return statuses
    }

    var isFiltering: Bool { !searchText.isEmpty || minimumPriority != nil }

    func matches(_ task: HiveTask) -> Bool {
        if task.status == .cancelled && !showsCancelled { return false }
        if let minimumPriority, task.priority < minimumPriority { return false }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let haystack = [task.title, task.details, task.id, task.ownerName ?? "", task.labels.joined(separator: " ")]
        return haystack.contains { $0.localizedStandardContains(query) }
    }

    /// Matching tasks: highest priority first, then most recently updated.
    func apply(to tasks: [HiveTask]) -> [HiveTask] {
        tasks.filter(matches).sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.updatedAt > $1.updatedAt
        }
    }

    func tasks(in status: HiveTask.Status, from tasks: [HiveTask]) -> [HiveTask] {
        apply(to: tasks).filter { $0.status == status }
    }
}
