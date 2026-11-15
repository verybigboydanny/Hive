import SwiftUI

extension HiveMessage.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .message: "Message"
        case .question: "Question"
        case .answer: "Answer"
        case .notice: "Notice"
        }
    }

    var tint: Color {
        switch self {
        case .question: .orange
        case .answer: .green
        case .notice, .message: .secondary
        }
    }
}
