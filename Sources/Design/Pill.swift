import SwiftUI

/// A small rounded label for a status, priority or tag.
struct Pill: View {
    private let text: Text
    private let tint: Color

    init(_ title: LocalizedStringKey, tint: Color = .secondary) {
        self.text = Text(title)
        self.tint = tint
    }

    init(verbatim title: String, tint: Color = .secondary) {
        self.text = Text(verbatim: title)
        self.tint = tint
    }

    var body: some View {
        text
            .font(.callout)
            .foregroundStyle(tint)
            .padding(.horizontal, HiveMetrics.pillHorizontal)
            .padding(.vertical, HiveMetrics.pillVertical)
            .background(tint.opacity(0.14), in: .capsule)
    }
}
