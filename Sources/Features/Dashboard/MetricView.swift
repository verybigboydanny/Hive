import SwiftUI

struct MetricView: View {
    let title: LocalizedStringKey
    let value: Int
    let detail: Text
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hiveAccent) private var accent

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value, format: .number)
                .font(.largeTitle.bold())
                .monospacedDigit()
                .foregroundStyle(accent.gradient)
                .contentTransition(.numericText())
                .animation(reduceMotion ? .easeOut(duration: 0.1) : .snappy(duration: 0.32), value: value)
            detail
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
