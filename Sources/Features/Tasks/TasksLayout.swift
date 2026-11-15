import Foundation

enum TasksLayout: String, CaseIterable, Identifiable {
    case board, list

    var id: String { rawValue }
}
