import SwiftUI

extension HiveTask.Status {
    var title: LocalizedStringKey {
        switch self {
        case .backlog: "Open"
        case .inProgress: "In Progress"
        case .blocked: "Blocked"
        case .review: "In Review"
        case .done: "Done"
        case .cancelled: "Cancelled"
        }
    }

    var symbol: String {
        switch self {
        case .backlog: "circle.dashed"
        case .inProgress: "circle.lefthalf.filled"
        case .blocked: "exclamationmark.circle"
        case .review: "eye.circle"
        case .done: "checkmark.circle"
        case .cancelled: "xmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .blocked: .orange
        case .inProgress: .accentColor
        case .backlog, .review, .done, .cancelled: .secondary
        }
    }
}
