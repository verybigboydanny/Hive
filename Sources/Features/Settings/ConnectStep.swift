import SwiftUI

/// One numbered step of the Connect Claude guide.
struct ConnectStep<Content: View>: View {
    private let number: Int
    private let title: LocalizedStringKey
    private let content: Content

    @Environment(\.hiveAccent) private var accent

    init(number: Int, title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.number = number
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: HiveMetrics.spacingLoose) {
            Text(number, format: .number)
                .bold()
                .foregroundStyle(.black)
                .frame(width: HiveMetrics.stepBadgeSize, height: HiveMetrics.stepBadgeSize)
                .background(accent.gradient, in: .circle)
                .shadow(color: accent.color.opacity(0.4), radius: 5, y: 2)
                .accessibilityLabel("Step \(number)")
            VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
                Text(title)
                    .font(.headline)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .hiveAppear(delay: Double(number) * 0.05)
    }
}
