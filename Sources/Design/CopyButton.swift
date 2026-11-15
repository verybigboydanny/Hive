import SwiftUI
import AppKit

/// Copies text to the clipboard and briefly confirms it.
struct CopyButton: View {
    let text: String
    var title: LocalizedStringKey = "Copy"

    @State private var didCopy = false

    var body: some View {
        Button {
            copy()
        } label: {
            Label(didCopy ? LocalizedStringKey("Copied") : title, systemImage: didCopy ? "checkmark" : "doc.on.doc")
        }
        .controlSize(.small)
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopy = true
    }
}
