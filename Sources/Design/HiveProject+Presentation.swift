import SwiftUI

extension HiveProject.Status {
    var title: LocalizedStringKey {
        switch self {
        case .ready: "Ready"
        case .attention: "Needs Attention"
        case .disconnected: "Backend Disconnected"
        }
    }

    var color: Color {
        switch self {
        case .ready: .green
        case .attention: .orange
        case .disconnected: .red
        }
    }
}
