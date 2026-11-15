import SwiftUI

extension Agent.Status {
    var title: LocalizedStringKey {
        switch self {
        case .working: "Working"
        case .online: "Online"
        case .idle: "Idle"
        case .offline: "Offline"
        }
    }

    var color: Color {
        switch self {
        case .working, .online: .green
        case .idle: .secondary
        case .offline: Color.secondary.opacity(0.4)
        }
    }
}
