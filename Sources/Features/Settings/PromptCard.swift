import SwiftUI

/// A prompt to paste into Claude, with what it is for.
struct PromptCard: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
            Text(title)
                .bold()
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            CodeBlock(text: prompt, wrapsLines: true)
        }
    }
}
