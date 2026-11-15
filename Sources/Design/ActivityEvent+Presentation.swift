import Foundation

extension ActivityEvent.Kind {
    var symbol: String {
        switch self {
        case .fileModified: "doc.text"
        case .taskUpdated: "checklist"
        case .agentConnected: "person.crop.circle.badge.checkmark"
        case .agentDisconnected: "person.crop.circle.badge.minus"
        case .checkpoint: "flag"
        case .handoff: "arrow.left.arrow.right"
        case .message: "bubble.left"
        case .other: "ellipsis.circle"
        }
    }
}
