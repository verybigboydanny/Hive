import SwiftUI

extension AttentionItem.Kind {
    var symbol: String {
        switch self {
        case .blockedTask: "exclamationmark.octagon"
        case .expiredLease: "clock.badge.exclamationmark"
        case .pendingHandoff: "arrow.left.arrow.right"
        }
    }

    var tint: Color {
        switch self {
        case .blockedTask, .expiredLease: .orange
        case .pendingHandoff: .accentColor
        }
    }
}
