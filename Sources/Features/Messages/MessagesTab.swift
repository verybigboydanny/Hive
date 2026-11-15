import Foundation

enum MessagesTab: String, CaseIterable, Identifiable {
    case messages, handoffs

    var id: String { rawValue }
}
