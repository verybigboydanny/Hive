import SwiftUI

/// Selectable monospaced text with a Copy button. Commands and JSON scroll sideways;
/// prompts wrap (`wrapsLines`).
struct CodeBlock: View {
    let text: String
    var wrapsLines = false

    var body: some View {
        HStack(alignment: .top, spacing: HiveMetrics.spacing) {
            if wrapsLines {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    Text(text)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            CopyButton(text: text)
        }
        .padding(HiveMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: HiveMetrics.cardRadius))
    }
}
