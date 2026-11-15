import SwiftUI

extension HiveTask.Priority {
    var title: LocalizedStringKey {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }

    var tint: Color {
        switch self {
        case .urgent: .red
        case .high: .orange
        case .normal, .low: .secondary
        }
    }
}
