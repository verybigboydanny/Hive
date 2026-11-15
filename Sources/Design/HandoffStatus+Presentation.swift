import SwiftUI

extension Handoff.Status {
    var title: LocalizedStringKey {
        switch self {
        case .pending: "Pending"
        case .accepted: "Accepted"
        case .cancelled: "Cancelled"
        }
    }

    var tint: Color {
        switch self {
        case .pending: .orange
        case .accepted: .green
        case .cancelled: .secondary
        }
    }
}
