import SwiftUI

/// A titled block of handoff text, hidden when empty.
struct HandoffTextSection: View {
    let title: LocalizedStringKey
    let text: String?

    var body: some View {
        if let text, !text.isEmpty {
            Section(title) {
                Text(text)
                    .textSelection(.enabled)
            }
            .hivePanelRows()
        }
    }
}
