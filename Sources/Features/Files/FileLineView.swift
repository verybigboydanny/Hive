import SwiftUI

struct FileLineView: View {
    let line: NumberedLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HiveMetrics.spacingLoose) {
            Text(verbatim: String(line.id))
                .foregroundStyle(.tertiary)
                .frame(minWidth: HiveMetrics.lineNumberWidth, alignment: .trailing)
            Text(verbatim: line.text.isEmpty ? " " : line.text)
        }
    }
}
